class_name CompanionStruck
extends RefCounted
## Event: a companion's auto attack hit a wild monster this tick (#221), for `damage` HP; a hit
## never takes it below 1 HP.

var companion_id: int
var monster_id: int
var damage: int


func _init(by_id: int, on_id: int, amount: int) -> void:
	companion_id = by_id
	monster_id = on_id
	damage = amount
