extends RefCounted
# Shared conservative local overtaking planner. Ordinary movement checks
# the swept footprint. The separate watchdog may reposition stranded
# vehicles only onto a verified free asphalt pose as a last resort.
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
	query.collision_mask = 1|4|8|32
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
	q.collision_mask = 1|4|8|32
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
	# Select a clear waypoint beyond the obstacle, not necessarily the next
	# waypoint. Never skip a stop, signal, destination or turning segment.
	var options: Array = []
	var previous_along := 0.0
	for i in range(index,mini(route.size(),index+65)):
		var item: Dictionary = route[i]
		var p: Vector3 = item.p
		var diff := p-origin
		var along := diff.dot(forward)
		var cross := diff.dot(right)
		if along<-.5 or along<previous_along-.5 or absf(cross)>half+.5: break
		previous_along = maxf(previous_along,along)
		var mandatory := item.has("stop") or signals.has(String(item.get("node",""))) or i==route.size()-1
		if along>=9.0 and along<=60.0:
			options.append({"index":i,"along":along,"cross":cross})
		if mandatory or along>60.0: break
	# Try shorter transitions for cars and longer ones for buses. A full
	# sweep of the rotated footprint still rejects an unsafe short turn.
	var base := maxf(4.0,length*.95)
	var back_length := maxf(4.0,length*1.10)
	for leave in [base,base+2.0,maxf(7.0,length*1.55)]:
		for option in options:
			var total := float(option.along)
			if total<float(leave)+back_length+length: continue
			var steps := ceili(total/.85)
			var previous := origin
			var points: Array = []
			var valid := true
			for j in range(1,steps+1):
				var along := total*float(j)/float(steps)
				var out := smoothstep(0.0,float(leave),along)
				var back := smoothstep(total-back_length,total,along)
				var cross := lerpf(change*out,float(option.cross),back)
				var p := origin+forward*along+right*cross
				var d := (p-previous).normalized()
				if not streets.in_carriageway(p,d,width,length,forward) or not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
					valid = false
					break
				# The ordinary junction controller still governs crossing entry.
				if j<steps: points.append({"p":p,"node":"","bypass":true})
				previous = p
			if valid and not points.is_empty():
				return {"path":points,"resume":int(option.index)}
	return {}

