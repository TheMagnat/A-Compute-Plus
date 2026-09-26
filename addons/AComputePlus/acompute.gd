@tool
class_name ACompute extends RefCounted

var kernels: Array[RID]
var rd : RenderingDevice
var owns_local_device: bool = false  # If we own the local RD and should free it
var use_local_device: bool = false # if we're using a local RD

var shader_name : String
var shader_id : RID
var push_constant : PackedByteArray
var uniform_set_gpu_id : RID
var uniform_set_cache : Array[RDUniform]
var current_bound_uniform_set_cpu_copy : Array

# State management
var refresh_uniforms: bool = true
var submited: bool = false

## Binding -> RID
var texture_cache: Dictionary[int, RID] = {}

## Contains the contents of the uniform array itself
## Binding -> Array
var uniform_buffer_cache: Dictionary[int, PackedByteArray] = {}
## Contains the RIDs for the gpu versions of the uniform array
## Binding -> RID
var uniform_buffer_id_cache: Dictionary[int, RID] = {}

## Contains the size of the storage buffer
## Binding -> int (byte size, for size-match checks on update)
var storage_buffer_cache_size: Dictionary[int, int] = {}
## Contains the RIDs for the gpu versions of the storage buffer
## Binding -> RID
var storage_buffer_id_cache: Dictionary[int, RID] = {}

#region Data Write API
func set_push_constant(_push_constant: PackedByteArray) -> void:
	push_constant = PackedByteArray(_push_constant)

func set_texture(binding: int, texture: RID) -> void:
	if texture_cache.has(binding):
		if texture_cache[binding] == texture:
			return
	
	var u : RDUniform = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(texture)
	
	# Cache texture RID
	texture_cache[binding] = texture
	
	_cache_uniform(u)

func set_uniform_buffer(binding: int, uniform_array: PackedByteArray) -> void:
	# Check if buffer exists already in this binding
	if uniform_buffer_cache.has(binding):
		
		# if buffer is identical, no need to change
		if uniform_array == uniform_buffer_cache.get(binding):
			return
		
		# if new values but same buffer size, update gpu buffer
		if uniform_array.size() == uniform_buffer_cache[binding].size():
			rd.buffer_update(uniform_buffer_id_cache.get(binding), 0, uniform_array.size(), uniform_array)
			uniform_buffer_cache[binding] = PackedByteArray(uniform_array)
			return
		
		# Otherwise, free the memory because footprint no longer matches
		rd.free_rid(uniform_buffer_id_cache.get(binding))
	
	# Instantiate uniform buffer in gpu memory and declare uniform descriptor
	var uniform_buffer_id = rd.uniform_buffer_create(uniform_array.size(), uniform_array)
	
	var u : RDUniform = RDUniform.new()
	
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u.binding = binding
	u.add_id(uniform_buffer_id)
	
	# Cache array contents and RID
	uniform_buffer_cache[binding] = PackedByteArray(uniform_array)
	uniform_buffer_id_cache[binding] = uniform_buffer_id
	
	_cache_uniform(u)

func set_storage_buffer(binding: int, storage_array: PackedByteArray) -> void:
	var byte_size: int = storage_array.size()
	# Check if buffer exists already in this binding
	if storage_buffer_cache_size.has(binding):
	
		# if new values but same buffer size, update gpu buffer
		if byte_size == storage_buffer_cache_size[binding]:
			rd.buffer_update(storage_buffer_id_cache.get(binding), 0, byte_size, storage_array)
			storage_buffer_cache_size[binding] = byte_size
			return
		
		# Otherwise, free the memory because footprint no longer matches
		rd.free_rid(storage_buffer_id_cache.get(binding))
	
	# Instantiate storage buffer in gpu memory and declare uniform descriptor
	var storage_buffer_id := rd.storage_buffer_create(storage_array.size(), storage_array)
	
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(storage_buffer_id)
	
	# Cache array size and RID
	storage_buffer_cache_size[binding] = byte_size
	storage_buffer_id_cache[binding] = storage_buffer_id
	
	_cache_uniform(u)

## Store an empty buffer
func set_empty_storage_buffer(binding: int, byte_size: int) -> void:
	var storage_array := PackedByteArray()
	storage_array.resize(byte_size)
	
	set_storage_buffer(binding, storage_array)

## Store an existing buffer.
## Buffer must have been created on the same RD.
## Note: This is useful to share data without involving CPU reading and writing
##       between multiple shaders.
##       It can also works on Multimesh buffers if you're using the Global Rendering Device.
func set_storage_buffer_rid(binding: int, rid: RID) -> void:
	if storage_buffer_cache_size.has(binding) and rid == storage_buffer_id_cache[binding]:
		return
	
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)

	# Cache array contents and RID
	storage_buffer_cache_size[binding] = -1
	storage_buffer_id_cache[binding] = rid
	
	_cache_uniform(u)
#endregion

#region Data Read API

func get_storage_data(binding: int) -> PackedByteArray:
	assert(binding in storage_buffer_id_cache)
	
	return rd.buffer_get_data(storage_buffer_id_cache[binding])

#endregion

