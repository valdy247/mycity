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
# A four-lane road has an overtaking lane in the same direction.
# Do not search the opposing carriageway for a bypass on this corridor.
static func _four_lane_pass(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary,height: float,lane: Dictionary) -> Dictionary:
	var origin := body.global_position
	var forward: Vector3 = lane.direction
	var right: Vector3 = lane.right
	var lateral := float(lane.lateral)
	var half := float(lane.half)
	var passing := half*.25 if lateral>half*.50 else half*.75
	var change := passing-lateral
	if absf(change)<.5: return {}
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.06,height,length+.06)
	# A short gradual shift can be followed by a longer run in the free lane.
	# Never skip a service stop, a signal or a destination.
	var options: Array = []
	for i in range(index,mini(route.size(),index+65)):
		var item: Dictionary = route[i]
		var p: Vector3 = item.p
		var diff := p-origin
		var along := diff.dot(forward)
		var cross := diff.dot(right)
		if along<-.5 or absf(cross)>half+.5: break
		var mandatory := item.has("stop") or signals.has(String(item.get("node",""))) or i==route.size()-1
		if along>=12.0 and along<=55.0:
			options.append({"index":i,"along":along,"cross":cross})
		if mandatory or along>55.0: break
	for option in options:
		var total := float(option.along)
		# Give long vehicles more room to change lanes without sweeping
		# their rear into the other lane or a parked vehicle.
		var transition := maxf(7.0,length*1.55)
		if total<transition*2.0+2.0: continue
		for leave in [transition,transition+2.0]:
			var steps := ceili(total/.8)
			var previous := origin
			var points: Array = []
			var valid := true
			for j in range(1,steps+1):
				var along := total*float(j)/float(steps)
				var out := smoothstep(0.0,float(leave),along)
				var back := smoothstep(total-transition,total,along)
				var cross := lerpf(change*out,float(option.cross),back)
				var p := origin+forward*along+right*cross
				var d := (p-previous).normalized()
				if not streets.in_carriageway(p,d,width,length) or not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
					valid = false
					break
				# The normal waypoint remains the final target.
				if j<steps: points.append({"p":p,"node":"","bypass":true})
				previous = p
			if valid and not points.is_empty():
				return {"path":points,"resume":int(option.index)}
	return {}

static func recover(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary = {},height: float = 1.8) -> Dictionary:
	if bool(body.get_meta("junction_guard",false)): return {}
	if index<0 or index>=route.size(): return {}
	var lane := streets.four_lane_at(body.global_position,body.global_transform.basis.z)
	if not lane.is_empty():
		return _four_lane_pass(body,route,index,streets,width,length,signals,height,lane)
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
	if bool(body.get_meta("junction_guard",false)):
		state.retreat_remaining = 0.0
		return false
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
	var candidates := body.get_tree().get_nodes_in_group("autonomous_traffic")
	candidates.append_array(body.get_tree().get_nodes_in_group("traffic_parked"))
	for node in candidates:
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
	if bool(body.get_meta("junction_guard",false)): return false
	body.set_meta("traffic_priority",length)
	# On Monte, lane discipline replaces arbitrary refuge manoeuvres.
	if stalled_time>.6 or not (state.get("cooperative_path",[]) as Array).is_empty() or body.has_meta("traffic_yield_until"):
		if not streets.four_lane_at(body.global_position,body.global_transform.basis.z).is_empty():
			state.cooperative_path = []
			state.cooperative_hold = 0
			body.remove_meta("traffic_yield_until")
			return false
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

# Initiate a lane change before the driver has reached a complete stop.
# The expensive path search is still throttled by each driver's cooldown.
static func early_lane_pass(body: CharacterBody3D,streets: Streets,blocked: bool,free: float) -> bool:
	return blocked and free>1.3 and not streets.four_lane_at(body.global_position,body.global_transform.basis.z).is_empty()

