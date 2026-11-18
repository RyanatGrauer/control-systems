# save_store.gd
#
# PURPOSE
#   The student's saved data (README 7.10): tuning snapshots per scenario,
#   settings, and (later) challenge results and lesson progress, kept in ONE
#   versioned JSON file under user://.
#
# SAFETY RULES (README 7.10, all enforced here)
#   * Plain data only. Saves are parsed as JSON, never loaded as Godot
#     resources/objects (a resource file can contain code).
#   * Everything loaded, whether from disk, an imported file or a pasted save
#     code, goes through validate(). Unknown keys are ignored; a bad value is
#     replaced by its default; a file that won't parse is renamed to a backup
#     (save.corrupt-<time>.json) instead of crashing, and defaults are used.
#   * Writes go to a temp file first, which then replaces the real one, so a
#     crash mid-save can't leave a half-written save. The file is closed right
#     after writing: on the Web, closing is what syncs it to IndexedDB.
#   * No quit-time save (browsers don't reliably give one): main_screen.gd
#     autosaves AUTOSAVE_DELAY_S after the last change instead.
#
# SCHEMA (version 1)
#   { "schema_version": 1,
#     "settings":  { see DisplaySettings.to_save() + "last_scenario" },
#     "snapshots": { scenario title: { "A".."D": { PID variable: number/bool } } },
#     "challenges": {}, "lessons": {} }   <- reserved for Milestone E
class_name SaveStore
extends RefCounted

const SCHEMA_VERSION: int = 1
const AUTOSAVE_DELAY_S: float = 1.5  # TUNABLE: wait this long after the last change
const SNAPSHOT_SLOTS: PackedStringArray = ["A", "B", "C", "D"]
const SAVE_CODE_PREFIX: String = "CLAB1:"   # marks (and versions) a pasted save code
const MAX_IMPORT_BYTES: int = 1_000_000     # refuse anything bigger: it isn't ours

# Where the save lives. Tests point this somewhere else so they never touch a
# real student save.
static var save_path: String = StoragePaths.get_save_folder() + "save.json"
# Tests that feed in a corrupt file on purpose turn the warning off.
static var print_warnings: bool = true

var data: Dictionary = default_data()


static func default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"settings": DisplaySettings.default_save().merged({"last_scenario": ""}),
		"snapshots": {},
		"challenges": {},
		"lessons": {},
	}


# --- disk ---

# Loads save_path. Returns a short message for the status line ("" if fine).
func load_from_disk() -> String:
	data = default_data()
	if not FileAccess.file_exists(save_path):
		return ""
	var text := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = _parse_json(text)
	if not parsed is Dictionary:
		var backup := save_path.get_basename() + ".corrupt-%d.json" % int(Time.get_unix_time_from_system())
		DirAccess.rename_absolute(save_path, backup)
		if print_warnings:
			push_warning("Save file could not be read; moved it to %s and started fresh." % backup)
		return "Your save file was damaged, so it was set aside and a fresh one started."
	data = validate(parsed)
	return ""


# Temp file first, then replace (see header). Returns true on success.
func write_to_disk() -> bool:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var temp_path := save_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write the save (%s)." % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()  # on the Web this is what flushes to IndexedDB
	return DirAccess.rename_absolute(temp_path, save_path) == OK


func reset_all() -> void:
	data = default_data()
	write_to_disk()


# --- import / export (all imports are untrusted: validate) ---

func to_json_text() -> String:
	return JSON.stringify(data, "\t")


# Returns "" on success, or a message saying why the text was rejected.
func import_json_text(text: String) -> String:
	if text.length() > MAX_IMPORT_BYTES:
		return "That file is too big to be a Control Lab save."
	var parsed: Variant = _parse_json(text)
	if not parsed is Dictionary or not (parsed as Dictionary).has("schema_version"):
		return "That isn't a Control Lab save file."
	data = validate(parsed)
	write_to_disk()
	return ""


