@tool
extends Node

#region Shaders Files

var void_function_regex := RegEx.create_from_string(r"^\s*void\s+(\w+)\s*\(\s*\)")

## List of every acompute shaders
var compute_shader_file_paths: Array[String] = []

## Shader name to file path (ex: "MyCompute" -> "res://shaders/MyCompute.acompute")
var compute_name_to_path: Dictionary[String, String] = {}

## Source cache for live reload
var shader_code_cache := {}

#endregion

#region Device Cache

## device_id (int) -> { compute_shader_name -> Array[RID] }
var device_compute_kernel_compilations: Dictionary[int, Dictionary] = {}

## device_id (int) -> weak ref to device (so we can recompile on changes)
var device_refs: Dictionary[int, WeakRef] = {}

#endregion

## Options
const USE_INCLUDE: bool = true # To allow the usage of includes until this proposal get accepted and completed: https://github.com/godotengine/godot-proposals/issues/6691
const HOT_RELOADING: bool = true

var AUTO_GLOBAL_COMPILE: bool = true:
	set(value):
		AUTO_GLOBAL_COMPILE = value
		
		if AUTO_GLOBAL_COMPILE:
			var global_rd: RenderingDevice = RenderingServer.get_rendering_device()
			register_device(global_rd)
			_compile_all_shaders_on_device(global_rd)

#region Utility
static func _device_id(rd: RenderingDevice) -> int:
	return rd.get_instance_id()

