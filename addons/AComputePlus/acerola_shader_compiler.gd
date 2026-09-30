@tool
extends Node

#region Device Cache

## device_id (int) -> { AComputeShader -> Array[RID] }
var device_compute_kernel_compilations: Dictionary[int, Dictionary] = {}

## device_id (int) -> weak ref to device (so we can recompile on changes)
var device_refs: Dictionary[int, WeakRef] = {}

#endregion

## Options
@export var HOT_RELOADING: bool = false:
	set(value):
		if value == HOT_RELOADING: return
		
		HOT_RELOADING = value
		
		if HOT_RELOADING:
			_hot_reload_register_all()
		else:
			_hot_reload_unregister_all()

@export var AUTO_GLOBAL_COMPILE: bool = false:
	set(value):
		if value == AUTO_GLOBAL_COMPILE: return
		
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
		device_compute_kernel_compilations[id] = {} as Dictionary[AComputeShader, Array]
	if id not in device_refs:
		device_refs[id] = weakref(rd)

func _free_device_compilations(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	assert(id in device_compute_kernel_compilations)
	
	for shader: AComputeShader in device_compute_kernel_compilations[id]:
		for kernel_rid: RID in device_compute_kernel_compilations[id][shader]:
			if kernel_rid.is_valid():
				rd.free_rid(kernel_rid)
	
	device_compute_kernel_compilations[id].clear()

func _compile_all_shaders_on_device(rd: RenderingDevice) -> void:
	var id: int = _device_id(rd)
	for shader: AComputeShader in _scan_root_acompute_shaders():
		if shader not in device_compute_kernel_compilations[id]:
			compile_shader_on_device(shader, rd)

## Helper method to return every AComputeShader in the filesystem
func _scan_root_acompute_shaders() -> Array[AComputeShader]:
	var res: Array[AComputeShader]
	
	_scan_acompute_shaders("res://", res)
	
	return res

func _scan_acompute_shaders(dir_name: String, res: Array[AComputeShader]) -> Array[AComputeShader]:
	var dir := DirAccess.open(dir_name)
	if not dir:
		return res
	
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			_scan_acompute_shaders(dir_name + "/" + file_name, res)
		else:
			var ext: String = file_name.get_extension()
			if ext == "acompute":
				var p: String = dir_name + "/" + file_name
				res.push_back(load(p))
		
		file_name = dir.get_next()
	
	return res
#endregion

#region Compilation
func _compile_acompute_on_device(shader: AComputeShader, rd: RenderingDevice) -> bool:
	var id: int = _device_id(rd)
	assert(id in device_refs)
	
	# Free any old kernels for this device/file
	if shader in device_compute_kernel_compilations[id]:
		for krid: RID in device_compute_kernel_compilations[id][shader]:
			if krid.is_valid():
				rd.free_rid(krid)
		@warning_ignore("unsafe_method_access")
		device_compute_kernel_compilations[id][shader].clear()
	
	if shader.kernel_spirv.is_empty():
		print("[AC] Skipped empty Compute Shader (device %d): %s" % [id, shader.shader_name])
		return false
	
	print("[AC] Compiling Compute Shader (device %d): %s" % [id, shader.shader_name])
	
	# Compile each kernel
	var kernels: Array[RID]
	for i: int in shader.kernel_spirv.size():
		var spirv: RDShaderSPIRV = shader.kernel_spirv[i]
		
		var shader_rid := rd.shader_create_from_spirv(spirv, "%s_%s" % [shader.shader_name, shader.kernel_names[i]])
		if not shader_rid.is_valid():
			return false
		
		print("[AC] - Compiling Kernel (device %d): %s" % [id, shader.kernel_names[i]])
		kernels.push_back(shader_rid)
	
	device_compute_kernel_compilations[id][shader] = kernels
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
func compile_shader_on_device(shader: AComputeShader, rd: RenderingDevice) -> void:
	if HOT_RELOADING:
		_hot_reload_register_shader(shader)
	
	var id: int = _device_id(rd)
	assert(id in device_refs)
	@warning_ignore("unsafe_method_access")
	assert(HOT_RELOADING or shader not in device_compute_kernel_compilations[id] or device_compute_kernel_compilations[id][shader].is_empty(), "Shader \"%s\" already compiled on device." % [shader.shader_name])
	#assert(shader in compute_name_to_path, "Shader \"%s\" not found." % [shader_name])
	
	var success: bool = _compile_acompute_on_device(shader, rd)
	if not success:
		device_compute_kernel_compilations[id][shader] = [] as Array[RID]

## Get all kernel RIDs (Array[RID]) for a specific device.
## If shader was not compiled for this device, we compile on demand.
func get_compute_kernel_compilations_for_device(shader: AComputeShader, rd: RenderingDevice) -> Array[RID]:
	var id: int = _device_id(rd)
	assert(id in device_refs)
	
	if shader not in device_compute_kernel_compilations[id]:
		# Compile on demand
		compile_shader_on_device(shader, rd)
	
	@warning_ignore("unsafe_cast")
	return device_compute_kernel_compilations[id][shader] as Array[RID]

## Return the device shader id. For convenience, we use the first compiled kernel RID.
func get_device_shader_id(shader: AComputeShader, rd: RenderingDevice) -> RID:
	##TODO: There is currently a bug with autoloads, opening the setting window will
	##      delete and reload the autoload. This break all our computations.
	##      This my get fixed with https://github.com/godotengine/godot/pull/123532
	##      When it get fixed, just remove the lines under this comment (in the if)
	##      Note: This bug does not occurs when using a scene instead of a script
	##            as an autoload. I leave this comment here for the moment
	if Engine.is_editor_hint():
		var debug_id: int = _device_id(rd)
		_ensure_device_maps(rd)
		if shader not in device_compute_kernel_compilations[debug_id]:
			compile_shader_on_device(shader, rd)
	
	var id: int = _device_id(rd)
	assert(id in device_refs)
	
	# In case compilation failed, return an invalid RID
	var kernels: Array[RID] = device_compute_kernel_compilations[id].get(shader, [])
	if kernels.is_empty():
		return RID()
	
	return device_compute_kernel_compilations[id][shader][0]
#endregion

#region Life Cycle
func _init() -> void:
	# Register the Global Rendering Device
	var global_rd: RenderingDevice = RenderingServer.get_rendering_device()
	register_device(global_rd)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Free all per-device resources
		for id: int in device_refs:
			var rd: RenderingDevice = device_refs[id].get_ref()
			if rd:
				_free_device_compilations(rd)
#endregion

#region Hot Reload
var hot_reload_registered_shaders: Dictionary[AComputeShader, Callable]
func _hot_reload_register_shader(shader: AComputeShader) -> void:
	if shader in hot_reload_registered_shaders: return
	
	var on_change_callable: Callable = _on_shader_changed.bind(shader)
	hot_reload_registered_shaders[shader] = on_change_callable
	
	shader.changed.connect(on_change_callable)

func _hot_reload_register_all() -> void:
	for device_id: int in device_compute_kernel_compilations:
		for shader: AComputeShader in device_compute_kernel_compilations[device_id]:
			# It's safe to do since _hot_reload_register_shader handle the duplicity safety
			_hot_reload_register_shader(shader)

func _hot_reload_unregister_all() -> void:
	for shader: AComputeShader in hot_reload_registered_shaders:
		shader.changed.disconnect(hot_reload_registered_shaders[shader])
	hot_reload_registered_shaders.clear()

func _on_shader_changed(shader: AComputeShader) -> void:
	for device_id: int in device_compute_kernel_compilations:
		var kernel_compilations: Dictionary[AComputeShader, Array] = device_compute_kernel_compilations[device_id]
		
		if shader in kernel_compilations:
			var wr: WeakRef = device_refs[device_id]
			var rd: RenderingDevice = wr.get_ref() if wr else null
			assert(rd != null, "Rendering device freed witout calling \"unregister_device\".")
			
			print("[AC] Hot Realoading (device %d): %s" % [device_id, shader.shader_name])
			
			compile_shader_on_device(shader, rd)
#endregion
