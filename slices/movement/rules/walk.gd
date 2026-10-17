class_name Walk
extends RefCounted
## MovementFeature's data for one walking entity: the move it is making, if any.

## The tile the current move started from.
var from: Vector2i = Vector2i.ZERO
## Ticks until the current move arrives; 0 when standing on the entity's tile.
var ticks_left: int = 0


func _init(start: Vector2i) -> void:
	from = start


func is_moving() -> bool:
	return ticks_left > 0
