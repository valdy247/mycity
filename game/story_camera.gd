extends Node3D
const Person = preload("res://street_person.gd")
# One reusable camera, same viewport, no postprocessing or extra render pass.
var shot_camera: Camera3D
var previous_camera: Camera3D
var subject: Node3D
var player_body: CharacterBody3D
var active := false
var shot_origin := Vector3.ZERO
var shot_end := Vector3.ZERO
var elapsed := 0.0

func _ready() -> void:
	shot_camera = Camera3D.new()
	shot_camera.name = "StoryCamera"
	add_child(shot_camera)
	shot_camera.fov = 58.0
	shot_camera.near = .08
	set_physics_process(false)

static func shot_candidates(focus: Vector3,viewer: Vector3) -> PackedVector3Array:
	var forward := viewer-focus
	forward.y = 0.0
	if forward.length_squared()<.04: forward = Vector3.FORWARD
	forward = forward.normalized()
	var side := Vector3(-forward.z,0,forward.x)
	return PackedVector3Array([
		focus+forward*1.9+side*.85+Vector3.UP*.18,
		focus+forward*1.9-side*.85+Vector3.UP*.18,
		focus+forward*1.35+Vector3.UP*.10,
		focus+forward*.95+side*.35+Vector3.UP*.12,
		focus+forward*.95-side*.35+Vector3.UP*.12
	])

func _clear(a: Vector3,b: Vector3) -> bool:
	if a.distance_squared_to(b)<.0001: return true
	var query := PhysicsRayQueryParameters3D.create(a,b,1|2|4|8|16|32)
	if is_instance_valid(player_body): query.exclude = [player_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _free_camera(at: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = .13
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,at)
	query.collision_mask = 1|2|4|8|16|32
	if is_instance_valid(player_body): query.exclude = [player_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func begin(actor: Node3D,player: CharacterBody3D,view: Camera3D) -> bool:
	finish()
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not is_instance_valid(player) or not is_instance_valid(view): return false
	if actor.global_position.distance_to(player.global_position)>6.0: return false
	player_body = player
	var focus := actor.global_position+Vector3.UP*1.43
	var candidates := shot_candidates(focus,player.global_position)
	for point in candidates:
		if not _clear(focus,point) or not _free_camera(point): continue
		subject = actor
		previous_camera = get_viewport().get_camera_3d()
		if not is_instance_valid(previous_camera): previous_camera = view
		shot_camera.far = view.far
		shot_origin = point
		var closer := point.lerp(focus,.10)
		shot_end = closer if _free_camera(closer) and _clear(point,closer) else point
		shot_camera.global_position = point
		shot_camera.look_at(focus)
		shot_camera.make_current()
		elapsed = 0.0
		active = true
		set_physics_process(true)
		return true
	# Narrow room or occluded NPC: keep gameplay camera; dialogue still works.
	player_body = null
	return false

func _physics_process(delta: float) -> void:
	if not active: return
	if not is_instance_valid(subject) or not is_instance_valid(previous_camera) or not subject.is_visible_in_tree():
		finish()
		return
	# The ordinary mission tick is paused; keep just the visible actor alive.
	if subject is Person: subject.animate(delta,false)
	elapsed = minf(elapsed+delta,3.0)
	var focus := subject.global_position+Vector3.UP*1.43
	var next := shot_origin.lerp(shot_end,smoothstep(0.0,3.0,elapsed))
	# A pedestrian/vehicle may enter the shot. Fall back instead of clipping.
	if not _clear(focus,next) or not _clear(shot_camera.global_position,next):
		finish()
		return
	shot_camera.global_position = next
	if next.distance_squared_to(focus)>.04: shot_camera.look_at(focus)

func finish() -> void:
	set_physics_process(false)
	if active and is_instance_valid(previous_camera) and is_instance_valid(shot_camera) and shot_camera.is_current():
		previous_camera.make_current()
	active = false
	subject = null
	player_body = null
	previous_camera = null
