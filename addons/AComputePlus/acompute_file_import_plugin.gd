@tool
extends EditorImportPlugin

var void_function_regex := RegEx.create_from_string(r"^\s*void\s+(\w+)\s*\(\s*\)")

const USE_INCLUDE: bool = true # To allow the usage of includes until this proposal get accepted and completed: https://github.com/godotengine/godot-proposals/issues/6691

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

func _import(
	source_file: String, save_path: String, _options: Dictionary,
	_platform_variants: Array[String], _gen_files: Array[String]
) -> Error:
	var error: Error
	
	print("Save path: ", save_path)
	
	var compute_shader := AComputeShader.new()
	error = _parse_acompute(compute_shader, source_file)
	if error != OK:
		return error
	
	error = ResourceSaver.save(compute_shader, "%s.%s" % [save_path, _get_save_extension()])
	if error != OK:
		return error
	
	print("Imported and parsed %s." % [source_file])
	
	return OK

func get_shader_name(file_path: String) -> String:
	return file_path.get_file().split(".")[0]

func _parse_acompute(acompute_shader: AComputeShader, compute_shader_file_path: String) -> Error:
	# Get the name
	acompute_shader.shader_name = get_shader_name(compute_shader_file_path)
	
	var raw_shader_code_string: String = FileAccess.get_file_as_string(compute_shader_file_path)
	if FileAccess.get_open_error() != OK:
		return FileAccess.get_open_error()
	
	var raw_lines: PackedStringArray = raw_shader_code_string.split("\n")
	var kernel_names: Array[String]
	var kernel_to_thread_group: Dictionary[String, PackedStringArray] # kname -> [x,y,z]
	
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
			
			kernel_names.push_back(kernel_name)
			raw_lines.remove_at(line_counter)
			line_counter -= 1
			
			# Extract thread groups
			if line.contains('numthreads'):
				var thread_groups = line.split('(')[-1].split(')')[0].split(',')
				if thread_groups.size() != 3:
					push_error("Failed to compile: " + compute_shader_file_path)
					push_error("Reason: #kernel thread group syntax error")
					return FAILED
				
				kernel_to_thread_group[kernel_name] = PackedStringArray()
				for n in thread_groups.size():
					kernel_to_thread_group[kernel_name].push_back((thread_groups[n].strip_edges()))
			else:
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: kernel thread group count not found")
				return FAILED
		
		elif USE_INCLUDE and line.begins_with("#include "):
			var include_path: String = line.split("#include")[1].strip_edges()
			var path: String = include_path.substr(1, include_path.length() - 2)
			
			if not path.begins_with("res://"):
				path = compute_shader_file_path.get_base_dir().path_join(path)
			
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
	
	acompute_shader.code = "\n".join(raw_lines)
	acompute_shader.kernel_names = kernel_names
	acompute_shader.kernel_to_thread_group = kernel_to_thread_group
	
	return OK
