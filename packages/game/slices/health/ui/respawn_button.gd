class_name RespawnButton
extends ActionButton
## The touch button that sends this machine's knocked-down player back to the world's spawn now
## (#495), pressing `respawn` as the X key and a controller's top face button do. It shows a door
## and only while the player is knocked down (#479): there's nothing to choose otherwise.


func _init() -> void:
	icon = preload("res://assets/game-icons/exit-door.svg")
	action = &"respawn"
	column_index = 2


func lay_out_in(screen: Vector2) -> void:
	super(screen)
	visible = visible and is_down()


## Whether this machine's player is knocked down.
func is_down() -> bool:
	var down: Entity = player()
	var knockdown: KnockdownFeature = feature(KnockdownFeature.ID) as KnockdownFeature
	return down != null and knockdown != null and knockdown.is_down(down.id)
