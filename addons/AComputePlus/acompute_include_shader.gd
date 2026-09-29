## Resource used to import ACompute include files and the AComputeShader
## that depend on it. It's not meant to be referenced in any other place than
## the the AComputePlus plugin, since it's explicitly skipped in the
## "acompute_include_file_export_plugin.gd" EditorExportPlugin, they wont be
## exported in any build. (Their data is already compiled in the compiled shaders)
@tool
@icon("ACShaderInclude.svg")
class_name AComputeShaderInclude extends Resource

@export var linked_shaders_path := PackedStringArray()
