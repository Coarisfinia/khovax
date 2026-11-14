class_name DrinkButton
extends ActionButton
## The tonics' touch button (#2313): drinks one (`drink_tonic`), as the G key and a controller's
## left trigger do. With one brew held it drinks it at once; with several it starts picking one
## (LocalInput's drink_pick), which the list beside it shows (BrewPickList). It shows the vial's
## icon and how many tonics and draughts the player holds, 0 when none, or while picking how many
## of the picked one (#429). After a drink it shows the 10 s wait as a cooldown circle with its
## seconds left, and it is drawn faded while the player holds none or waits.

## Whose tonics and draughts are counted: this machine's player's profile.
@export var holder: ProfileHolder


func _init() -> void:
	icon = ResourcePacks.texture("icon_round_bottom_flask")
	action = &"drink_tonic"
	column_index = 4


func corner_text() -> String:
	if _wait() > 0:
		return str(DrinkTie.wait_seconds(state(), slot()))
	var picked: String = _picked()
	if not picked.is_empty() and holder != null and holder.keeper != null:
		return str(holder.keeper.profile.materials.get(picked, 0))
	return str(DrinkTie.held_count(holder))


func cooldown_share() -> float:
	return float(_wait()) / float(DrinkingFeature.WAIT_TICKS)


func usable() -> bool:
	return player() != null and _wait() == 0 and DrinkTie.held_count(holder) > 0


## The ticks this machine's player still waits before their next drink, 0 for none.
func _wait() -> int:
	var game: GameState = state()
	if game == null or game.player(slot()) == null:
		return 0
	return DrinkingFeature.wait_of(game, slot())


## The brew being picked to drink, or "" while not picking.
func _picked() -> String:
	if driver == null or not driver.input is LocalInput:
		return ""
	return (driver.input as LocalInput).drink_pick.picked
