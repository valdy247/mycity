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
	query.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(shape.size.y*.5+.07))
	query.collision_mask = 1|4|8
	query.exclude = [body.get_rid()]
	return body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

static func find(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary = {},height: float = 1.8) -> Dictionary:
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
	shape.size = Vector3(width+.12,height,length+.12)
	var steps := ceili(max_distance/.75)
	for side in [-1.0,1.0]:
		for amount in [width+.25,width+.55,width+1.0,width+1.55,width+2.10,width+2.80]:
			var shift := float(side)*float(amount)
			var points: Array = []
			var valid := true
			var previous := origin
			for i in range(1,steps+1):
				var t := float(i)/float(steps)
				var ramp := smoothstep(0.0,.23,t)*(1.0-smoothstep(.77,1.0,t))
				var p := origin+forward*(max_distance*t)+right*(lateral*t+shift*ramp)
				var d := (p-previous).normalized()
				if not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
					valid = false
					break
				points.append({"p":p,"node":"","bypass":true})
				previous = p
			if valid and not points.is_empty():
				return {"path":points,"resume":resume}
	return {}

# Check a complete swept envelope, including between samples.
static func _segment_clear(body: CharacterBody3D,a: Vector3,b: Vector3,d: Vector3,shape: BoxShape3D) -> bool:
	if not _clear(body,b,d,shape): return false
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),a+Vector3.UP*(shape.size.y*.5+.07))
	q.collision_mask = 1|4|8
	q.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	if not space.intersect_shape(q,1).is_empty(): return false
	q.motion = b-a
	var sweep := space.cast_motion(q)
	return sweep.size()>=2 and sweep[0]>=.999

# A shorter lane change is useful when the next stop or a tight bend
# prevents a full overtake. Always resume the same original waypoint.
static func recover(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary = {},height: float = 1.8) -> Dictionary:
	var normal := find(body,route,index,streets,width,length,signals,height)
	if not normal.is_empty(): return normal
	if index<0 or index>=route.size(): return {}
	var origin := body.global_position
	var target: Vector3 = route[index].p
	target.y = origin.y
	var heading := body.global_transform.basis.z.normalized()
	var left := Vector3(heading.z,0,-heading.x)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.08,height,length+.08)
	# Left includes the opposing lane, but its swept space must be free.
	# No building, sidewalk or occupied lane is accepted.
	for shift in [width+.35,width+1.15,width+2.0,-width-.35,-width-1.15,0.0]:
		for advance in [5.0,8.0,11.0,14.0]:
			var goal := origin+heading*float(advance)+left*float(shift)
			if goal.distance_to(target)>origin.distance_to(target)+2.0: continue
			if goal.distance_to(target)<.30: continue
			var points: Array = []
			var previous := origin
			var valid := true
			var steps := ceili(float(advance)/.7)
			for j in range(1,steps+1):
				var t := float(j)/float(steps)
				var p := origin+heading*float(advance)*t+left*float(shift)*smoothstep(0.0,1.0,t)
				var d := (p-previous).normalized()
				if not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
					valid = false
					break
				points.append({"p":p,"node":"","bypass":true})
				previous = p
			if valid and not points.is_empty():
				# Validate the rejoin too, rather than trapping a vehicle
				# on the opposite side of the road after a lane change.
				var tail := target-previous
				var tail_steps := maxi(1,ceili(tail.length()/.8))
				if tail_steps>55: continue
				for j in range(1,tail_steps+1):
					var p := goal.lerp(target,float(j)/float(tail_steps))
					var d := (p-previous).normalized()
					if d.length_squared()<.01: continue
					if not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
						valid = false
						break
					if j<tail_steps: points.append({"p":p,"node":"","bypass":true})
					previous = p
				if valid: return {"path":points,"resume":index}
	return {}

# Measure actual progress, not merely a sensor reporting an obstacle.
# A driver can be stuck even with a clear centreline.
static func stalled(state: Dictionary,body: CharacterBody3D,delta: float) -> float:
	var prior: Vector3 = state.get("traffic_last",body.global_position)
	var elapsed := float(state.get("traffic_stall",0.0))
	if body.global_position.distance_to(prior)<.10*delta:
		elapsed += delta
	else:
		elapsed = maxf(0.0,elapsed-delta*3.0)
	state.traffic_last = body.global_position
	state.traffic_stall = elapsed
	return elapsed

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
	if body.test_move(body.global_transform,Vector3.ZERO,null,.001,true) or body.test_move(body.global_transform,d*advance):
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

# Keep reverse manoeuvres active across frames. Otherwise a few centimetres
# of reverse progress reset the stall detector and cause forward/reverse loops.
static func retreat(state: Dictionary,body: CharacterBody3D,streets: Streets,width: float,length: float,delta: float,requested: bool) -> bool:
	var remaining := float(state.get("retreat_remaining",0.0))
	if remaining<=0.0:
		if not requested or float(state.get("backed_up",0.0))>=5.5: return false
		remaining = minf(3.5,5.5-float(state.get("backed_up",0.0)))
	if not reverse_clear(body,streets,width,length,delta):
		state.retreat_remaining = 0.0
		return false
	var step := .8*delta
	state.retreat_remaining = maxf(0.0,remaining-step)
	state.backed_up = float(state.get("backed_up",0.0))+step
	state.traffic_last = body.global_position
	state.traffic_stall = 4.0
	return true