# Intersection admission: reserve one crossing at a time, before the
# vehicle's nose enters the junction. Verify that its tail can exit too.
static func _junction_samples(origin: Vector3,route: Array,index: int,loop: bool,continuation: Array,resume: int) -> Array:
	var samples: Array = [{"p":origin,"distance":0.0,"d":Vector3.ZERO}]
	var previous := origin
	var traveled := 0.0
	var points: Array = []
	for offset in range(mini(80,route.size())):
		var at := index+offset
		if at>=route.size() and not loop: break
		points.append(route[at%route.size()])
	if not continuation.is_empty():
		for offset in range(mini(45,continuation.size())):
			points.append(continuation[(resume+offset)%continuation.size()])
	for item in points:
		var target: Vector3 = item.p if item is Dictionary else item
		target.y = origin.y
		var diff := target-previous
		var length := diff.length()
		if length<.01: continue
		var d := diff/length
		var extent := minf(length,48.0-traveled)
		if extent<=.01: break
		var count := maxi(1,ceili(extent/1.0))
		for i in range(1,count+1):
			var step := extent*float(i)/float(count)
			samples.append({"p":previous+d*step,"distance":traveled+step,"d":d})
		traveled += extent
		previous = target
		if traveled>=47.99: break
	return samples

static func _flat_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x-b.x,a.z-b.z).length()

static func _junction_occupied(body: CharacterBody3D,junction: Dictionary) -> bool:
	var shape := CylinderShape3D.new()
	shape.radius = float(junction.radius)
	shape.height = 3.8
	var p: Vector3 = junction.p
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY,p+Vector3.UP*1.9)
	q.collision_mask = 1|4|8
	q.exclude = [body.get_rid()]
	for hit in body.get_world_3d().direct_space_state.intersect_shape(q,64):
		if hit.collider is CharacterBody3D: return true
	return false

static func _junction_exit_clear(body: CharacterBody3D,samples: Array,first: int,last: int,width: float,length: float,height: float) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.10,height,length+.30)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1|4|8
	q.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	for i in range(maxi(1,first),last+1):
		var p: Vector3 = samples[i].p
		var d: Vector3 = samples[i].d
		q.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(height*.5+.08))
		for hit in space.intersect_shape(q,32):
			if hit.collider is CharacterBody3D: return false
	return true

static func _junction_release(state: Dictionary,body: CharacterBody3D,streets: Streets) -> void:
	var id := String(state.get("junction_claim",""))
	if not id.is_empty():
		var claim: Dictionary = streets.intersection_claims.get(id,{})
		if int(claim.get("owner",0))==body.get_instance_id(): streets.intersection_claims.erase(id)
	state.erase("junction_claim")
	state.erase("junction_entered")

