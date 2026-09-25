@tool
class_name BoidComputer extends Node

var rd: RenderingDevice
var boidsCompute: ACompute

var isComputing: bool = false

## Rendering
var color_rect: ColorRect

var multimesh: MultiMesh
var multiMeshInstance: MultiMeshInstance2D
var multimeshBufferRid: RID

@export var material: Material
@export var mesh: Mesh

@export var size: int = 100
@export var area := Vector2(500.0, 500.0)

@export var min_speed: float = 1.0
@export var max_speed: float = 3.0

@export var perception_radius: float = 10.0
@export var separation_radius: float = 4.0
@export var max_steer_force: float = 1.0
@export var bounds_margin: float = 0.1

@export var separation_weight: float = 1.0
@export var alignment_weight: float = 1.0
@export var cohesion_weight: float = 1.0
@export var bounds_weight: float = 1.0

enum Bindings {
	MULTIMESH = 0,
	BOIDS = 1,
}

const BOID_DATA_STRUCT_VECTOR2_SIZE: int = 2

func _ready() -> void:
	registerComputeShader()
	
	initialize()
	
	# To visualize the area
	color_rect = ColorRect.new()
	color_rect.size = area
	color_rect.position -= area / 2.0
	color_rect.color = Color.BLACK
	color_rect.z_index = -1
	add_child(color_rect)

func initialize() -> void:
	var initial_pos = PackedVector2Array()
	initial_pos.resize(size)
	for i: int in size:
		var random_pos := Vector2(randf_range(-area.x / 2.0, area.x / 2.0), randf_range(-area.y / 2.0, area.y / 2.0))
		initial_pos[i] = random_pos
	
	setupMultiMesh(initial_pos)
	setupInitialUniforms(initial_pos)

func setupMultiMesh(initial_pos: PackedVector2Array) -> void:
	multimesh = MultiMesh.new()
	
	mesh.material = material
	
	multimesh.mesh = mesh
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.physics_interpolation_quality = MultiMesh.INTERP_QUALITY_FAST
	multimesh.instance_count = size
	# Note: You may want to set the multimesh.custom_aabb for your 3D projects

	multiMeshInstance = MultiMeshInstance2D.new()
	multiMeshInstance.multimesh = multimesh
	multiMeshInstance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	multiMeshInstance.material = material
	
	for i: int in size:
		var xform := Transform2D(0.0, Vector2.ONE, 0.0, initial_pos[i])
		
		multimesh.set_instance_transform_2d(i, xform)
		# Note: You could add Color or Custom data to the Multimesh and edit it in the compute shader to then receive it in a rendering shader.
		#multimesh.set_instance_color(i, Color(i, 0.0, 0.0, 0.0))
	
	add_child(multiMeshInstance)
	
	multimeshBufferRid = RenderingServer.multimesh_get_buffer_rd_rid(multimesh.get_rid())

func setupInitialUniforms(initial_pos: PackedVector2Array) -> void:
	boidsCompute.set_storage_buffer(Bindings.MULTIMESH, multimesh.buffer.to_byte_array())
	
	var boidsData := PackedVector2Array()
	boidsData.resize(size * BOID_DATA_STRUCT_VECTOR2_SIZE)
	for i: int in size:
		boidsData[0 + i * BOID_DATA_STRUCT_VECTOR2_SIZE] = initial_pos[i]
		boidsData[1 + i * BOID_DATA_STRUCT_VECTOR2_SIZE] = Vector2.ZERO
	
	boidsCompute.set_storage_buffer(Bindings.BOIDS, boidsData.to_byte_array())

func updateUniforms(delta: float) -> void:
	# Here you can update the buffers that require it
	
	boidsCompute.set_push_constant(get_push_constant(delta))

func get_push_constant(delta: float) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(16 * 4)
	
	bytes.encode_u32(0 * 4, size)
	bytes.encode_float(1 * 4, delta)
	bytes.encode_float(2 * 4, min_speed)
	bytes.encode_float(3 * 4, max_speed)
	
	bytes.encode_float(4 * 4, perception_radius)
	bytes.encode_float(5 * 4, separation_radius)
	bytes.encode_float(6 * 4, max_steer_force)
	bytes.encode_float(7 * 4, bounds_margin)

	bytes.encode_float(8 * 4, separation_weight)
	bytes.encode_float(9 * 4, alignment_weight)
	bytes.encode_float(10 * 4, cohesion_weight)
	bytes.encode_float(11 * 4, bounds_weight)

	bytes.encode_float(12 * 4, area.x / 2.0)
	bytes.encode_float(13 * 4, area.y / 2.0)
	
	## Padding
	#bytes.encode_float(14 * 4, 0.0)
	#bytes.encode_float(15 * 4, 0.0)
	
	return bytes

func compute(delta: float) -> void:
	updateUniforms(delta)
	#TODO: Find a way to automaticaly get the number of threads in shaders kernels
	var groups: int = ceil(float(size) / 1024.0)
	boidsCompute.dispatch(0, groups, 1, 1, true)
	isComputing = true

func sync() -> void:
	if not isComputing: return
	
	rd.sync()
	isComputing = false
	
	# Now that sync was called, we can use the computed data.
	
	var newMultimeshBuffer: PackedFloat32Array = boidsCompute.get_storage_data(Bindings.MULTIMESH).to_float32_array()
	multimesh.buffer = newMultimeshBuffer

func _physics_process(delta: float) -> void:
	if isComputing:
		sync()
	
	compute(delta)

func registerComputeShader() -> void:
	rd = RenderingServer.create_local_rendering_device()
	boidsCompute = ACompute.new('compute_boids', rd, true)