#region Utility
func _cache_uniform(u: RDUniform) -> void:
	##TODO: Check if we can come up with a better solution to prevent having null if skiping bindings
	if uniform_set_cache.size() - 1 < u.binding:
		refresh_uniforms = true
		uniform_set_cache.resize(u.binding + 1)
	
	# If uniform has had its info changed then set flag to refresh gpu side uniform data
	if uniform_set_cache[u.binding]:
		var old_uniform_ids: Array[RID] = uniform_set_cache[u.binding].get_ids()
		var new_uniform_ids: Array[RID] = u.get_ids()
		
		if old_uniform_ids.size() != new_uniform_ids.size():
			refresh_uniforms = true
		else:
			for i: int in old_uniform_ids.size():
				if old_uniform_ids[i].get_id() != new_uniform_ids[i].get_id():
					refresh_uniforms = true
					break
	
	uniform_set_cache[u.binding] = u
#endregion

#region Public API
## A device can be injected to be used.
## If no device is injected, ACompute will use the Global Rendering Device.
## You can leave the responsibility of the RD to the ACompute object,
## which will handle registering and releasing the RD upon free.
func _init(_shader_name: String, _rd: RenderingDevice = null, _owns_local_device: bool = false) -> void:
	assert(_rd != RenderingServer.get_rendering_device(), "To use the Global Rendering device, provide a null RD.")
	assert(_rd != null or not _owns_local_device, "When using Global Rendering device, owns_local_device must be false.")
	
	# Choose between injected or global device
	if _rd:
		rd = _rd
		owns_local_device = _owns_local_device
		use_local_device = true
	else:
		rd = RenderingServer.get_rendering_device()
		owns_local_device = false
		use_local_device = false
	
	shader_name = _shader_name
	
	# Register the device
	if owns_local_device: AcerolaShaderCompiler.register_device(rd)
	
	# "get_compute_kernel_compilations_for_device" will compile the shader for us if it's not already compiled
	for kernel in AcerolaShaderCompiler.get_compute_kernel_compilations_for_device(shader_name, rd):
		kernels.push_back(rd.compute_pipeline_create(kernel))
	
	shader_id = AcerolaShaderCompiler.get_device_shader_id(shader_name, rd)

## Prepare the RD to run the desired kernel on the selected number of groups.
## If using a local RD, your last dispatch call must have submit to true or your
## command will never run.
## Once you submited, you must call sync to retrieves your data.
## Note: You can't set submit to true on the Global Rendering Device, Godot handle it itself.
func dispatch(kernel_index: int, x_groups: int, y_groups: int, z_groups: int, submit: bool = false) -> void:
	assert(use_local_device or not submit, "Can't Submit on Global Rendering Device.")
	
	var global_shader_id: RID = AcerolaShaderCompiler.get_device_shader_id(shader_name, rd)
	
	# Recreate kernel pipelines if shader was recompiled
	if shader_id != global_shader_id:
		shader_id = global_shader_id
		
		# AcerolaShaderCompiler frees the compilations which then frees all attached resources
		# including the old uniform set so it needs to be recreated
		uniform_set_gpu_id = rd.uniform_set_create(uniform_set_cache, global_shader_id, 0)
		
		kernels.clear()
		for kernel in AcerolaShaderCompiler.get_compute_kernel_compilations_for_device(shader_name, rd):
			kernels.push_back(rd.compute_pipeline_create(kernel))
	
	# If compilation failed, do not dispatch anything and return
	if kernels.is_empty(): return
	
	# Reallocate GPU memory if uniforms need updating
	if refresh_uniforms:
		if rd.uniform_set_is_valid(uniform_set_gpu_id):
			rd.free_rid(uniform_set_gpu_id)
		uniform_set_gpu_id = rd.uniform_set_create(uniform_set_cache, global_shader_id, 0)
		refresh_uniforms = false
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, kernels[kernel_index])
	rd.compute_list_bind_uniform_set(compute_list, uniform_set_gpu_id, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	rd.compute_list_end()
	
	if submit:
		rd.submit()
		submited = true

## Must be called after a dispatch with submit to retrieve the data
## Note: You can't call sync on the Global Rendering Device, Godot handle it itself.
func sync() -> void:
	assert(use_local_device, "Can't sync on Global Rendering Device.")
	if submited:
		rd.sync()
		submited = false
	elif not kernels.is_empty():
		# Here we try to sync while not having subtimed anything and the shader is compiled
		push_error("\"sync\" can only be called after a submit.")
#endregion

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		for kernel in kernels:
			rd.free_rid(kernel)
		kernels.clear()
		
		for binding: int in uniform_buffer_id_cache:
			rd.free_rid(uniform_buffer_id_cache[binding])
		uniform_buffer_id_cache.clear()
		
		for binding: int in storage_buffer_id_cache:
			rd.free_rid(storage_buffer_id_cache[binding])
		storage_buffer_id_cache.clear()
		
		if rd.uniform_set_is_valid(uniform_set_gpu_id): rd.free_rid(uniform_set_gpu_id)
		
		if owns_local_device and rd:
			AcerolaShaderCompiler.unregister_device(rd)
			rd.free()
			rd = null
