# web_platform.gd
#
# PURPOSE
#   ALL browser-specific code lives here (README 7.11), so desktop builds never
#   touch JavaScriptBridge. Every function checks is_web() first.
#     * download_text()      browser download of a generated file (CSV, save).
#     * pick_text_file()     opens the browser's file picker and hands the
#                            chosen file's text back to GDScript.
#     * request_persistent_storage()  asks the browser not to evict our saves
#                            (often refused inside itch.io's iframe; harmless).
#
# HOW IT FITS
#   ui/save_panel.gd calls these on the Web and uses Godot's FileDialog on
#   desktop instead.
class_name WebPlatform
extends RefCounted

# The JavaScript callback must stay referenced while the picker is open, or
# Godot frees it and the browser's call goes nowhere.
static var _file_callback: JavaScriptObject
static var _on_file_text: Callable


static func is_web() -> bool:
	return OS.has_feature("web")


static func download_text(file_name: String, text: String, mime_type: String) -> void:
	if not is_web():
		return
	JavaScriptBridge.download_buffer(text.to_utf8_buffer(), file_name, mime_type)


# Opens the file picker; later calls on_text(text) with the file's contents.
# (If the student cancels, nothing is called.)
static func pick_text_file(accept: String, on_text: Callable) -> void:
	if not is_web():
		return
	_on_file_text = on_text
	_file_callback = JavaScriptBridge.create_callback(_receive_file_text)
	var window := JavaScriptBridge.get_interface("window")
	window.controlLabReceiveFile = _file_callback
	# A hidden <input type=file>; when a file is chosen, read it as text and
	# pass it to the GDScript callback above. Files over 1 MB are ignored
	# (a real save is a few kB).
	JavaScriptBridge.eval("""
		(function () {
			const input = document.createElement('input');
			input.type = 'file';
			input.accept = '%s';
			input.onchange = function () {
				const file = input.files && input.files[0];
				if (!file || file.size > 1000000) { return; }
				file.text().then(function (text) { window.controlLabReceiveFile(text); });
			};
			input.click();
		})();
	""" % accept.c_escape(), true)


static func _receive_file_text(arguments: Array) -> void:
	if arguments.is_empty() or not _on_file_text.is_valid():
		return
	_on_file_text.call(str(arguments[0]))


static func request_persistent_storage() -> void:
	if not is_web():
		return
	JavaScriptBridge.eval(
		"if (navigator.storage && navigator.storage.persist) { navigator.storage.persist(); }", true)
