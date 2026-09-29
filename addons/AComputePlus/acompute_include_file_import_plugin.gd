@tool
extends EditorImportPlugin

var void_function_regex := RegEx.create_from_string(r"^\s*void\s+(\w+)\s*\(\s*\)")

func _get_importer_name() -> String:
	return "ACompute.acomputeinc"

func _get_visible_name() -> String:
	return "ACompute Shader Include"

func _get_recognized_extensions() -> PackedStringArray:
	return ["acomputeinc"]

func _get_save_extension() -> String:
	return "tres"

func _get_resource_type() -> String:
	return "AComputeShaderInclude"

func _get_preset_count() -> int:
	return 0

func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	return []

func _import(
	source_file: String, save_path: String, options: Dictionary,
	_platform_variants: Array[String], _gen_files: Array[String]
) -> Error:
	var error: Error
	
	var old_shader_include: AComputeShaderInclude = load(source_file)
	var linked_shaders_path: PackedStringArray
	if old_shader_include:
		linked_shaders_path = old_shader_include.linked_shaders_path
		old_shader_include = null
	else:
		linked_shaders_path = PackedStringArray()
	
	var new_shader_include := AComputeShaderInclude.new()
	# Note: Old linked shader will add themself to the linked list while reimporting
	
	# If called by a "parent" shader, add its path to our list
	var called_from_shader_importer: bool = "parent_shader" in options
	if called_from_shader_importer:
		var shader_path: String = options["parent_shader"]
		
		if shader_path not in linked_shaders_path:
			linked_shaders_path.push_back(shader_path)
		
		new_shader_include.linked_shaders_path = linked_shaders_path
	
	error = ResourceSaver.save(new_shader_include, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		return error
	
	# Only reimport if not called from a "parent" shader to prevent infinite import loop
	if not called_from_shader_importer and linked_shaders_path:
		_reimport_linked_shaders(linked_shaders_path)
	
	return OK

#region Parsing
func _get_shader_name(file_path: String) -> String:
	return file_path.get_file().split(".")[0]

func _reimport_linked_shaders(linked_shaders_path: PackedStringArray) -> void:
	assert(linked_shaders_path)
	
	for path: String in linked_shaders_path:
		if ResourceLoader.exists(path, "AComputeShader"):
			append_import_external_resource(path)
		else:
			push_warning("%s not found and will not be recompiled." % path)
#endregion
