class_name DialogSaveHold
extends WorldSaveHold
## The world isn't saved while any player's dialog is open (#891, #913): WorldKeeper waits, and
## saves a moment after the last one closes.


## Whether any instance of `world` has a player's dialog open (DialogFeature).
func holds(world: World) -> bool:
	if world == null:
		return false
	for state: GameState in world.instances.values():
		var dialogs: DialogFeature = state.feature(DialogFeature.ID) as DialogFeature
		if dialogs != null and dialogs.any_open():
			return true
	return false
