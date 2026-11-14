class_name WildMonsterEscaped
extends RefCounted
## Event: a wild monster its region marks to escape (#2411, EscapeFeature) reached its line this
## tick and left the instance through a portal, instead of fainting or being dominated. Its entity
## is already gone, and nobody dominated it; the fight still counts, through the event its legend
## names it emitting (EventEmitted), as when it faints.

var monster_id: int
## Where it stood when it left.
var tile: Vector2i
## Its species id and its short id (ShortId, #700).
var species: String
var short_id: String
## The quest target it was (#625), as its region's legend names it, or "".
var target: String = ""


func _init(escaped_id: int, from: Vector2i, species_id: String, short: String) -> void:
	monster_id = escaped_id
	tile = from
	species = species_id
	short_id = short
