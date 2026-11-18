# save_panel.gd
#
# PURPOSE
#   The "Save & export" panel (README 7.8, 7.10, 7.11):
#     * Export run (CSV)    the current run, for a spreadsheet or Python.
#     * Export / Import save file   backup or move to another computer.
#     * Copy / Paste save code      the same, as text through the clipboard
#                                   (works everywhere, even if downloads or the
#                                   file picker are blocked).
#     * Reset all progress  with a confirmation step.
#   Saving itself is automatic; the status line says when it last happened.
#
# HOW IT FITS
#   Uses SaveStore for the data and WebPlatform (browser) or FileDialog
#   (desktop) for files. Emits save_replaced after an import or reset so
#   main_screen.gd re-applies settings and snapshots.
class_name SavePanel
extends VBoxContainer

signal save_replaced

var _store: SaveStore
var _make_csv: Callable   # () -> [file_name, csv_text]
var _status: Label
var _paste_dialog: AcceptDialog
var _paste_box: TextEdit
var _copy_dialog: AcceptDialog
var _copy_box: TextEdit
var _reset_dialog: ConfirmationDialog
var _file_dialog: FileDialog


func setup(store: SaveStore, make_csv: Callable) -> void:
	_store = store
	_make_csv = make_csv
	add_theme_constant_override("separation", 9)

	_add_button("Export run (CSV)", "Download this run's data (time, setpoint, measurement, terms...) for a spreadsheet or Python.",
			_on_export_csv)
	_add_hint("Saving is automatic. Export a backup now and then: clearing browser data deletes it.")
	var file_row := HBoxContainer.new()
	add_child(file_row)
	_add_button("Export save", "Download your save as a .json file (backup or move to another computer).",
			_on_export_save, file_row)
	_add_button("Import save", "Load a save file you exported earlier. Replaces your current save.",
			_on_import_save, file_row)
	var code_row := HBoxContainer.new()
	add_child(code_row)
	_add_button("Copy save code", "Your save as text, to paste somewhere safe (or into another computer).",
			_on_copy_code, code_row)
	_add_button("Paste save code", "Load a save from a code copied earlier.", _on_paste_code, code_row)
	var reset_button := _add_button("Reset all progress...", "Delete all saved tunings and settings (asks first).",
			func() -> void: _reset_dialog.popup_centered())
	reset_button.add_theme_color_override("font_color", SignalColors.WARNING_TEXT)

	_status = UiStyle.make_hint("")
	add_child(_status)
	_build_dialogs()


func show_status(text: String) -> void:
	_status.text = text


# --- actions ---

func _on_export_csv() -> void:
	var file: Array = _make_csv.call()
	_save_text_file(file[0], file[1], "text/csv", "*.csv ; CSV files")


func _on_export_save() -> void:
	_save_text_file("control_lab_save.json", _store.to_json_text(), "application/json",
			"*.json ; Control Lab saves")


func _on_import_save() -> void:
	if WebPlatform.is_web():
		WebPlatform.pick_text_file(".json,application/json", _import_text)
	else:
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.filters = PackedStringArray(["*.json ; Control Lab saves"])
		_file_dialog.current_file = ""
		_file_dialog.popup_centered_ratio(0.7)


func _on_copy_code() -> void:
	var code := _store.to_save_code()
	DisplayServer.clipboard_set(code)
	# Also show it, in case the browser blocked clipboard access.
	_copy_box.text = code
	_copy_dialog.popup_centered(Vector2i(800, 400))
	show_status("Save code copied to the clipboard.")


func _on_paste_code() -> void:
	_paste_box.text = ""
	_paste_dialog.popup_centered(Vector2i(800, 400))
	_paste_box.grab_focus()


func _import_text(text: String) -> void:
	var problem := _store.import_json_text(text)
	_after_import(problem)


func _after_import(problem: String) -> void:
	if problem != "":
		show_status(problem)
		return
	show_status("Save loaded.")
	save_replaced.emit()


# Desktop: FileDialog; Web: browser download.
func _save_text_file(file_name: String, text: String, mime_type: String, filter: String) -> void:
	if WebPlatform.is_web():
		WebPlatform.download_text(file_name, text, mime_type)
		show_status("Downloaded %s." % file_name)
		return
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.filters = PackedStringArray([filter])
	_file_dialog.current_file = file_name
	_file_dialog.set_meta("text", text)
	_file_dialog.popup_centered_ratio(0.7)


func _on_file_chosen(path: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			show_status("Could not write %s." % path)
			return
		file.store_string(_file_dialog.get_meta("text"))
		file.close()
		show_status("Saved %s." % path.get_file())
	else:
		var file_size := FileAccess.open(path, FileAccess.READ).get_length() if FileAccess.file_exists(path) else 0
		if file_size > SaveStore.MAX_IMPORT_BYTES:
			show_status("That file is too big to be a Control Lab save.")
			return
		_import_text(FileAccess.get_file_as_string(path))


# --- building ---

func _build_dialogs() -> void:
	_reset_dialog = ConfirmationDialog.new()
	_reset_dialog.title = "Reset all progress?"
	_reset_dialog.dialog_text = "This deletes every saved tuning snapshot and setting on this computer/browser.\nIt can't be undone (unless you exported a backup)."
	_reset_dialog.ok_button_text = "Delete everything"
	_reset_dialog.confirmed.connect(func() -> void:
		_store.reset_all()
		show_status("All progress was reset.")
		save_replaced.emit())
	add_child(_reset_dialog)

	_copy_dialog = AcceptDialog.new()
	_copy_dialog.title = "Your save code"
	_copy_box = _make_code_box(_copy_dialog, "Copied to the clipboard. If not, select it all and copy.")
	_copy_box.editable = false
	_copy_box.add_theme_color_override("font_readonly_color", Color.WHITE)
	add_child(_copy_dialog)

	_paste_dialog = AcceptDialog.new()
	_paste_dialog.title = "Paste a save code"
	_paste_dialog.ok_button_text = "Load it"
	_paste_dialog.add_cancel_button("Cancel")
	_paste_box = _make_code_box(_paste_dialog, "Paste (Ctrl+V / Cmd+V) the code below. It replaces your current save.")
	_paste_dialog.confirmed.connect(func() -> void:
		_after_import(_store.import_save_code(_paste_box.text)))
	add_child(_paste_dialog)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_file_chosen)
	add_child(_file_dialog)


func _make_code_box(dialog: AcceptDialog, hint: String) -> TextEdit:
	var column := VBoxContainer.new()
	var label := Label.new()
	label.text = hint
	column.add_child(label)
	var box := TextEdit.new()
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.custom_minimum_size = Vector2(740.0, 240.0)
	column.add_child(box)
	dialog.add_child(column)
	return box


func _add_button(text: String, tooltip: String, on_pressed: Callable,
		parent: Control = self) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(on_pressed)
	parent.add_child(button)
	return button


func _add_hint(text: String) -> void:
	add_child(UiStyle.make_hint(text))
