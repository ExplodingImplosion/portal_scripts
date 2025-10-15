@tool
extends AnimationPlayer

@export_tool_button("Export Animations") var export_animations := func export_animations() -> void:
	#var animation: Animation
	var anims_string: String
	for animation_name in get_animation_list():
		#animation = get_animation(animation_name)
		anims_string += export_animation(get_animation(animation_name),animation_name)
	
	DisplayServer.clipboard_set(anims_string)
	print("Successfully copied exported animations to clipboard!")
	
	# Was gonna iter thru libraries but fuck it nvm
	#var library: AnimationLibrary
	#for library_name in get_animation_library_list():
		#library = get_animation_list()
		#for animation in get_animation_library(library):
			#pass

class KeyFrame:
	var relative_pos: Vector3
	var relative_rot: Vector3
	var relative_time: float
	
	func _init(current_time: float, prev_time: float = 0.) -> void:
		relative_time = current_time - prev_time
		
	func add_pos(current_position: Vector3, prev_position := Vector3.ZERO):
		relative_pos = current_position - prev_position
	
	func add_rot(current_rotation: Vector3, prev_rotation := Vector3.ZERO):
		relative_rot = current_rotation - prev_rotation

class ExportableAnimation:
	var positions: PackedVector3Array
	var pos_times: PackedFloat64Array # No idea if using doubles actually does
	var rotations: PackedVector3Array # anything for BF6 but im just doin it in
	var rot_times: PackedFloat64Array # case lmao
	var anim_name: String
	var obj_name: String
	var num_p_keys: int
	var num_r_keys: int
	var keyframes: Array[KeyFrame]
	
	func _init(animation_name: StringName, node: Node) -> void:
		obj_name = node.name.to_snake_case()
		# lmao le jank (im using this to separate animation names from node names)
		anim_name = animation_name.to_camel_case() + "___" + obj_name.to_camel_case()
		print("Exporting animation %s..."%anim_name)
	
	# Bad name cuz its a track
	func add_pos_anim(anim: Animation, track_idx: int) -> void:
		num_p_keys = add_anim(positions,pos_times,anim,track_idx)
	
	# Bad name cuz its a track
	func add_rot_anim(anim: Animation, track_idx: int) -> void:
		num_r_keys = add_anim(rotations,rot_times,anim,track_idx)
	
	# Bad name cuz its a track
	func add_anim(values: PackedVector3Array, times: PackedFloat64Array, anim: Animation, track_idx: int) -> int:
		var num_keys: int = 0
		values.clear()
		times.clear()
		var value: Variant
		for key_idx in anim.track_get_key_count(track_idx):
			value = anim.track_get_key_value(track_idx,key_idx)
			if value is Quaternion:
				values.append((value as Quaternion).get_axis())
			elif value is Vector3:
				values.append(value as Vector3)
			else:
				push_error("Invalid data type %s (%s) on track %s."%[
					type_string(typeof(value)),value,track_idx
				])
				continue
			times.append(anim.track_get_key_time(track_idx,key_idx))
			num_keys += 1
		return num_keys
	
	func combine_tracks() -> void:
		var keys: Dictionary[float,KeyFrame] = {}
		var key: KeyFrame
		var time: float
		
		# For grabbing exportable anims i reduced code duplication by some inline lambda bullshit
		# and arbitratily decided not to here. because, reasons i guess
		
		for i in num_p_keys:
			time = pos_times[i]
			if keys.has(time):
				key = keys[time]
			else:
				key = KeyFrame.new(time,0. if i == 0 else pos_times[i-1])
				keys[time] = key
			
			if i == 0:
				key.add_pos(positions[i])
			else:
				key.add_pos(positions[i],positions[i-1])
		
		for i in num_r_keys:
			time = rot_times[i]
			if keys.has(time):
				key = keys[time]
			else:
				key = KeyFrame.new(time,0. if i == 0 else rot_times[i-1])
				keys[time] = key
			
			if i == 0:
				key.add_rot(rotations[i])
			else:
				key.add_rot(rotations[i],rotations[i-1])
		
		keys.sort()
		
		keyframes = keys.values()
	
	func export() -> String:
		
		# Side effect but its here to make sure things behave as expected
		combine_tracks()
		
		var anim_string := ""
		var frame: int = 0
		var first_time: float = 0.
		for key in keyframes:
			if (key.relative_time > 0.) and (key.relative_time < 1./60.):
				push_error("Warning! Creating keyframes at a lower resolution than 1/60th of a second will always be rounded up to 1/60th due to tickrate stuff. Animation %s has a keyframe with a relative time of %s."%[anim_name,key.relative_time])
			if frame == 0:
				if key.relative_time != 0.:
					anim_string += "\t%s\n"%WAIT_STRING%key.relative_time
				anim_string += "\t%s\n"%get_move_over_time_func(key)
				first_time = key.relative_time
			else:
				# Prevents waiting on a keyframe which is supposed to instantly
				# move an object at the start from delaying execution
				if frame > 1 or first_time != 0:
					anim_string += "\t%s\n"%WAIT_STRING%key.relative_time
				anim_string += "\t%s\n"%get_move_over_time_func(key)
			frame += 1
		
		return DECLARATION_STRING%[anim_name,obj_name,anim_string]
	
	const DECLARATION_STRING = "export async function %s(%s: mod.Object) {\n%s}"
	const MOVE_OVER_TIME_STRING = "mod.MoveObjectOverTime(%s, mod.CreateVector(%s, %s, %s), mod.CreateVector(%s, %s, %s), %s, %s, %s);"
	const WAIT_STRING = "await mod.Wait(%s);"
	const MOD_VECTOR_STRING = "mod.CreateVector(%s, %s, %s)"
	
	# TODO impl should_loop and should_reverse cuz these are actually things in godot and could
	# probably be added in a relatively 1:1 adjacent way
	func get_move_over_time_func(key: KeyFrame, should_loop := false, should_reverse := false) -> String:
		return "mod.MoveObjectOverTime(%s,%s,%s,%s,%s,%s)"%[
			obj_name,get_mod_vector(key.relative_pos),get_mod_vector(key.relative_rot),key.relative_time,should_loop,should_reverse
		]
	
	func get_mod_vector(vec: Vector3) -> String:
		return MOD_VECTOR_STRING%[vec.x,vec.y,vec.z]

