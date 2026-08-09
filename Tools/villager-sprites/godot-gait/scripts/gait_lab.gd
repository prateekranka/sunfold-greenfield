extends Node2D
## Live cyninja gait preview + angle exporter for the Python cutout bake.
##
## Keys:
##   1–5     facing preset (S SE E NE N)
##   [ / ]   previous / next walk frame
##   Space   play / pause
##   E       export walk_angles.json (+ suggested bend signs)
##   B       flip bendA/bendB on the current facing (knock-knee knob)
##   R       reload data/gait_config.json

const GaitIK := preload("res://scripts/gait_ik.gd")
const CONFIG_PATH := "res://data/gait_config.json"
const EXPORT_PATH := "res://export/walk_angles.json"

@export var facing: String = "S"
@export var playing: bool = true
@export var phase_u: float = 0.0

var _cfg: Dictionary = {}
var _figure: Dictionary = {}
var _gait: Dictionary = {}
var _gains: Dictionary = {}
var _frame_i: int = 0
var _status: String = ""


func _ready() -> void:
	_reload()
	queue_redraw()


func _process(delta: float) -> void:
	if playing and _gait:
		var fps: float = float(_gait.get("fps", 10))
		phase_u = fposmod(phase_u + delta * fps / float(_gait.get("frames", 4)), 1.0)
		_frame_i = int(floor(phase_u * float(_gait.get("frames", 4)))) % int(_gait.get("frames", 4))
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_set_facing("S")
			KEY_2:
				_set_facing("SE")
			KEY_3:
				_set_facing("E")
			KEY_4:
				_set_facing("NE")
			KEY_5:
				_set_facing("N")
			KEY_BRACKETLEFT:
				playing = false
				_frame_i = (_frame_i - 1 + int(_gait.get("frames", 4))) % int(_gait.get("frames", 4))
				phase_u = float(_frame_i) / float(_gait.get("frames", 4))
				queue_redraw()
			KEY_BRACKETRIGHT:
				playing = false
				_frame_i = (_frame_i + 1) % int(_gait.get("frames", 4))
				phase_u = float(_frame_i) / float(_gait.get("frames", 4))
				queue_redraw()
			KEY_SPACE:
				playing = not playing
			KEY_E:
				_export_angles()
			KEY_B:
				_flip_bends()
			KEY_R:
				_reload()
				queue_redraw()


func _reload() -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		_status = "Missing %s" % CONFIG_PATH
		return
	var raw := FileAccess.get_file_as_string(CONFIG_PATH)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_status = "Bad JSON in gait_config.json"
		return
	_cfg = parsed
	_figure = _cfg.get("figure", {}).get("S", {})
	_gait = _cfg.get("gait", {})
	_gains = _cfg.get("viewGain", {})
	_status = "Loaded gait_config.json — facing %s" % facing


func _set_facing(f: String) -> void:
	facing = f
	_status = "Facing %s  bendA=%s bendB=%s" % [
		facing,
		_gain().get("bendA", 1.0),
		_gain().get("bendB", 1.0),
	]
	queue_redraw()


func _gain() -> Dictionary:
	return _gains.get(facing, {"stride": 1.0, "lift": 1.0, "bob": 1.0, "bendA": 1.0, "bendB": 1.0})


func _flip_bends() -> void:
	if not _gains.has(facing):
		return
	var g: Dictionary = _gains[facing]
	var a: float = float(g.get("bendA", 1.0))
	var b: float = float(g.get("bendB", 1.0))
	g["bendA"] = -a
	g["bendB"] = -b
	_gains[facing] = g
	_status = "Flipped bends on %s → A=%s B=%s (press E to export)" % [facing, g["bendA"], g["bendB"]]
	queue_redraw()


func _sample_frame(frame_i: int) -> Dictionary:
	var g := _gain()
	var frames: int = int(_gait.get("frames", 4))
	var u := float(frame_i) / float(frames)
	var stride := float(_gait.get("stride", 96)) * float(g.get("stride", 1.0))
	var lift := float(_gait.get("lift", 28)) * float(g.get("lift", 1.0))
	var contact := float(_gait.get("contact", 0.62))
	var plant_drop := float(_gait.get("plantDrop", 10))
	var bob_keys: Array = _cfg.get("armKeys", [])
	var bob := 0.01
	if frame_i < bob_keys.size():
		bob = float(bob_keys[frame_i].get("bob", 0.01)) * float(g.get("bob", 1.0))
	var root := Vector2(0.0, bob * float(_figure.get("height", 1240)))
	var out := {
		"frame": frame_i,
		"phase_u": u,
		"root": [0.0, bob],
		"legs": {},
	}
	for side in ["A", "B"]:
		var leg: Dictionary = _figure.get("leg%s" % side, {})
		var hip := Vector2(leg["hip"][0], leg["hip"][1])
		var knee := Vector2(leg["knee"][0], leg["knee"][1])
		var ankle := Vector2(leg["ankle"][0], leg["ankle"][1])
		var bend := float(g.get("bend%s" % side, 1.0))
		var phase := float(_gait.get("phase%s" % side, 0.0 if side == "B" else 0.5))
		var gu := fposmod(u + phase, 1.0)
		var path := GaitIK.foot_path(gu, stride, lift, ankle.y - plant_drop, ankle.x, contact)
		var target := Vector2(path.x + root.x, path.y)
		var solved := GaitIK.solve_leg(
			hip, knee, ankle,
			float(leg.get("thigh_rest_angle", 0.0)),
			float(leg.get("shin_rest_angle", 0.0)),
			float(leg.get("foot_rest_angle", 0.0)),
			target, path.z, bend, root
		)
		out["legs"][side] = {
			"thigh": solved["thigh"],
			"shin": solved["shin"],
			"foot": solved["foot"],
			"target": [target.x, target.y],
			"knee": [solved["knee"].x, solved["knee"].y],
			"ankle": [solved["ankle"].x, solved["ankle"].y],
			"bend": bend,
		}
	return out