# Emergency overtaking is allowed across the painted centreline, not
# across sidewalks, physical medians, occupied lanes or junctions.
# Check the complete outward/return manoeuvre before committing.
static func _opposing_pass(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary,height: float) -> Dictionary:
	if streets.map_data==null or not streets.intersection_clear_for_stop(body.global_position,length,width): return {}
	var origin := body.global_position
	var heading := body.global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var chosen: Dictionary = {}
	var best := INF
	var forward := heading
	var center := origin
	for edge in streets.map_data.roads_near(origin,12.0):
		if not bool(edge.get("driveable",false)): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var first := String(edge.a_id)
		var last := String(edge.b_id)
		if not streets.map_data.graph.get(first,[]).has(last) or not streets.map_data.graph.get(last,[]).has(first): continue
		var axis := (b-a).normalized()
		if absf(axis.dot(heading))<.82: continue
		var nearest := Geometry3D.get_closest_point_to_segment(Vector3(origin.x,0,origin.z),a,b)
		var distance := Vector2(origin.x-nearest.x,origin.z-nearest.z).length()
		if distance>float(edge.width)*.5+.1 or distance>=best: continue
		best = distance
		chosen = edge
		forward = axis if axis.dot(heading)>0.0 else -axis
		center = nearest
	if chosen.is_empty(): return {}
	var right := Vector3(-forward.z,0,forward.x)
	var lateral := (origin-center).dot(right)
	var half := float(chosen.width)*.5
	var lane_center := -maxf(width*.5+.20,half*(.25 if int(chosen.get("lanes_per_direction",1))==2 else .50))
	if absf(lane_center)+width*.5+.10>half: return {}
	var change := lane_center-lateral
	if absf(change)<.45: return {}
	# Never overtake just because an intersection admission or signal is
	# holding this vehicle. The existing junction controller stays in charge.
	var options: Array = []
	var previous_along := 0.0
	for i in range(index,mini(route.size(),index+70)):
		var item: Dictionary = route[i]
		var p: Vector3 = item.p
		var diff := p-origin
		var along := diff.dot(forward)
		var cross := diff.dot(right)
		if along<-.7 or along<previous_along-.7 or absf(cross)>half+.6: break
		previous_along = maxf(previous_along,along)
		var mandatory := item.has("stop") or signals.has(String(item.get("node",""))) or i==route.size()-1
		if along>=maxf(12.0,length*3.0) and along<=55.0 and streets.intersection_clear_for_stop(p,length,width):
			# End on the original side, not at an arbitrary oncoming waypoint.
			if lateral+cross>=width*.5: options.append({"p":p,"along":along,"cross":cross,"index":i})
		if mandatory or along>55.0: break
	if options.is_empty(): return {}
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.10,height,length+.10)
	# Predict approaching traffic over the duration of the low-speed pass.
	var traffic := body.get_tree().get_nodes_in_group("autonomous_traffic")
	var oncoming: Array[Dictionary] = []
	for node in traffic:
		if not node is CharacterBody3D or node==body or not is_instance_valid(node): continue
		var other := node as CharacterBody3D
		var diff := other.global_position-origin
		if absf(diff.y)>2.5 or diff.length_squared()>22500.0: continue
		var along := diff.dot(forward)
		var cross := lateral+diff.dot(right)
		if along< -length or cross>width*.5 or other.global_basis.z.dot(forward)>-.5: continue
		oncoming.append({"along":along,"speed":maxf(0.0,-other.velocity.dot(forward))})
	var leave_base := maxf(4.5,length*1.1+absf(change)*.6)
	for option in options:
		var total := float(option.along)
		var returning := maxf(4.5,length*1.15+absf(change)*.55)
		var unsafe := false
		for other in oncoming:
			# The pass is driven at at most 4 m/s. Keep a buffer for
			# vehicles already approaching and recheck each physical step.
			if float(other.along)<total+length+8.0+maxf(3.0,float(other.speed))*(total/3.0+2.0):
				unsafe = true
				break
		if unsafe: continue
		for leave in [leave_base,leave_base+2.0]:
			if total<float(leave)+returning+length: continue
			var steps := ceili(total/.85)
			var previous := origin
			var points: Array = []
			var valid := true
			for j in range(1,steps+1):
				var along := total*float(j)/float(steps)
				var cross := lerpf(change*smoothstep(0.0,float(leave),along),float(option.cross),smoothstep(total-returning,total,along))
				var p := origin+forward*along+right*cross
				var d := (p-previous).normalized()
				if not streets.intersection_clear_for_stop(p,length,width) or not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
					valid = false
					break
				if j<steps: points.append({"p":p,"node":"","bypass":true,"opposing_pass":true})
				previous = p
			if valid and not points.is_empty(): return {"path":points,"resume":int(option.index)}
	return {}

