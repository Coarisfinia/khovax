class_name ReviveButton
extends ActionButton
## The revive item's touch button (#656): uses one (`revive_monster`), as the V key and a
## controller's d-pad down do, on the fainted monster this machine's player carries, or, with
## several fainted, starts picking one (#780, LocalInput), which a tap on its roster square ends. It
## shows the item's icon and how many the player holds, 0 when none (#429), and is
## drawn faded while they hold none or nothing they carry has fainted.

## Whose revive items are counted: this machine's player's profile.
@export var holder: ProfileHolder


func _init() -> void:
	icon = preload("res://assets/game-icons/herbs-bundle.svg")
	action = &"revive_monster"
	column_index = 3


func corner_text() -> String:
	return str(ReviveItem.held(holder))


func usable() -> bool:
	if ReviveItem.held(holder) == 0 or player() == null:
		return false
	return not ReviveItemFeature.fainted(state(), slot()).is_empty()
