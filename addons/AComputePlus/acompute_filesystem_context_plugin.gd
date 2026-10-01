@tool
extends EditorContextMenuPlugin


var _file_dialog: EditorFileDialog

const DEFAULT_SHADER_CODE := """\

#kernel [numthreads(1024, 1, 1)]
void kernel_name() {
	// Your compute shader code here
}
"""

func _popup_menu(paths: PackedStringArray) -> void:
	var prefix: String = ""
	if paths.is_empty():
		prefix = "New "
	
	add_context_menu_item(prefix + "ACompute Shader...", _create_compute_shader, preload("ACShader.svg"))
	add_context_menu_item(prefix + "ACompute Shader Include...", _create_compute_shader_include, preload("ACShaderInclude.svg"))

func _create_compute_shader(paths: PackedStringArray) -> void:
	if paths.is_empty(): return

	var directory: String = paths[0]
	
	_create_file_dialog(directory, "new_shader", "acompute", "ACompute Shader", true)

func _create_compute_shader_include(paths: PackedStringArray) -> void:
	if paths.is_empty(): return
	
	var directory: String = paths[0]
	
	_create_file_dialog(directory, "new_shader_include", "acomputeinc", "ACompute Shader Include", false)

func _create_file_dialog(initial_dir: String, initial_name: String, filter_ext: String, filter_name: String, use_default_code: bool) -> void:
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.current_dir = initial_dir
	_file_dialog.current_file = "%s.%s" % [initial_name, filter_ext]
	_file_dialog.add_filter("*.%s" % filter_ext, filter_name)
	
	_file_dialog.file_selected.connect(_on_file_selected.bind(filter_ext, use_default_code))
	_file_dialog.canceled.connect(_free_file_dialog)

	EditorInterface.get_base_control().add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.5)

func _on_file_selected(path: String, ext: String, use_default_code: bool) -> void:
	if not path.ends_with(".%s" % ext):
		path += ".%s" % ext
	
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_free_file_dialog()
		push_error("Could not create: " + path)
		return
	
	file.store_string(DEFAULT_SHADER_CODE if use_default_code else "")
	file.close()
	
	EditorInterface.get_resource_filesystem().scan()
	
	_free_file_dialog()

func _free_file_dialog() -> void:
	_file_dialog.queue_free()
	_file_dialog = null
