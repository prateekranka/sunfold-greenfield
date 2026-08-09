extends RefCounted
## Cyninja-style two-bone gait IK — GDScript port of Tools/villager-sprites/gait_ik.py.
## Angle convention: 0 = screen-down, positive swings tip toward screen-right.
## Loaded via preload("res://scripts/gait_ik.gd") from the gait lab.

const CONTACT_DEFAULT := 0.60


static func clampv(v: float, lo: float, hi: float) -> float:
	return clampf(v, lo, hi)


static func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampv((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func angle_of(vx: float, vy: float) -> float:
	return rad_to_deg(atan2(vx, vy))


static func unit(api_deg: float) -> Vector2:
	var r := deg_to_rad(api_deg)
	return Vector2(sin(r), cos(r))


static func solve_chain(
	hip: Vector2, l1: float, l2: float, target: Vector2, bend: float = 1.0
) -> Vector2:
	## Returns (upper_world_deg, lower_world_deg).
	var dx := target.x - hip.x
	var dy := target.y - hip.y
	var dist := clampv(Vector2(dx, dy).length(), absf(l1 - l2) + 0.5, l1 + l2 - 0.5)
	var base := angle_of(dx, dy)
	var cos_a := clampv((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a1 := rad_to_deg(acos(cos_a))
	var upper_world := base + bend * a1
	var u := unit(upper_world)
	var knee := hip + u * l1
	var b := unit(base)
	var reach := hip + b * dist
	var lower_world := angle_of(reach.x - knee.x, reach.y - knee.y)
	return Vector2(upper_world, lower_world)


static func foot_path(
	phase_u: float,
	stride: float,
	lift: float,
	ground_y: float,
	hip_x: float,
	contact: float = CONTACT_DEFAULT
) -> Vector3:
	## Returns (target_x, target_y, foot_world_deg).
	var gu := fposmod(phase_u, 1.0)
	contact = clampv(contact, 0.05, 0.95)
	var x: float
	var y: float
	var toe: float
	if gu < contact:
		var s := gu / contact
		x = lerpf(stride * 0.5, -stride * 0.5, s)
		y = ground_y - lift * 0.35 * smoothstep(0.70, 1.0, s)
		toe = lerpf(0.0, -10.0, smoothstep(0.55, 1.0, s))
	else:
		var v := (gu - contact) / (1.0 - contact)
		x = lerpf(-stride * 0.5, stride * 0.5, smoothstep(0.0, 1.0, v))
		y = ground_y - lift * maxf(sin(PI * v), 0.35 * (1.0 - v))
		toe = -12.0 * (1.0 - v) * (1.0 - v)
	return Vector3(hip_x + x, y, toe)


static func solve_leg(
	hip: Vector2,
	knee_rest: Vector2,
	ankle_rest: Vector2,
	thigh_rest_angle: float,
	shin_rest_angle: float,
	foot_rest_angle: float,
	target: Vector2,
	foot_world: float,
	bend: float,
	root: Vector2 = Vector2.ZERO,
	pelvis_world: float = 0.0
) -> Dictionary:
	var v1 := knee_rest - hip
	var v2 := ankle_rest - knee_rest
	var l1 := v1.length()
	var l2 := v2.length()
	var rest_thigh := angle_of(v1.x, v1.y)
	var rest_shin := angle_of(v2.x, v2.y)
	var hip_w := hip + root
	var worlds := solve_chain(hip_w, l1, l2, target, bend)
	var upper_world: float = worlds.x
	var lower_world: float = worlds.y
	var thigh := upper_world - pelvis_world - rest_thigh - thigh_rest_angle
	var shin := (
		lower_world
		- upper_world
		- (rest_shin - rest_thigh)
		- shin_rest_angle
	)
	var foot := minf(0.0, foot_world) - lower_world - foot_rest_angle
	foot = clampv(foot, -22.0, 22.0)
	var u := unit(upper_world)
	var knee_w := hip_w + u * l1
	var shin_u := unit(lower_world)
	var ankle_w := knee_w + shin_u * l2
	return {
		"thigh": thigh,
		"shin": shin,
		"foot": foot,
		"hip": hip_w,
		"knee": knee_w,
		"ankle": ankle_w,
		"upper_world": upper_world,
		"lower_world": lower_world,
	}
