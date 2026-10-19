class_name SpikesStruck
extends RefCounted
## Event: the spikes on a ring hurt a wild monster pushing on it this tick (#692), for `damage` HP;
## like an auto attack, they never take it below 1 HP.

var monster_id: int
## The entity id of the ring's dominator, whose spikes they are.
var dominator_id: int
var damage: int


func _init(on_id: int, by_id: int, amount: int) -> void:
	monster_id = on_id
	dominator_id = by_id
	damage = amount
