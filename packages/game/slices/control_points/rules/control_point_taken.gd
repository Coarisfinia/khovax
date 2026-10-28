class_name ControlPointTaken
extends RefCounted
## Event: a player closed a ring around a control point and placed their totem on it (#644), so
## their side holds that point now and the totem wards it, the one totem it takes.

## The control point's tile.
var point: Vector2i
## The side that holds it now (ControlPointSides).
var side: int
## The entity id of the player who placed the totem.
var player_id: int


func _init(taken: Vector2i, taking_side: int, placed_by: int) -> void:
	point = taken
	side = taking_side
	player_id = placed_by
