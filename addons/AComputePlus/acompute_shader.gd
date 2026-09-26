@tool
@icon("ACShader.svg")
class_name AComputeShader extends Resource

@export var shader_name: String

@export_multiline("monospace") var code: String

@export var kernel_names: Array[String]

@export var kernel_to_thread_group: Dictionary[String, PackedStringArray] # kernel_name -> ["x", "y", "z"]
