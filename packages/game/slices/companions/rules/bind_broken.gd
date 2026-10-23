class_name BindBroken
extends RefCounted
## Event: a companion's held special stopped binding the wild monster `monster_id` before its hold
## ran its course (#1167), without its strike: the companion was struck, can no longer strike it, or
## left. Its companion's look lets go of the hold then.

var companion_id: int
var monster_id: int


func _init(by_id: int, on_id: int) -> void:
	companion_id = by_id
	monster_id = on_id