# Shift requests an actual left detour even near junction approaches.
# Preserve named signals/stops and validate the full swept footprint.
static func requested_left_pass(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary = {},height: float = 1.8) -> Dictionary:
	if index<0 or index>=route.size(): return {}
	var origin := body.global_position
	var forward := body.global_basis.z.normalized()
	forward.y = 0.0
	var left := Vector3(forward.z,0,-forward.x)
	var options: Array = []
	var along_last := 0.0
	for i in range(index,mini(route.size(),index+65)):
		var item: Dictionary = route[i]
		var target: Vector3 = item.p
		var diff := target-origin
		var along := diff.dot(forward)
		if along<-.6 or along<along_last-.6 or absf(diff.dot(left))>maxf(2.0,width): break
		along_last = maxf(along,along_last)
		if along>=maxf(8.0,length*2.2) and along<=52.0:
			options.append({"along":along,"cross":diff.dot(left),"index":i})
		if item.has("stop") or signals.has(String(item.get("node",""))) or i==route.size()-1 or along>52.0: break
	if options.is_empty(): return {}
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.08,height,length+.08)
	var traffic := body.get_tree().get_nodes_in_group("autonomous_traffic")
	for shift in [width+.45,width+1.3,width+2.2,width+3.0]:
		var amount := float(shift)
		for option in options.slice(0,8):
			var total := float(option.along)
			var ramp := maxf(2.6,length*.85+amount*.35)
			if total<ramp*2.0+length: continue
			var unsafe := false
			for node in traffic:
				var other := node as CharacterBody3D
				if not is_instance_valid(other) or other==body: continue
				var diff := other.global_position-origin
				var gap := diff.dot(forward)
				if absf(diff.y)>2.0 or gap<0.0 or gap>140.0: continue
				if other.global_basis.z.dot(forward)>-.55: continue
				if absf(diff.dot(left)-amount)>width+2.0: continue
				if gap<total+length+6.0+maxf(2.0,-other.velocity.dot(forward))*(total/3.0+1.5):
					unsafe = true
					break
			if unsafe: continue
			var count := maxi(4,ceili(total/.8))
			var points: Array = []
			var previous := origin
			var valid := true
			for j in range(1,count+1):
				var along := total*float(j)/float(count)
				var cross := amount*smoothstep(0.0,ramp,along)*(1.0-smoothstep(total-ramp,total,along))+float(option.cross)*smoothstep(total-ramp,total,along)
				var p := origin+forward*along+left*cross
				var d := (p-previous).normalized()
				if not _on_road(streets,p,d,width,length) or not _segment_clear(body,previous,p,d,shape):
					valid = false
					break
				if j<count: points.append({"p":p,"node":"","bypass":true,"requested_left":true})
				previous = p
			if valid and not points.is_empty(): return {"path":points,"resume":int(option.index)}
	return {}

static func recover(body: CharacterBody3D,route: Array,index: int,streets: Streets,width: float,length: float,signals: Dictionary = {},height: float = 1.8) -> Dictionary:
	if bool(body.get_meta("junction_guard",false)): return {}
	if index<0 or index>=route.size(): return {}
	var lane := streets.four_lane_at(body.global_position,body.global_transform.basis.z)
	if not lane.is_empty():
		var same_lane := _four_lane_pass(body,route,index,streets,width,length,signals,height,lane)
		if not same_lane.is_empty(): return same_lane
		return _opposing_pass(body,route,index,streets,width,length,signals,height)
	var opposite := _opposing_pass(body,route,index,streets,width,length,signals,height)
	if not opposite.is_empty(): return opposite
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
# Watchdog is sampled twice per second. Unlike the short stall timer,
# reversing a few centimetres or discarding a detour cannot reset it.
static func _route_point(route: Array,index: int) -> Vector3:
	var item = route[index]
	return item if item is Vector3 else item.p

static func _mandatory_waypoint(route: Array,index: int) -> bool:
	var item = route[index]
	return item is Dictionary and (item.has("stop") or not String(item.get("node","")).is_empty())

static func _recovery_pose_clear(body: CharacterBody3D,streets: Streets,p: Vector3,d: Vector3,width: float,length: float,height: float) -> bool:
	if not p.is_finite() or d.length_squared()<.5: return false
	if not _on_road(streets,p,d,width,length) or not streets.intersection_clear_for_stop(p,length,width): return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.24,height,length+.30)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(height*.5+.07))
	query.collision_mask = 1|4|8|16|32
	query.exclude = [body.get_rid()]
	if not body.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	# Pedestrians are often visual-only actors; check them on rare recovery.
	var side := Vector3(-d.z,0,d.x)
	for node in body.get_tree().get_nodes_in_group("pedestrian_spacing"):
		if not node is Node3D or not node.is_visible_in_tree() or body.is_ancestor_of(node): continue
		var offset: Vector3 = node.global_position-p
		if absf(offset.y)>1.5: continue
		if absf(offset.dot(side))<width*.5+.65 and absf(offset.dot(d))<length*.5+.85: return false
	return true