func _export_angles() -> void:
	var facings := ["S", "SE", "E", "NE", "N"]
	var frames: int = int(_gait.get("frames", 4))
	var payload := {
		"schema": "sunfold.godot-walk-angles/1",
		"source": "godot-gait lab",
		"facingOrder": facings,
		"clips": {
			"walk": {
				"frames": frames,
				"fps": int(_gait.get("fps", 10)),
				"gait": {
					"stride": _gait.get("stride", 96),
					"lift": _gait.get("lift", 28),
					"contact": _gait.get("contact", 0.62),
					"phaseA": _gait.get("phaseA", 0.5),
					"phaseB": _gait.get("phaseB", 0.0),
					"plantDrop": _gait.get("plantDrop", 10),
				},
				"viewGain": {},
				"perFacing": {},
			}
		},
		"note": "Merge viewGain bendA/bendB into Tools/villager-sprites/clips.json, then re-run bake_sprites.py. Pixel compositing stays in the Python cutout pipeline.",
	}
	var walk: Dictionary = payload["clips"]["walk"]
	for f in facings:
		var prev := facing
		facing = f
		var g := _gain()
		walk["viewGain"][f] = {
			"stride": g.get("stride", 1.0),
			"lift": g.get("lift", 1.0),
			"bendA": g.get("bendA", 1.0),
			"bendB": g.get("bendB", 1.0),
		}
		var samples: Array = []
		for i in range(frames):
			var sample := _sample_frame(i)
			samples.append({
				"frame": i,
				"root": sample["root"],
				"angles": {
					"legA_thigh": sample["legs"]["A"]["thigh"],
					"legA_shin": sample["legs"]["A"]["shin"],
					"legA_foot": sample["legs"]["A"]["foot"],
					"legB_thigh": sample["legs"]["B"]["thigh"],
					"legB_shin": sample["legs"]["B"]["shin"],
					"legB_foot": sample["legs"]["B"]["foot"],
				},
			})
		walk["perFacing"][f] = samples
		facing = prev
	var abs_path := ProjectSettings.globalize_path(EXPORT_PATH)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if f == null:
		_status = "Export failed: %s" % FileAccess.get_open_error()
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	# Persist bend tweaks back into the config the lab reloads.
	_cfg["viewGain"] = _gains
	var cfg_file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if cfg_file:
		cfg_file.store_string(JSON.stringify(_cfg, "\t"))
		cfg_file.close()
	_status = "Exported %s — apply with: python3 apply_godot_gait.py" % abs_path


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1100, 900)), Color(0.12, 0.11, 0.10))
	draw_string(ThemeDB.fallback_font, Vector2(24, 36), "Sunwoven gait lab — cyninja IK (Godot 4.7)", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.95, 0.9, 0.8))
	draw_string(ThemeDB.fallback_font, Vector2(24, 62), "1–5 facing  [ ] frame  Space play  B flip bends  E export  R reload", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 0.68, 0.62))
	draw_string(ThemeDB.fallback_font, Vector2(24, 84), _status, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.75, 0.45))

	if _figure.is_empty():
		return

	var sample := _sample_frame(_frame_i)
	var origin := Vector2(280, 40)
	var scale := 0.55
	# Ground line
	var ground_y := float(_figure["legA"]["ankle"][1]) * scale + origin.y
	draw_line(Vector2(40, ground_y), Vector2(1060, ground_y), Color(0.35, 0.32, 0.28), 1.0)

	var pelvis := Vector2(_figure["pelvis"][0], _figure["pelvis"][1]) * scale + origin
	draw_circle(pelvis, 6.0, Color(0.9, 0.85, 0.7))
	for side in ["A", "B"]:
		var leg: Dictionary = sample["legs"][side]
		var hip_draw := Vector2(
			_figure["leg%s" % side]["hip"][0] + sample["root"][0] * float(_figure["width"]),
			_figure["leg%s" % side]["hip"][1] + sample["root"][1] * float(_figure["height"])
		) * scale + origin
		var knee := Vector2(leg["knee"][0], leg["knee"][1]) * scale + origin
		var ankle := Vector2(leg["ankle"][0], leg["ankle"][1]) * scale + origin
		var col := Color(0.55, 0.85, 1.0) if side == "A" else Color(1.0, 0.7, 0.45)
		draw_line(pelvis, hip_draw, Color(0.55, 0.5, 0.45), 2.0)
		draw_line(hip_draw, knee, col, 5.0)
		draw_line(knee, ankle, col, 4.0)
		draw_circle(knee, 5.0, col)
		draw_circle(ankle, 4.0, Color(0.95, 0.95, 0.9))
		var tgt := Vector2(leg["target"][0], leg["target"][1]) * scale + origin
		draw_circle(tgt, 3.0, Color(1.0, 0.3, 0.3, 0.7))

	var g := _gain()
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24, 860),
		"facing=%s  frame=%d/%d  phase=%.2f  stride×%.2f  lift×%.2f  bendA=%.0f bendB=%.0f" % [
			facing, _frame_i, int(_gait.get("frames", 4)) - 1, phase_u,
			float(g.get("stride", 1.0)), float(g.get("lift", 1.0)),
			float(g.get("bendA", 1.0)), float(g.get("bendB", 1.0)),
		],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.82, 0.75)
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(24, 882),
		"Outward knees: S/SE A=+1 B=-1; N/NE A=-1 B=+1. Profile (E) both +1. Press B to flip; E exports for Python bake.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.58, 0.52)
	)
