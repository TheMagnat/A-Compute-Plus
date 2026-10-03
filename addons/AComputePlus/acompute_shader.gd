@tool
@icon("ACShader.svg")
class_name AComputeShader extends Resource

@export var shader_name: String

@export var kernel_names: Array[String]
@export var kernel_thread_groups: Array[PackedInt32Array] # kernel_index -> [x, y, z]
@export var kernel_spirv: Array[RDShaderSPIRV]

## Filled at runtime and reused between different RenderingDevices
var kernel_byte_code: Array[PackedByteArray]