func export_animation(animation: Animation, anim_name: StringName) -> String:
	
	var node_anims: Dictionary[Node,ExportableAnimation]
	var get_anim := func get_anim(node: Node) -> ExportableAnimation:
		if node_anims.has(node):
			return node_anims[node]
		else:
			var anim := ExportableAnimation.new(anim_name,node)
			node_anims[node] = anim
			return anim
	
	for track_idx in animation.get_track_count():
	
		var path: NodePath = animation.track_get_path(track_idx)
		# At one point this didnt work and it needed to be
		# get_tree().edited_scene_root.get_node(path) instead
		var node: Node = get_node(path)
		if not node is Node3D:
			push_error("Invalid animation track export on non-3D node %s (%s) in animation %s on track %s."%[
				node.name,node,anim_name,track_idx
			])
	
		match animation.track_get_type(track_idx):
	
			Animation.TYPE_POSITION_3D:
				var exp_anim := get_anim.call(node) as ExportableAnimation
				if !exp_anim.positions.is_empty():
					push_error("Node %s (%s) has a redundant position animation on track %s in animation '%s'"%[
						node.name,node,track_idx,anim_name
					])
				exp_anim.add_pos_anim(animation,track_idx)
	
			Animation.TYPE_ROTATION_3D:
				var exp_anim := get_anim.call(node) as ExportableAnimation
				if !exp_anim.rotations.is_empty():
					push_error("Node %s (%s) has a redundant rotation animation on track %s in animation '%s'"%[
						node.name,node,track_idx,anim_name
					])
				exp_anim.add_rot_anim(animation,track_idx)
	
			_:
				push_error("Found invalid animation track type %s in animation '%s' %s %s."%[
					animation.track_get_type(track_idx),anim_name,animation.resource_name,animation.resource_path
				])
	
	var script_string: String = ""
	for anim: ExportableAnimation in node_anims.values():
		script_string += anim.export()+"\n\n\n"
		print("Successfully exported animation '%s'."%anim.anim_name)
	# add combined animation lmao
	return script_string
