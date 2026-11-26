extends RefCounted
# Shared conservative local overtaking planner. No teleporting or driving
# on sidewalks: validate the swept vehicle footprint on asphalt and check
# both static geometry and other vehicles before accepting a manoeuvre.
const Streets = preload("res://street_geometry.gd")

static func _on_road(streets: Streets,p: Vector3,d: Vector3,w: float,l: float) -> bool:
	var side := Vector3(-d.z,0,d.x)
	for x in [-1.0,1.0]:
		for z in [-1.0,1.0]:
			if not streets.point_on_road(p+side*float(x)*(w*.5+.08)+d*float(z)*(l*.5+.08)):
				return false
	return streets.point_on_road(p)

static func _clear(body: CharacterBody3D,p: Vector3,d: Vector3,shape: BoxShape3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*.91)
	query.collision_mask = 1|4
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

static func find(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary = {}) -> Dictionary:
	if index<0 or index>=route.size(): return {}
	var origin := body.global_position
	var forward := body.global_transform.basis.z.normalized()
	forward.y = 0.0
	var right := Vector3(-forward.z,0,forward.x)
	var max_distance := 0.0
	var resume := index
	var lateral := 0.0
	for i in range(index,mini(route.size(),index+65)):
		var item: Dictionary = route[i]
		var p: Vector3 = item.p
		var diff := p-origin
		var along := diff.dot(forward)
		var cross := diff.dot(right)
		if along<-.5 or absf(cross)>1.5: break
		var must_stop := item.has("stop") or signals.has(String(item.get("node",""))) or i==route.size()-1
		if along>=12.0:
			max_distance = minf(34.0,along-(3.5 if must_stop else 1.0))
			resume = i
			lateral = cross*max_distance/maxf(along,.1)
			if max_distance>=25.0 or must_stop: break
		if must_stop: break
	if max_distance<12.0: return {}
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.25,1.45,length+.25)
	var steps := ceili(max_distance/.75)
	for side in [-1.0,1.0]:
		for amount in [width+.25,width+.55,width+1.0,width+1.55]:
			var shift := float(side)*float(amount)
			var points: Array = []
			var valid := true
			var previous := origin
			for i in range(1,steps+1):
				var t := float(i)/float(steps)
				var ramp := smoothstep(0.0,.23,t)*(1.0-smoothstep(.77,1.0,t))
				var p := origin+forward*(max_distance*t)+right*(lateral*t+shift*ramp)
				var d := (p-previous).normalized()
				if not _on_road(streets,p,d,width,length) or not _clear(body,p,d,shape):
					valid = false
					break
				points.append({"p":p,"node":"","bypass":true})
				previous = p
			if valid and not points.is_empty():
				return {"path":points,"resume":resume}
	return {}

# Full-width lookahead shared by all autonomous street vehicles.
static func clear_distance(body: CharacterBody3D,d: Vector3,reach: float,width: float,length: float,height: float = 1.8) -> float:
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.10,height,length+.10)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(body.global_transform.basis.orthonormalized(),body.global_position+Vector3.UP*(height*.5+.10))
	query.collision_mask = 1|4|8
	query.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty(): return 0.0
	query.motion = d*reach
	var result := space.cast_motion(query)
	return reach*result[0] if result.size()>=2 else 0.0

static func safe_step(body: CharacterBody3D,d: Vector3,advance: float,angle: float,delta: float) -> bool:
	var previous := body.global_rotation.y
	body.global_rotation.y = angle
	if body.test_move(body.global_transform,d*advance):
		body.global_rotation.y = previous
		body.velocity = Vector3.ZERO
		return false
	body.velocity = d*advance/maxf(delta,.001)
	body.move_and_slide()
	return true

static func reverse_clear(body: CharacterBody3D,streets: Streets,width: float,length: float,delta: float) -> bool:
	var direction := body.global_transform.basis.z.normalized()
	var step := .8*delta
	if not _on_road(streets,body.global_position-direction*step,direction,width,length): return false
	if body.test_move(body.global_transform,-direction*(step+.5)): return false
	body.velocity = -direction*.8
	body.move_and_slide()
	return true
