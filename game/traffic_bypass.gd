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

# Cooperative gridlock recovery. Requests use deterministic priority, so
# two drivers cannot order each other to yield at the same time.
static func _traffic_rank(body: CharacterBody3D,length: float) -> float:
	return float(body.get_meta("traffic_priority",length))

static func request_space(body: CharacterBody3D,target: Vector3,length: float,width: float) -> void:
	var now := Time.get_ticks_msec()
	if now<int(body.get_meta("traffic_request_after",0)): return
	body.set_meta("traffic_request_after",now+1800)
	var forward := target-body.global_position
	forward.y = 0.0
	if forward.length_squared()<.01: forward = body.global_transform.basis.z
	forward = forward.normalized()
	var side := Vector3(-forward.z,0,forward.x)
	var best: CharacterBody3D
	var best_distance := INF
	var rank := _traffic_rank(body,length)
	for node in body.get_tree().get_nodes_in_group("autonomous_traffic"):
		var other := node as CharacterBody3D
		if other==null or other==body or bool(other.get_meta("traffic_servicing",false)): continue
		if not other.has_meta("traffic_priority"): continue
		var other_rank := _traffic_rank(other,0.0)
		if other_rank>rank or (is_equal_approx(other_rank,rank) and other.get_instance_id()<body.get_instance_id()): continue
		var offset := other.global_position-body.global_position
		var along := offset.dot(forward)
		if absf(offset.y)>1.0 or along<-.5 or along>length*.5+9.0 or absf(offset.dot(side))>width*.5+2.0: continue
		if other.velocity.length()>1.0: continue
		if offset.length_squared()<best_distance:
			best = other
			best_distance = offset.length_squared()
	if best!=null:
		best.set_meta("traffic_yield_from",body.global_position)
		best.set_meta("traffic_yield_until",now+5500)

# Find an independent refuge, not a full overtake that requires the
# original blocked lane to be free before the first wheel can move.
static func _yield_path(body: CharacterBody3D,streets: Streets,width: float,length: float,height: float,requester: Vector3) -> Dictionary:
	var origin := body.global_position
	var heading := body.global_transform.basis.z.normalized()
	var side := Vector3(-heading.z,0,heading.x)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(.15,width-.03),height,maxf(.2,length-.03))
	for sign_value in [1.0,-1.0]:
		for shift in [width+.65,-width-.65,0.0,width+1.55,-width-1.55]:
			for advance in [3.5,5.5,8.0,11.0]:
				var goal := origin+heading*float(sign_value)*float(advance)+side*float(shift)
				# Move away from the requesting vehicle or out of its lane.
				var before := origin-requester
				var after := goal-requester
				if after.length_squared()<before.length_squared()+1.0 and absf(after.dot(side))<absf(before.dot(side))+1.0: continue
				var points: Array = []
				var previous := origin
				var valid := true
				var steps := ceili(float(advance)/.65)
				for i in range(1,steps+1):
					var t := float(i)/float(steps)
					var p := origin+heading*float(sign_value)*float(advance)*t+side*float(shift)*smoothstep(0.0,1.0,t)
					var motion := (p-previous).normalized()
					var face := motion*float(sign_value)
					if not _on_road(streets,p,face,width,length) or not _segment_clear(body,previous,p,face,shape):
						valid = false
						break
					points.append(p)
					previous = p
				if valid and not points.is_empty():
					return {"points":points,"reverse":float(sign_value)<0.0}
	return {}

# Return true only when this vehicle owns a temporary yielding maneuver.
# Ordinary physics safety checks remain active on every movement.
static func cooperate(state: Dictionary,body: CharacterBody3D,streets: Streets,width: float,length: float,height: float,delta: float,stalled_time: float,target: Vector3) -> bool:
	body.set_meta("traffic_priority",length)
	var now := Time.get_ticks_msec()
	var points: Array = state.get("cooperative_path",[])
	if points.is_empty():
		if now<int(state.get("cooperative_hold",0)):
			body.velocity = Vector3.ZERO
			state.speed = 0.0
			return true
		if now<int(body.get_meta("traffic_yield_until",0)) and now>=int(state.get("cooperative_retry",0)):
			state.cooperative_retry = now+1800
			var requester: Vector3 = body.get_meta("traffic_yield_from",body.global_position)
			var choice := _yield_path(body,streets,width,length,height,requester)
			if not choice.is_empty():
				points = choice.points
				state.cooperative_path = points
				state.cooperative_index = 0
				state.cooperative_reverse = bool(choice.reverse)
				state.retreat_remaining = 0.0
				body.remove_meta("traffic_yield_until")
		if points.is_empty():
			if stalled_time>2.0: request_space(body,target,length,width)
			return false
	var index := int(state.cooperative_index)
	var next: Vector3 = points[index]
	var diff := next-body.global_position
	diff.y = 0.0
	if diff.length()<.10:
		index += 1
		state.cooperative_index = index
		if index>=points.size():
			state.cooperative_path = []
			state.cooperative_hold = now+1300
			state.traffic_stall = 0.0
			state.stalled = 0.0
			state.backed_up = 0.0
			state["cooperative_rejoin"] = true
		body.velocity = Vector3.ZERO
		state.speed = 0.0
		return true
	var d := diff.normalized()
	var face := -d if bool(state.cooperative_reverse) else d
	var angle := lerp_angle(body.global_rotation.y,atan2(face.x,face.z),minf(delta*6.0,1.0))
	var step := minf(diff.length(),1.7*delta)
	if not safe_step(body,d,step,angle,delta):
		state.cooperative_path = []
		state.cooperative_hold = now+500
		body.velocity = Vector3.ZERO
	state.speed = 0.0
	state.traffic_last = body.global_position
	state.traffic_stall = 0.0
	state.stalled = 0.0
	return true

# Only ordinary circulating vehicles use this short forward rejoin.
# Service and passenger routes retain their pending destination.
static func rejoin_index(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,height: float) -> int:
	var origin := body.global_position
	var heading := body.global_transform.basis.z.normalized()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,height,length)
	var best := index
	var best_distance := INF
	for offset in range(mini(12,route.size())):
		var at := (index+offset)%route.size()
		var item: Dictionary = route[at]
		if item.has("stop") or (offset>0 and not String(item.get("node","")).is_empty()): break
		var p: Vector3 = item.p
		p.y = origin.y
		var diff := p-origin
		var distance := diff.length()
		if distance<.5 or distance>16.0 or diff.normalized().dot(heading)<.25: continue
		if distance>=best_distance: continue
		var d := diff.normalized()
		var valid := true
		var previous := origin
		var count := ceili(distance/.75)
		for i in range(1,count+1):
			var q := origin.lerp(p,float(i)/float(count))
			if not _on_road(streets,q,d,width,length) or not _segment_clear(body,previous,q,d,shape):
				valid = false
				break
			previous = q
		if valid:
			best = at
			best_distance = distance
	return best
