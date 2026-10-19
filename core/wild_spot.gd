class_name WildSpot
extends RefCounted
## What a region piece's legend says about one of its wild monster spots, beyond where it is: the
## species it names (#133; "" to roll one from the blueprint's list), whether its monster starts
## wounded (#389), and the event its monster emits when it faints (#541, EventEmitted; "" for none).

var species: String = ""
var wounded: bool = false
var emits: String = ""


func _init(named: String = "", is_wounded: bool = false, emitted: String = "") -> void:
	species = named
	wounded = is_wounded
	emits = emitted