# Returns metres of permitted forward travel, or -1 when unrestricted.
# The caller uses both a braking curve and a hard per-frame movement cap.
static func junction_gate(state: Dictionary,body: CharacterBody3D,streets: Streets,route: Array,index: int,loop: bool,width: float,length: float,height: float,delta: float,continuation: Array = [],resume: int = 0) -> float:
	var origin := body.global_position
	var extent := Vector2(length,width).length()*.5
	var owner := body.get_instance_id()
	var now := Time.get_ticks_msec()
	body.set_meta("junction_guard",false)
	var held := String(state.get("junction_claim",""))
	if not held.is_empty():
		var claim: Dictionary = streets.intersection_claims.get(held,{})
		if int(claim.get("owner",0))!=owner:
			state.erase("junction_claim")
			state.erase("junction_entered")
		else:
			var old: Dictionary = claim.junction
			var old_center: Vector3 = old.p
			var away := _flat_distance(origin,old_center)
			var radius := float(old.radius)+extent
			if away<radius+.10: state.junction_entered = true
			if bool(state.get("junction_entered",false)) and away>radius+1.0:
				_junction_release(state,body,streets)
			elif not bool(state.get("junction_entered",false)) and now-int(claim.since)>8500:
				_junction_release(state,body,streets)
			else:
				body.set_meta("junction_guard",true)
				return -1.0
	if route.is_empty() or index<0 or index>=route.size(): return -1.0
	var nearby := streets.intersections_near(origin,34.0)
	if nearby.is_empty():
		state.erase("junction_signal_id")
		return -1.0
	var samples := _junction_samples(origin,route,index,loop,continuation,resume)
	var selected: Dictionary = {}
	var entry := -1
	var exit := -1
	var stop_distance := INF
	for junction in nearby:
		var center: Vector3 = junction.p
		var radius := float(junction.radius)+extent+.65
		var first := -1
		var last := -1
		for i in range(samples.size()):
			var p: Vector3 = samples[i].p
			var inside := _flat_distance(p,center)<=radius
			if first<0:
				if inside: first = i
			elif not inside:
				last = i
				break
		if first<0: continue
		var limit := 0.0 if first==0 else float(samples[first-1].distance)
		if limit>=stop_distance: continue
		selected = junction
		entry = first
		exit = last
		stop_distance = limit
	if selected.is_empty():
		state.erase("junction_signal_id")
		return -1.0
	var center: Vector3 = selected.p
	var id := String(selected.id)
	var occupied_radius := float(selected.radius)+extent
	var already_inside := _flat_distance(origin,center)<occupied_radius-.05
	# A vehicle already inside must clear the box, not stop for a red
	# light or reverse across crossing traffic.
	if already_inside:
		body.set_meta("junction_guard",true)
		if not streets.intersection_claims.has(id):
			streets.intersection_claims[id] = {"owner":owner,"since":now,"junction":selected}
			state.junction_claim = id
			state.junction_entered = true
		return -1.0
	if stop_distance>maxf(8.0,float(state.get("speed",0.0))*1.2+3.0): return stop_distance
	body.set_meta("junction_guard",true)
	# Signal dwell occurs at the approach, never at the mapped node.
	if bool(selected.signal):
		if String(state.get("junction_signal_id",""))!=id:
			state.junction_signal_id = id
			state.junction_signal_wait = 0.0
		if stop_distance<=.12 and float(state.get("speed",0.0))<.15:
			state.junction_signal_wait = float(state.junction_signal_wait)+delta
		if float(state.junction_signal_wait)<2.0: return stop_distance
	# Don't lock the box far in advance; queue at the line first.
	if stop_distance>2.0: return stop_distance
	var existing: Dictionary = streets.intersection_claims.get(id,{})
	if not existing.is_empty():
		var other := instance_from_id(int(existing.owner)) as CharacterBody3D
		if not is_instance_valid(other):
			streets.intersection_claims.erase(id)
		elif int(existing.owner)!=owner:
			var other_extent := float(other.get_meta("junction_extent",4.5))
			if now-int(existing.since)>8500 and _flat_distance(other.global_position,center)>float(selected.radius)+other_extent+.2:
				streets.intersection_claims.erase(id)
			else: return stop_distance
	# If the route ends inside the crossing, refuse entry. A legal exit
	# must fit the whole vehicle, plus a little space beyond its tail.
	if exit<0: return stop_distance
	if now<int(state.get("junction_retry",0)): return stop_distance
	state.junction_retry = now+250
	if _junction_occupied(body,selected): return stop_distance
	var last := mini(samples.size()-1,exit+2)
	if not _junction_exit_clear(body,samples,entry,last,width,length,height): return stop_distance
	streets.intersection_claims[id] = {"owner":owner,"since":now,"junction":selected}
	body.set_meta("junction_extent",extent)
	state.junction_claim = id
	state.junction_entered = false
	return -1.0

static func junction_speed(speed: float,limit: float,brake: float) -> float:
	return speed if limit<0.0 else minf(speed,sqrt(2.0*brake*maxf(0.0,limit)))

static func junction_advance(advance: float,limit: float) -> float:
	return advance if limit<0.0 else minf(advance,maxf(0.0,limit))
