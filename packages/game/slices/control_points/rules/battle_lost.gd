class_name BattleLost
extends RefCounted
## Event: a side of a control point battle (#643) holds no control point any more, so it lost the
## battle. Raised once per battle.

## The side that lost (ControlPointFeature.ATTACKERS or DEFENDERS).
var side: int


func _init(losing_side: int) -> void:
	side = losing_side
