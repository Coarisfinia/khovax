class_name WorldChanged
extends RefCounted
## Event: a world-changing moment (#499). A named event (EventEmitted, #541), such as a story beat,
## set its world flag for the first time this tick, so the blueprints' variants that flag chooses
## take over. The World raises it among its own events, once per flag: the same event raised again
## later changes nothing and raises nothing.

## The name of the event that changed the world.
var event_name: String
## The world flag it set: WorldFlags.EVENT_FLAG + `event_name`.
var flag: String


func _init(named: String, set_flag: String) -> void:
	event_name = named
	flag = set_flag
