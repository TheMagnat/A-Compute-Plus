@tool
extends EditorImportPlugin

var void_function_regex := RegEx.create_from_string(r"^\s*void\s+(\w+)\s*\(\s*\)")

func _get_importer_name() -> String:
	return "ACompute.acompute"

func _get_visible_name() -> String:
	return "ACompute Shader"

func _get_recognized_extensions() -> PackedStringArray:
	return ["acompute"]

func _get_save_extension() -> String:
	return "tres"

func _get_resource_type() -> String:
	return "AComputeShader"

func _get_preset_count() -> int:
	return 0

func _get_import_options(_path: String, _preset_index: int) -> Array[Dictionary]:
	#return [{"name": "my_option", "default_value": false}]
	return []

func _get_import_order() -> int:
	# Since we want the include files to be imported first,
	# we set a higher order (lower priority) to AComputeShader.
	return 1

func _import(
	source_file: String, save_path: String, _options: Dictionary,
	_platform_variants: Array[String], _gen_files: Array[String]
) -> Error:
	var error: Error
	
	var compute_shader := AComputeShader.new()
	error = _parse_acompute(compute_shader, source_file)
	if error != OK:
		push_warning("Failed to compile %s" % source_file)
	
	error = ResourceSaver.save(compute_shader, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		return error
	
	print("Imported and parsed %s." % [source_file])
	
	return OK

#region Parsing
func _get_shader_name(file_path: String) -> String:
	return file_path.get_file().split(".")[0]

func _parse_acompute(acompute_shader: AComputeShader, compute_shader_file_path: String) -> Error:
	var use_includes: bool = ProjectSettings.get_setting("AComputePlus/use_includes", true)
	
	# Get the name
	acompute_shader.shader_name = _get_shader_name(compute_shader_file_path)
	
	var raw_shader_code_string: String = FileAccess.get_file_as_string(compute_shader_file_path)
	if FileAccess.get_open_error() != OK:
		return FileAccess.get_open_error()
	
	var includes: Array[AComputeShaderInclude]
	
	var raw_lines: PackedStringArray = raw_shader_code_string.split("\n")
	var kernel_names: Array[String]
	var kernel_thread_groups: Array[PackedInt32Array] # kernel index -> [x,y,z]
	
	# Read reconized preprocessed instructions
	var line_counter : int = 0
	while line_counter < raw_lines.size():
		var line: String = raw_lines[line_counter]
		
		if line.begins_with("#kernel "):
			if line_counter + 1 >= raw_lines.size():
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: #kernel instruction at end of file")
				return FAILED
			
			var kernel_declaration_line: String = raw_lines[line_counter + 1]
			
			var regex_match: RegExMatch = void_function_regex.search(kernel_declaration_line)
			if not regex_match:
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: #kernel instruction must be placed before a valid void function")
				return FAILED
			
			var kernel_name: String = regex_match.get_string(1)
			
			# Extract thread groups
			if not line.contains('numthreads'):
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: kernel thread group count not found")
				return FAILED
			
			var thread_groups: PackedStringArray = line.split('(')[-1].split(')')[0].split(',')
			if thread_groups.size() != 3:
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: #kernel thread group syntax error")
				return FAILED
			
			var thread_group := PackedInt32Array()
			for n in thread_groups.size():
				thread_group.push_back(int(thread_groups[n]))
			
			kernel_names.push_back(kernel_name)
			kernel_thread_groups.push_back(thread_group)
			
			raw_lines.remove_at(line_counter)
			line_counter -= 1
			
		elif use_includes and line.begins_with("#include "):
			var include_path: String = line.split("#include")[1].strip_edges()
			var path: String = include_path.substr(1, include_path.length() - 2)
			
			if not path.begins_with("res://"):
				path = compute_shader_file_path.get_base_dir().path_join(path)
			
			var shader_include: AComputeShaderInclude = load(path)
			if not shader_include:
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: Can't find #include file at path: %s" % path)
				return FAILED
			
			includes.push_back(shader_include)
			
			var include_file := FileAccess.open(path, FileAccess.READ)
			var raw_include_lines: PackedStringArray = include_file.get_as_text().split("\n")
			
			raw_lines = raw_lines.slice(0, line_counter) + raw_include_lines + raw_lines.slice(line_counter + 1, raw_lines.size())
			line_counter += raw_include_lines.size()
		
		line_counter += 1
	
	if kernel_names.is_empty():
		push_error("Failed to compile: " + compute_shader_file_path)
		push_error("Reason: No kernels found")
		return FAILED

	if raw_lines.is_empty():
		push_error("Failed to compile: " + compute_shader_file_path)
		push_error("Reason: No shader code found")
		return FAILED
	
	#TODO: Better than join everything to find a simple kernel name
	var body_str: String = "\n".join(raw_lines)
	for kname: String in kernel_names:
		if not body_str.contains(kname):
			push_error("Failed to compile: " + compute_shader_file_path)
			push_error("Reason: " + kname + " kernel not found!")
			return FAILED
	
	# Compile each kernel
	var kernels_spirv: Array[RDShaderSPIRV]
	for i: int in kernel_names.size():
		var kernel_name: String = kernel_names[i]
		var tg: PackedInt32Array = kernel_thread_groups[i]
		
		var base_code : String = "#version 450\n" \
			+ "layout(local_size_x = %d, local_size_y = %d, local_size_z = %d) in;" % [tg[0], tg[1], tg[2]] \
			+ "\n".join(raw_lines)
		
		var code: String = base_code.replace(kernel_name, "main")
		
		var src := RDShaderSource.new()
		src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src.source_compute = code
		
		## You can deactivate cache her for testing purposes
		var spirv: RDShaderSPIRV = RenderingServer.get_rendering_device().shader_compile_spirv_from_source(src, true)
		if spirv.compile_error_compute != "":
			push_error(spirv.compile_error_compute)
			push_error("In: " + code)
			return FAILED
		
		kernels_spirv.push_back(spirv)
		
		print("- Compiling to SPIR-V Kernel : %s" % [kernel_name])
	
	acompute_shader.kernel_names = kernel_names
	acompute_shader.kernel_thread_groups = kernel_thread_groups
	acompute_shader.kernel_spirv = kernels_spirv
	
	# Link this shader path to all its includes to reimport it if an include changes
	for include: AComputeShaderInclude in includes:
		pass
		#TODO: This line allow hot reloading when editing an include file.
		#      However, there is currently a bug when calling append_import_external_resource.
		#      It make the current resource not emit its changed signal, making the hot reload
		#      fail since it's based on this event to detect a change. I reported the bug here
		#      https://github.com/godotengine/godot/issues/123950 or we wait for it to be fixed
		#      or we find a workaround.
		#append_import_external_resource(include.resource_path, {"parent_shader": compute_shader_file_path})
	
	return OK
#endregion
