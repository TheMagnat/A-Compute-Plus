@tool
extends EditorPlugin

const SHADER_COMPILER_AUTOLOAD_NAME = "AcerolaShaderCompiler"

var acerola_file_import_plugin: EditorImportPlugin

func _enable_plugin() -> void:
	add_autoload_singleton(SHADER_COMPILER_AUTOLOAD_NAME, "acerola_shader_compiler.gd")

func _disable_plugin() -> void:
	remove_autoload_singleton(SHADER_COMPILER_AUTOLOAD_NAME)

func _enter_tree() -> void:
	acerola_file_import_plugin = preload("acompute_file_import_plugin.gd").new()
	add_import_plugin(acerola_file_import_plugin)

func _exit_tree() -> void:
	remove_import_plugin(acerola_file_import_plugin)
	acerola_file_import_plugin = null

#region File Editing
func _handles(object: Object) -> bool:
	return object is AComputeShader

func _edit(object: Object) -> void:
	if not object: return
	
	var shader: AComputeShader = object as AComputeShader
	
	var path: String = shader.resource_path
	if path: 
		OS.shell_open(ProjectSettings.globalize_path(path))
#endregion
