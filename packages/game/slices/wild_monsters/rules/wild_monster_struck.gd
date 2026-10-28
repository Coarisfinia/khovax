class_name WildMonsterStruck
extends RefCounted
## Event: a wild monster's attack hit something next to it this tick (#422): a companion, a player
## or the prey it hunts (#1204, HuntFeature; `target_id`, their entity id), or a tile of the allies'
## trail (`target_id` 0). `tile`
## is where the hit landed, and `damage` how much it dealt (0 on an invincible player, #1147). On a
## companion, `strong` says for each of its types on the type chart whether the strike was strong
## against it (weak otherwise); it's empty otherwise and while the chart is off
## (TypeEffectivenessFeature.strong_against, #701), and only the damage numbers read it (#764).
## `dodged` says the hit missed a companion that dodged it (#1499): it deals nothing, and the damage
## numbers show it as a miss (#1564).

var monster_id: int
var target_id: int
var tile: Vector2i
var damage: int
var strong: Array[bool]
var dodged: bool = false


func _init(
	by_id: int,
	on_id: int,
	on_tile: Vector2i,
	amount: int,
	strong_types: Array[bool] = [],
) -> void:
	monster_id = by_id
	target_id = on_id
	tile = on_tile
	damage = amount
	strong = strong_types