# Return a valid original-route index or -1. Normal reversing and bypass
# remain the first response. Reposition only as a last resort on free asphalt.
static func reset_watchdog(state: Dictionary) -> void:
	if not state.has("watch_anchor"): return
	for key in ["watch_anchor","watch_elapsed","watch_still","watch_offroad","watch_safe","watch_retry","watch_report"]:
		state.erase(key)

static func watchdog(state: Dictionary,body: CharacterBody3D,streets: Streets,route: Array,index: int,width: float,length: float,height: float,delta: float,loop: bool = true) -> int:
	if route.is_empty() or index<0 or index>=route.size(): return -1
	state.watch_elapsed = float(state.get("watch_elapsed",0.0))+delta
	if float(state.watch_elapsed)<.5: return -1
	var elapsed: float = state.watch_elapsed
	state.watch_elapsed = 0.0
	var origin := body.global_position
	var heading := body.global_basis.z.normalized()
	var on_road := _on_road(streets,origin,heading,width,length)
	var anchor: Vector3 = state.get("watch_anchor",origin)
	if origin.distance_squared_to(anchor)>4.0:
		state.watch_anchor = origin
		state.watch_still = 0.0
	else:
		state.watch_anchor = anchor
		state.watch_still = float(state.get("watch_still",0.0))+elapsed
	state.watch_offroad = 0.0 if on_road else float(state.get("watch_offroad",0.0))+elapsed
	# Save a small checkpoint only on safe road, outside junctions.
	if on_road and streets.intersection_clear_for_stop(origin,length,width):
		state.watch_safe = {"p":origin,"d":heading,"index":index}
	# Briefly crossing an irregular corner is not the same as being stranded.
	var offroad := float(state.watch_offroad)>=2.0 and (not streets.point_on_road(origin) or float(state.watch_still)>=3.0)
	var stuck := float(state.watch_still)>=30.0
	if not offroad and not stuck: return -1
	var now := Time.get_ticks_msec()
	if now<int(state.get("watch_retry",0)): return -1
	state.watch_retry = now+4000
	var options: Array = []
	# Search forward along the current road but never pass a stop, named
	# junction or destination. Sample the segment approaching that point.
	for offset in range(mini(8,route.size())):
		var raw := index+offset
		if raw>=route.size() and not loop: break
		var at := raw%route.size()
		var previous := at-1
		if previous<0:
			if not loop: previous = at
			else: previous = route.size()-1
		var target := _route_point(route,at)
		var start := _route_point(route,previous)
		var direction := target-start
		direction.y = 0.0
		if direction.length_squared()<.1:
			direction = target-origin
			direction.y = 0.0
		if direction.length_squared()<.1: direction = heading
		direction = direction.normalized()
		var projection := Geometry3D.get_closest_point_to_segment(origin,Vector3(start.x,origin.y,start.z),Vector3(target.x,origin.y,target.z))
		for meters in [2.0,5.0,9.0,14.0]:
			var candidate := projection+direction*float(meters)
			if (target-candidate).dot(direction)<.4: candidate = Vector3(target.x,origin.y,target.z)-direction*.6
			if origin.distance_to(candidate)>25.0 or origin.distance_to(candidate)<1.5: continue
			if (candidate-Vector3(start.x,origin.y,start.z)).dot(direction)<-.2: continue
			if offset>0 and not streets.intersection_clear_for_stop(projection,length,width): continue
			options.append({"p":candidate,"d":direction,"index":at})
		if _mandatory_waypoint(route,at): break
	# A checkpoint is only useful if it belongs to the same pending leg.
	var saved: Dictionary = state.get("watch_safe",{})
	if not saved.is_empty() and int(saved.index)==index and origin.distance_to(saved.p)>1.5 and origin.distance_to(saved.p)<35.0:
		if offroad: options.push_front(saved)
		else: options.append(saved)
	# For off-road cases, a point behind the target can be safer than
	# forcing a short, impossible turn. Keep the same pending waypoint.
	var target := _route_point(route,index)
	var direction := target-origin
	direction.y = 0.0
	if index>0: direction = _route_point(route,index)-_route_point(route,index-1)
	direction.y = 0.0
	if direction.length_squared()<.1: direction = heading
	direction = direction.normalized()
	for meters in [3.0,6.0,10.0,16.0]:
		var candidate := Vector3(target.x,origin.y,target.z)-direction*float(meters)
		if origin.distance_to(candidate)<=35.0 and origin.distance_to(candidate)>1.5:
			options.append({"p":candidate,"d":direction,"index":index})
	# If all original-lane recovery poses are blocked, check a neighbouring
	# lane on the same carriageway. Retain the pending route waypoint.
	var alternate: Array = []
	for option in options:
		var p: Vector3 = option.p
		var d: Vector3 = option.d
		var lane := streets.four_lane_at(p,d)
		if lane.is_empty(): continue
		var side: Vector3 = lane.right
		var half := float(lane.half)
		var lateral := float(lane.lateral)
		for target_lateral in [half*.25,half*.75]:
			var candidate := p+side*(float(target_lateral)-lateral)
			if candidate.distance_to(origin)<1.5: continue
			if not streets.in_carriageway(candidate,d,width,length,d): continue
			alternate.append({"p":candidate,"d":d,"index":int(option.index)})
	options.append_array(alternate)
	for option in options:
		var p: Vector3 = option.p
		var d: Vector3 = option.d
		if not _recovery_pose_clear(body,streets,p,d,width,length,height): continue
		_junction_release(state,body,streets)
		body.set_meta("junction_guard",false)
		body.remove_meta("traffic_yield_until")
		body.global_transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p)
		body.velocity = Vector3.ZERO
		state.speed = 0.0
		state.stalled = 0.0
		state.traffic_stall = 0.0
		state.traffic_last = p
		state.backed_up = 0.0
		state.retreat_remaining = 0.0
		state.cooperative_path = []
		state.cooperative_hold = 0
		state.cooperative_rejoin = false
		state.watch_anchor = p
		state.watch_still = 0.0
		state.watch_offroad = 0.0
		state.watch_safe = {"p":p,"d":d,"index":int(option.index)}
		print("Tráfico: recuperación ",body.name," · ", "fuera de calzada" if offroad else "bloqueo prolongado")
		return int(option.index)
	if now>=int(state.get("watch_report",0)):
		state.watch_report = now+30000
		print("Tráfico: ",body.name," sin espacio seguro de recuperación; reintentando.")
	return -1

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
	query.collision_mask = 1|4|8|32
	query.exclude = [body.get_rid()]
	var space := body.get_world_3d().direct_space_state
	if not space.intersect_shape(query,1).is_empty():
		# An inflated lookahead can graze a curbside object. Test the
		# real collision body before declaring that it has zero clearance.
		var collision := KinematicCollision3D.new()
		if body.test_move(body.global_transform,d*reach,collision,.001):
			return clampf(collision.get_travel().dot(d),0.0,reach)
		return reach
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
					if not streets.intersection_clear_for_stop(p,length,width) or not _on_road(streets,p,face,width,length) or not _segment_clear(body,previous,p,face,shape):
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
static func early_lane_pass(body: CharacterBody3D,_streets: Streets,blocked: bool,free: float) -> bool:
	# Avoid running a full planner for each normal moving traffic queue.
	return blocked and free<5.0 and body.velocity.length()<2.5

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
	q.collision_mask = 1|4|8|32
	q.exclude = [body.get_rid()]
	for hit in body.get_world_3d().direct_space_state.intersect_shape(q,64):
		if hit.collider is CharacterBody3D: return true
	return false

