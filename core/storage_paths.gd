# storage_paths.gd
#
# PURPOSE
#   The ONE place that decides where Control Lab stores files (saves, settings,
#   exported runs). Nothing else in the project should build user:// paths.
#
# WHY THIS MATTERS ON ITCH.IO (README 7.11)
#   On the Web build, Godot keeps user:// inside ONE browser IndexedDB database
#   named "/userfs", and every Godot game on itch.io's shared hosting domain
#   uses that same database. Games are kept apart only by the folder name inside
#   it, which comes from the project setting
#       application/config/custom_user_dir_name = "control_lab_7f3k2q"
#   VERIFIED in a Web build (Chrome, Godot 4.7.2): user:// resolves to
#   "/userfs/control_lab_7f3k2q". On desktop it resolves to the normal app-data
#   folder with the same name.
#
#   DO NOT change that project setting (or turn off use_custom_user_dir) after
#   release: students' existing saves would be orphaned.
#   check_storage_location() warns at startup if the setting was lost.
class_name StoragePaths
extends RefCounted

# Must match application/config/custom_user_dir_name in project.godot.
const STORAGE_ID: String = "control_lab_7f3k2q"


static func get_save_folder() -> String:
	return "user://"


# True if user:// really is our uniquely named folder. If someone disables the
# custom user directory, Web saves could collide with other itch.io games.
static func check_storage_location() -> bool:
	var is_unique := OS.get_user_data_dir().get_file() == STORAGE_ID
	if not is_unique:
		push_warning("user:// is '%s', not a folder named '%s'. Check the project setting application/config/custom_user_dir_name." % [OS.get_user_data_dir(), STORAGE_ID])
	return is_unique
