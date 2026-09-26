@tool
extends EditorPlugin

const SHADER_COMPILER_AUTOLOAD_NAME = "AcerolaShaderCompiler"

func _enable_plugin() -> void:
	add_autoload_singleton(SHADER_COMPILER_AUTOLOAD_NAME, "res://addons/AComputePlus/acerola_shader_compiler.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton(SHADER_COMPILER_AUTOLOAD_NAME)
