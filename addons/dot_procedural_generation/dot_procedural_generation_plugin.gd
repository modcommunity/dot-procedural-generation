@tool
extends EditorPlugin

## Editor entry point for dot-procedural-generation. Registers inspector types only.
##
## No autoloads: a server generating the next map while the current one is still being
## played is two runners in one process, and a global would make them one.

const _ICON := "res://addons/dot_procedural_generation/icon_placeholder.svg"

const _TYPES := [
	[
		"DotProcGenRunner",
		"Node",
		"res://addons/dot_procedural_generation/runtime/dot_procgen_runner.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
