class_name ReviveButton
extends ActionButton
## The revive item's touch button (#656): uses one (`revive_monster`), as the V key and a
## controller's d-pad down do, bringing back the first fainted monster this machine's player
## carries. It shows the item's icon and how many the player holds, 0 when none (#429), and is
## drawn faded while they hold none or nothing they carry has fainted.

@export var driver: Session
## Whose revive items are counted: this machine's player's profile.
@export var holder: ProfileHolder


func _init() -> void:
	icon = preload("res://assets/game-icons/herbs-bundle.svg")
	action = &"revive_monster"
	column_index = 3


func corner_text() -> String:
	return str(ReviveItem.held(holder))


func usable() -> bool:
	if ReviveItem.held(holder) == 0 or driver == null or driver.state == null:
		return false
	var slot: int = driver.input.slot if driver.input != null else 0
	if driver.state.player(slot) == null:
		return false
	return not ReviveItemFeature.revivable(driver.state, slot).is_empty()
