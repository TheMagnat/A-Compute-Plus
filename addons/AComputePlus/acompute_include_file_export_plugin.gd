## This EditorExportPlugin is used to exclude include files from the export build
@tool
extends EditorExportPlugin


func _get_name() -> String:
	return "AComputeShaderIncludeExcluder"

func _export_file(_path: String, type: String, _features: PackedStringArray) -> void:
	if type == "AComputeShaderInclude":
		skip()