# Compact text for copy/paste: prefix + base64(gzip(JSON)).
func to_save_code() -> String:
	var bytes := JSON.stringify(data).to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP)
	return SAVE_CODE_PREFIX + Marshalls.raw_to_base64(bytes)


func import_save_code(code: String) -> String:
	code = code.strip_edges()
	if not code.begins_with(SAVE_CODE_PREFIX):
		return "That isn't a Control Lab save code (it should start with %s)." % SAVE_CODE_PREFIX
	var bytes := Marshalls.base64_to_raw(code.substr(SAVE_CODE_PREFIX.length()))
	# Every gzip stream starts with the bytes 1F 8B; check before decompressing
	# so obvious junk is rejected quietly.
	if bytes.size() < 18 or bytes[0] != 0x1f or bytes[1] != 0x8b:
		return "That save code is damaged or incomplete. Try copying it again."
	var text := bytes.decompress_dynamic(MAX_IMPORT_BYTES, FileAccess.COMPRESSION_GZIP) \
			.get_string_from_utf8()
	if text == "":
		return "That save code is damaged or incomplete. Try copying it again."
	return import_json_text(text)


# JSON text -> Variant, or null if it doesn't parse. (JSON.parse_string would
# also print an engine error; a bad file is expected here, not a bug.)
static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


# --- validation and migration ---

# Builds a clean save from untrusted data, keeping only known keys with
# values of the right type.
static func validate(raw: Dictionary) -> Dictionary:
	raw = migrate(raw)
	var clean := default_data()
	var raw_settings: Variant = raw.get("settings")
	if raw_settings is Dictionary:
		var defaults: Dictionary = clean["settings"]
		for key: String in defaults:
			if (raw_settings as Dictionary).has(key):
				defaults[key] = _same_type(raw_settings[key], defaults[key])
	var raw_snapshots: Variant = raw.get("snapshots")
	if raw_snapshots is Dictionary:
		for title: Variant in raw_snapshots:
			var slots: Variant = raw_snapshots[title]
			if not title is String or not slots is Dictionary:
				continue
			var clean_slots := {}
			for slot: Variant in slots:
				if slot in SNAPSHOT_SLOTS and slots[slot] is Dictionary:
					clean_slots[slot] = clean_tuning(slots[slot])
			if not clean_slots.is_empty():
				clean["snapshots"][title] = clean_slots
	return clean


# A PID tuning with only real PidController variables, each converted to the
# variable's own type (JSON gives every number back as a float). A value of
# the wrong type is DROPPED, so loading the snapshot leaves that setting as is.
static func clean_tuning(raw: Dictionary) -> Dictionary:
	var template := PidController.new().get_tuning()
	var tuning := {}
	for key: String in template:
		if raw.has(key):
			var marker := {}  # a value no save can contain: means "rejected"
			var value: Variant = _same_type(raw[key], template[key], marker)
			if not is_same(value, marker):
				tuning[key] = value
	return tuning


# Older save formats are upgraded here, one version at a time. (Version 1 is
# the first; a missing version is treated as 1.)
static func migrate(raw: Dictionary) -> Dictionary:
	var raw_version: Variant = raw.get("schema_version", 1)
	var version := int(raw_version) if (raw_version is int or raw_version is float) else 1
	# if version == 1: raw = _migrate_1_to_2(raw); version = 2   <- future example
	raw["schema_version"] = maxi(version, SCHEMA_VERSION)
	return raw


# `value` converted to the type of `default`; if it can't be, returns
# `fallback` (which is `default` unless the caller passes something else).
static func _same_type(value: Variant, default: Variant, fallback: Variant = null) -> Variant:
	if fallback == null:
		fallback = default
	var is_number := (value is float or value is int) and is_finite(float(value))
	match typeof(default):
		TYPE_BOOL:
			return value if value is bool else fallback
		TYPE_INT:
			return int(value) if is_number else fallback
		TYPE_FLOAT:
			return float(value) if is_number else fallback
		TYPE_STRING:
			return value if value is String and (value as String).length() < 200 else fallback
	return fallback