func _ensure_device_maps(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	if id not in device_compute_kernel_compilations:
		device_compute_kernel_compilations[id] = {} as Dictionary[String, Array]
	if id not in device_refs:
		device_refs[id] = weakref(rd)

func _free_device_compilations(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	assert(id in device_compute_kernel_compilations)
	
	for cname: String in device_compute_kernel_compilations[id]:
		for kernel_rid in device_compute_kernel_compilations[id][cname]:
			if kernel_rid.is_valid():
				rd.free_rid(kernel_rid)
	
	device_compute_kernel_compilations[id].clear()

func _compile_all_shaders_on_device(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	for shader_name: String in compute_name_to_path:
		if shader_name not in device_compute_kernel_compilations[id]:
			compile_shader_on_device(shader_name, rd)
#endregion

#region File Scan
func find_files(dir_name: String) -> void:
	var dir := DirAccess.open(dir_name)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			find_files(dir_name + "/" + file_name)
		else:
			var ext: String = file_name.get_extension()
			if ext == "acompute":
				var p: String = dir_name + "/" + file_name
				compute_shader_file_paths.push_back(p)
				compute_name_to_path[get_shader_name(p)] = p
			# If you want .glsl single-compute files, handle here similarly.
		file_name = dir.get_next()

func get_shader_name(file_path: String) -> String:
	return file_path.get_file().split(".")[0]
#endregion

#region Compilation
func _compile_acompute_on_device(compute_shader_file_path: String, rd: RenderingDevice) -> bool:
	var id: int = _device_id(rd)
	assert(id in device_refs)

	var compute_shader_name: String = get_shader_name(compute_shader_file_path)
	print("Compiling Compute Shader (device %s): %s" % [str(id), compute_shader_name])
	
	# Free any old kernels for this device/file
	if compute_shader_name in device_compute_kernel_compilations[id]:
		for krid: RID in device_compute_kernel_compilations[id][compute_shader_name]:
			if krid.is_valid():
				rd.free_rid(krid)
		device_compute_kernel_compilations[id][compute_shader_name].clear()
	
	# Read shader file
	var file := FileAccess.open(compute_shader_file_path, FileAccess.READ)
	var raw_shader_code_string: String = file.get_as_text()
	shader_code_cache[compute_shader_file_path] = raw_shader_code_string

	var raw_lines: PackedStringArray = raw_shader_code_string.split("\n")
	var kernel_names: Array[String]
	var kernel_to_thread_group: Dictionary[String, Array] # kname -> [x,y,z]
	
	var current_line_index: int = 0
	
	# Read reconized preprocessed instructions
	var line_counter : int = 0
	while line_counter < raw_lines.size():
		var line: String = raw_lines[line_counter]
		
		if line.begins_with("#kernel "):
			if line_counter + 1 >= raw_lines.size():
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: #kernel instruction at end of file")
				return false
			
			var kernel_declaration_line: String = raw_lines[line_counter + 1]
			
			var regex_match: RegExMatch = void_function_regex.search(kernel_declaration_line)
			if not regex_match:
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: #kernel instruction must be placed before a valid void function")
				return false
			
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
					return false
				
				kernel_to_thread_group[kernel_name] = [] as Array[String]
				for n in thread_groups.size():
					kernel_to_thread_group[kernel_name].push_back((thread_groups[n].strip_edges()))
			else:
				push_error("Failed to compile: " + compute_shader_file_path)
				push_error("Reason: kernel thread group count not found")
				return false
		
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
		return false

	if raw_lines.is_empty():
		push_error("Failed to compile: " + compute_shader_file_path)
		push_error("Reason: No shader code found")
		return false
	
	#TODO: Better than join everything to find a simple kernel name
	var body_str: String = "\n".join(raw_lines)
	for kname: String in kernel_names:
		if not body_str.contains(kname):
			push_error("Failed to compile: " + compute_shader_file_path)
			push_error("Reason: " + kname + " kernel not found!")
			return false
	
	# Compile each kernel
	var kernels: Array[RID]
	for kname: String in kernel_names:
		var lines := PackedStringArray(raw_lines)
		
		var tg := kernel_to_thread_group[kname]
		lines.insert(0, "layout(local_size_x = %s, local_size_y = %s, local_size_z = %s) in;" % [tg[0], tg[1], tg[2]])
		lines.insert(0, "#version 450")
		
		var code := "\n".join(lines).replace(kname, "main")
		
		var src := RDShaderSource.new()
		src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		src.source_compute = code
		var spirv := rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error(spirv.compile_error_compute)
			push_error("In: " + code)
			return false
		
		var shader_rid := rd.shader_create_from_spirv(spirv)
		if not shader_rid.is_valid():
			return false
		
		print("- Compiling Kernel (device %s): %s" % [str(id), kname])
		kernels.push_back(shader_rid)
	
	device_compute_kernel_compilations[id][compute_shader_name] = kernels
	return true
#endregion

#region Public API
## Must be called at least once per device (global or local).
func register_device(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	if id not in device_refs:
		_ensure_device_maps(rd)

## Must be called before a registered RenderingDevice is freed.
func unregister_device(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	_free_device_compilations(rd)
	device_refs.erase(id)

## Precompile a shader on a device.
func compile_shader_on_device(shader_name: String, rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	assert(id in device_refs)
	assert(HOT_RELOADING or shader_name not in device_compute_kernel_compilations[id] or device_compute_kernel_compilations[id][shader_name].is_empty(), "Shader \"%s\" already compiled on device." % [shader_name])
	assert(shader_name in compute_name_to_path, "Shader \"%s\" not found." % [shader_name])
	
	var success: bool = _compile_acompute_on_device(compute_name_to_path[shader_name], rd)
	if not success:
		device_compute_kernel_compilations[id][shader_name] = [] as Array[RID]

## Get all kernel RIDs (Array[RID]) for a specific device.
## If shader was not compiled for this device, we compile on demand.
func get_compute_kernel_compilations_for_device(shader_name: String, rd: RenderingDevice) -> Array[RID]:
	var id: int = _device_id(rd)
	assert(id in device_refs)
	
	if shader_name not in device_compute_kernel_compilations[id]:
		# Compile on demand
		compile_shader_on_device(shader_name, rd)
	
	return device_compute_kernel_compilations[id][shader_name] as Array[RID]

## Return the device shader id. For convenience, we use the first compiled kernel RID.
func get_device_shader_id(shader_name: String, rd: RenderingDevice) -> RID:
	var id: int = _device_id(rd)
	assert(id in device_refs)
	
	# In case compilation failed, return an invalid RID
	var kernels: Array[RID] = device_compute_kernel_compilations[id].get(shader_name, [])
	if kernels.is_empty():
		return RID()
	
	return device_compute_kernel_compilations[id][shader_name][0]
#endregion

#region Life Cycle
func _init() -> void:
	# Initial scan
	find_files("res://")
	
	# Register the Global Rendering Device
	var global_rd: RenderingDevice = RenderingServer.get_rendering_device()
	register_device(global_rd)
	
	if AUTO_GLOBAL_COMPILE:
		_compile_all_shaders_on_device(global_rd)

func _physics_process(delta: float) -> void:
	if not HOT_RELOADING: return
	
	# Live reload for all registered devices
	for shader_name: String in compute_name_to_path:
		var file_path: String = compute_name_to_path[shader_name]
		
		#TODO: Better way to verify if file got edited
		var current := FileAccess.open(file_path, FileAccess.READ).get_as_text()
		if shader_code_cache.get(file_path, "") != current:
			shader_code_cache[file_path] = current
			
			# Recompile on all devices that use this shader
			for device_id: int in device_compute_kernel_compilations:
				var kernel_compilations: Dictionary[String, Array] = device_compute_kernel_compilations[device_id]
				
				if shader_name in kernel_compilations:
					var wr: WeakRef = device_refs[device_id]
					var rd: RenderingDevice = wr.get_ref() if wr else null
					assert(rd != null, "Rendering device freed witout calling \"unregister_device\".")
					
					#_compile_acompute_on_device(file_path, rd)
					compile_shader_on_device(shader_name, rd)

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# Free all per-device resources
		for id: int in device_refs:
			var rd := device_refs[id].get_ref()
			if rd:
				_free_device_compilations(rd)
#endregion
