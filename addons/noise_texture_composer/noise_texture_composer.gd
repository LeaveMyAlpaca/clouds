@tool
extends EditorPlugin
class TextureRebuilderInspectorPlugin:
	extends EditorInspectorPlugin

	func _can_handle(object):
		return object is ComposedTexture2D or object is ComposedTexture3D

	func _parse_group(object: Object, group: String) -> void:
			var button = Button.new()
			button.text = "Rebuild Texture"
			add_property_editor("Regenerate", button)
			button.pressed.connect(object.rebuild_composed_texture)

var texture_rebuilder_plugin: TextureRebuilderInspectorPlugin
func _enter_tree():
	texture_rebuilder_plugin = TextureRebuilderInspectorPlugin.new()
	add_inspector_plugin(texture_rebuilder_plugin)


func _exit_tree():
	remove_inspector_plugin(texture_rebuilder_plugin)
