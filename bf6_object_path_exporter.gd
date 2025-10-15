@tool

extends Path3D

func get_follower() -> PathFollow3D:
	var f := PathFollow3D.new()
	add_child(f,false,Node.INTERNAL_MODE_FRONT)
	return f

var follower := get_follower()

@export_range(0.01,100.,0.001,"exp_edit","or_greater","hide_slider")
var speed: float = 1.
@export var object_name: String = "obj"
@export_range(1.,60.,1.) var resolution: float = 60.

@export_tool_button("Export Path") var export_path := func export_path() -> void:
	follower.progress_ratio = 1.
	var max_dist := follower.progress
	follower.progress_ratio = 0.
	var time_to_completion := max_dist / speed
	prints("max dist",max_dist)
	prints("time to complete",time_to_completion)
	var delta_time: float = 1. / resolution
	var num_ticks: int = roundi(time_to_completion / delta_time) # Convert to even ticks
	var dist_per_tick := speed / resolution
	assert(follower.position == Vector3.ZERO)
	var prev_pos: Vector3 = follower.global_position
	
	# These loops could be 1 loop but i wanna keep the logical steps separate
	# for clarity
	
	var obj_export_name := object_name.to_camel_case()
	
	var path_string: String = ""
	for i in num_ticks:
		follower.progress += dist_per_tick
		path_string += "\t%s\n\t%s\n"%[
			get_move_over_time_func(
				obj_export_name,
				follower.global_position-prev_pos,
				Vector3.ZERO, # TODO impl rotations
				delta_time,
				false,false # loop and reverse
			),
			WAIT_STRING%delta_time
		]
		prev_pos = follower.global_position
	
	
	DisplayServer.clipboard_set(DECLARATION_STRING%[
		name.to_camel_case(),obj_export_name,path_string
	])
	print("Copied path to clipboard!")

const DECLARATION_STRING = "export async function %s(%s: mod.Object) {\n%s}"
const MOVE_OVER_TIME_STRING = "mod.MoveObjectOverTime(%s, mod.CreateVector(%s, %s, %s), mod.CreateVector(%s, %s, %s), %s, %s, %s);"
const WAIT_STRING = "await mod.Wait(%s);"
const MOD_VECTOR_STRING = "mod.CreateVector(%s, %s, %s)"

func get_move_over_time_func(object_name: String, relative_pos: Vector3, relative_rot: Vector3, relative_time: float, should_loop := false, should_reverse := false) -> String:
	return "mod.MoveObjectOverTime(%s,%s,%s,%s,%s,%s)"%[
		object_name,get_mod_vector(relative_pos),get_mod_vector(relative_pos),relative_time,should_loop,should_reverse
	]

func get_mod_vector(vec: Vector3) -> String:
	return MOD_VECTOR_STRING%[vec.x,vec.y,vec.z]
