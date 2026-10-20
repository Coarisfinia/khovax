class_name WildSpot
extends RefCounted
## What a region piece's legend says about one of its wild monster spots, beyond where it is: the
## species it names (#133; "" to roll one from the blueprint's list), whether its monster starts
## wounded (#389), the event its monster emits when it faints (#541, EventEmitted; "" for none), and
## the quest target it is (#625): a content id a quest's step names to ask for this one monster, ""
## for none.

var species: String = ""
var wounded: bool = false
var emits: String = ""
var target: String = ""


func _init(
	named: String = "",
	is_wounded: bool = false,
	emitted: String = "",
	quest_target: String = "",
) -> void:
	species = named
	wounded = is_wounded
	emits = emitted
	target = quest_target
