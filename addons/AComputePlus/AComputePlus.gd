@tool
extends EditorPlugin

const PLUGIN_NAME: String = "AComputePlus"
const SHADER_COMPILER_AUTOLOAD_NAME: String = "AcerolaShaderCompiler"

var acerola_file_import_plugin: EditorImportPlugin
var acerola_include_file_import_plugin: EditorImportPlugin
var acerola_include_file_export_plugin: EditorExportPlugin

var acerola_shader_compiler_ref: Node = null

func _enable_plugin() -> void:
	add_autoload_singleton(SHADER_COMPILER_AUTOLOAD_NAME, "acerola_shader_compiler.tscn")

func _disable_plugin() -> void:
	remove_autoload_singleton(SHADER_COMPILER_AUTOLOAD_NAME)

func _enter_tree() -> void:
	acerola_file_import_plugin = preload("acompute_file_import_plugin.gd").new()
	add_import_plugin(acerola_file_import_plugin)
	
	acerola_include_file_import_plugin = preload("acompute_include_file_import_plugin.gd").new()
	add_import_plugin(acerola_include_file_import_plugin)
	
	acerola_include_file_export_plugin = preload("acompute_include_file_export_plugin.gd").new()
	add_export_plugin(acerola_include_file_export_plugin)
	
	_setup_settings()

func _exit_tree() -> void:
	remove_export_plugin(acerola_include_file_export_plugin)
	acerola_include_file_export_plugin = null
	
	remove_import_plugin(acerola_include_file_import_plugin)
	acerola_include_file_import_plugin = null

	remove_import_plugin(acerola_file_import_plugin)
	acerola_file_import_plugin = null

#region Compiler Autoload Instance
## Insane hack we have to do since you can't reference directly the autoload since it's
## added in this plugin and would make the plugin impossible to parse and with the same bug
## mentioned in "get_device_shader_id", it make the autoload node path change when opening
## settings so it can have a weird name like @Node@28630.
## Check if https://github.com/godotengine/godot/pull/123532 fix it
## Note: This bug does not occurs when using a scene instead of a script
##       as an autoload. I leave this comment here for the moment
#func _get_compiler_instance() -> Node:
	#for child: Node in get_tree().root.get_children(true):
		#if preload("acerola_shader_compiler.gd") == child.get_script():
			#return child
	#
	#return get_tree().root.get_node_or_null(SHADER_COMPILER_AUTOLOAD_NAME)

func _get_compiler_instance() -> Node:
	return get_tree().root.get_node_or_null(SHADER_COMPILER_AUTOLOAD_NAME)

## Call this to save the state of the compiler in its packed scene (.tscn) file
## Useful to share user settings in runtime
func _save_compiler_state() -> void:
	var instance: Node = _get_compiler_instance()
	if not instance: return
	
	var scene_pack := PackedScene.new()
	scene_pack.pack(instance)
	
	ResourceSaver.save(scene_pack, instance.scene_file_path)
#endregion

#region Settings
var hot_reload: bool = false:
	set(value):
		if hot_reload == value: return
		
		var instance: Node = _get_compiler_instance()
		if instance:
			@warning_ignore("unsafe_property_access")
			instance.HOT_RELOADING = value
			_save_compiler_state()
			
		hot_reload = value

var auto_compile_on_global_rd: bool = false:
	set(value):
		if auto_compile_on_global_rd == value: return
			
		var instance: Node = _get_compiler_instance()
		if instance:
			@warning_ignore("unsafe_property_access")
			instance.AUTO_GLOBAL_COMPILE = value
			_save_compiler_state()
		
		auto_compile_on_global_rd = value

## Note: Editing settings order require editing "_on_settings_changed" too
const SETTINGS_NAMES: PackedStringArray = [
	"hot_reload",
	"use_includes",
	"auto_compile_on_global_rd"
]

func _setup_settings() -> void:
	for setting_name: String in SETTINGS_NAMES:
		var setting_full_name: String = "%s/%s" % [PLUGIN_NAME, setting_name]
		
		if not ProjectSettings.has_setting(setting_full_name):
			ProjectSettings.set_setting(setting_full_name, true)
		
		ProjectSettings.set_initial_value(setting_full_name, true)
	
	# Note that settings_changed will emited be called at start
	ProjectSettings.settings_changed.connect(_on_settings_changed)

func _on_settings_changed() -> void:
	hot_reload = ProjectSettings.get_setting("%s/%s" % [PLUGIN_NAME, SETTINGS_NAMES[0]], false)
	auto_compile_on_global_rd = ProjectSettings.get_setting("%s/%s" % [PLUGIN_NAME, SETTINGS_NAMES[2]], false)
#endregion

#region File Editing
func _handles(object: Object) -> bool:
	return object is AComputeShader or object is AComputeShaderInclude

func _edit(object: Object) -> void:
	if not object: return
	
	var resource: Resource = object as Resource
	
	var path: String = resource.resource_path
	if path: 
		OS.shell_open(ProjectSettings.globalize_path(path))
#endregion
