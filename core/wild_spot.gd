class_name WildSpot
extends RefCounted
## What a region piece's legend says about one of its wild monster spots, beyond where it is: the
## species it names (#133; "" to roll one from the blueprint's list) and whether its monster starts
## wounded (#389).

var species: String = ""
var wounded: bool = false


func _init(named: String = "", is_wounded: bool = false) -> void:
	species = named
	wounded = is_wounded
