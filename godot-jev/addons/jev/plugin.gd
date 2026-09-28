@tool
extends EditorPlugin
## Registers the `Jev` autoload when the plugin is enabled.

const AUTOLOAD := "Jev"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD, "res://addons/jev/jev.gd")


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD)
