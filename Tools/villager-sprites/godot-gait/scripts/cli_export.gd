extends SceneTree
## Headless one-shot: load gait lab, export walk_angles.json, quit.
## Usage:
##   Godot --path . --headless -s res://scripts/cli_export.gd


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://scenes/gait_lab.tscn")
	if packed == null:
		push_error("cli_export: failed to load gait_lab.tscn")
		quit(1)
		return
	var lab: Node = packed.instantiate()
	root.add_child(lab)
	await process_frame
	if lab.has_method("_export_angles"):
		lab.call("_export_angles")
		print("cli_export: ", lab.get("_status"))
		quit(0)
	else:
		push_error("cli_export: gait lab missing _export_angles")
		quit(1)