static func _junction_exit_clear(body: CharacterBody3D,samples: Array,first: int,last: int,width: float,length: float,height: float) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.10,height,length+.30)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1|4|8|32
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
			var progress_at: Vector3 = claim.get("progress_at",origin)
			if _flat_distance(origin,progress_at)>.45:
				claim.progress_at = origin
				claim.progress_ms = now
			if away<radius+.10: state.junction_entered = true
			if bool(state.get("junction_entered",false)) and away>radius+1.0:
				_junction_release(state,body,streets)
			elif not bool(state.get("junction_entered",false)) and now-int(claim.get("progress_ms",claim.since))>2600:
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
		# A departing vehicle on the outer safety ring must not queue
		# for the intersection it has just left.
		if first==0 and samples.size()>1:
			var next_sample: Vector3 = samples[1].p
			if _flat_distance(origin,center)>=float(junction.radius)+extent-.05 and _flat_distance(next_sample,center)>_flat_distance(origin,center)+.02:
				continue
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
			body.set_meta("junction_extent",extent)
			streets.intersection_claims[id] = {"owner":owner,"since":now,"junction":selected,"progress_at":origin,"progress_ms":now}
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
		if float(state.junction_signal_wait)<.8: return stop_distance
	# Don't lock the box far in advance; queue at the line first.
	if stop_distance>4.0: return stop_distance
	var existing: Dictionary = streets.intersection_claims.get(id,{})
	if not existing.is_empty():
		var other := instance_from_id(int(existing.owner)) as CharacterBody3D
		if not is_instance_valid(other):
			streets.intersection_claims.erase(id)
		elif int(existing.owner)!=owner:
			var other_extent := float(other.get_meta("junction_extent",4.5))
			if now-int(existing.get("progress_ms",existing.since))>2600 and _flat_distance(other.global_position,center)>float(selected.radius)+other_extent+.2:
				streets.intersection_claims.erase(id)
			else: return stop_distance
	# If the route ends inside the crossing, refuse entry. A legal exit
	# must fit the whole vehicle, plus a little space beyond its tail.
	if exit<0: return stop_distance
	if now<int(state.get("junction_retry",0)): return stop_distance
	state.junction_retry = now+250
	# A broad circular occupancy test counts cars on harmless adjacent
	# lanes as blockers. Check the actual swept travel corridor instead.
	var last := mini(samples.size()-1,exit+2)
	if not _junction_exit_clear(body,samples,entry,last,width,length,height): return stop_distance
	streets.intersection_claims[id] = {"owner":owner,"since":now,"junction":selected,"progress_at":origin,"progress_ms":now}
	body.set_meta("junction_extent",extent)
	state.junction_claim = id
	state.junction_entered = false
	return -1.0

static func junction_speed(speed: float,limit: float,brake: float) -> float:
	return speed if limit<0.0 else minf(speed,sqrt(2.0*brake*maxf(0.0,limit)))

static func junction_advance(advance: float,limit: float) -> float:
	return advance if limit<0.0 else minf(advance,maxf(0.0,limit))

# A vehicle at a sharp corner may have zero forward clearance with
# its old heading. Let it turn in place only if its real body fits.
static func align_if_clear(body: CharacterBody3D,angle: float) -> void:
	if absf(angle_difference(body.global_rotation.y,angle))<.005: return
	var old := body.global_rotation.y
	body.global_rotation.y = angle
	if body.test_move(body.global_transform,Vector3.ZERO,null,.001,true):
		body.global_rotation.y = old
