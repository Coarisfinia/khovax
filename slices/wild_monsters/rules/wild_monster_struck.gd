class_name WildMonsterStruck
extends RefCounted
## Event: a wild monster's attack hit something next to it this tick (#422): a companion or a
## player (`target_id`, their entity id), or a tile of the allies' trail (`target_id` 0). `tile`
## is where the hit landed, and `damage` how hard it was.

var monster_id: int
var target_id: int
var tile: Vector2i
var damage: int


func _init(by_id: int, on_id: int, on_tile: Vector2i, amount: int) -> void:
	monster_id = by_id
	target_id = on_id
	tile = on_tile
	damage = amount
