class_name CompanionStruck
extends RefCounted
## Event: a companion's auto attack hit a wild monster this tick (#221), for `damage` HP; a hit
## never takes it below 1 HP. `strong` says, for each of the monster's types on the type chart,
## whether the strike was strong against it (weak otherwise); it's empty while the chart is off
## (TypeEffectivenessFeature.strong_against, #701), and only the damage numbers read it (#764).

var companion_id: int
var monster_id: int
var damage: int
var strong: Array[bool]


func _init(by_id: int, on_id: int, amount: int, strong_types: Array[bool] = []) -> void:
	companion_id = by_id
	monster_id = on_id
	damage = amount
	strong = strong_types
