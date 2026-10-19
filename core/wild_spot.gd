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


## What a legend marks a wild monster with beyond its species and wounding: the event it emits when
## it faints, and the quest target it is.
static func mark(emitted: String, quest_target: String) -> WildSpot:
	return WildSpot.new("", false, emitted, quest_target)


## The quest target the wild monster with entity id `entity_id` is in `marks` (WildMonsterFeature's,
## by entity id, #625), or "" when it's none.
static func target_in(marks: Dictionary[int, WildSpot], entity_id: int) -> String:
	var marked: WildSpot = marks.get(entity_id)
	return marked.target if marked != null else ""
