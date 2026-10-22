class_name SpecialStruck
extends RefCounted
## Event: a companion's special attack hit a wild monster this tick (#410), for `damage` HP. It's
## lethal: `felled` says whether it took the monster to 0 HP, so that it fainted. `strong` says,
## for each of the monster's types on the type chart, whether the strike was strong against it (weak
## otherwise); it's empty while the chart is off (TypeEffectivenessFeature.strong_against, #701).

var companion_id: int
var monster_id: int
var damage: int
var felled: bool
var strong: Array[bool]


func _init(
	by_id: int,
	on_id: int,
	amount: int,
	fainted: bool,
	strong_types: Array[bool] = [],
) -> void:
	companion_id = by_id
	monster_id = on_id
	damage = amount
	felled = fainted
	strong = strong_types
