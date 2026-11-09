class_name CompanionSwapFeature
extends Feature
## Manual swaps (#55): a player in this instance makes another of the monsters they carry their
## companion, any time, by its place in their carried order (Command.swap). The feature only checks
## the choice and raises CompanionChosen; the world makes the choice theirs in every instance, and
## CompanionFeature then sends the old companion off and lets the new one join them. Choosing the
## companion they already have, a place they carry nothing in, or a monster that fainted (#597) and
## hasn't been revived (#655) does nothing.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "companion_swaps"


func id() -> String:
	return ID


## After the companions, which it swaps: a player's own swap comes last in the tick.
func requires() -> Array[String]:
	var needed: Array[String] = [CompanionFeature.ID]
	return needed


## Lets every player here swap, in slot order.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.swap != Command.NO_SWAP and state.player(slot) != null:
			_swap(state, slot, command.swap - 1)


## Raises CompanionChosen when the player in `slot` carries a monster at `place` other than their
## companion, and it hasn't fainted.
static func _swap(state: GameState, slot: int, place: int) -> void:
	var party: PackedStringArray = CompanionParty.carried(state, slot)
	if place >= party.size() or party[place] == CompanionParty.companion(state, slot):
		return
	if not CompanionParty.has_fainted(state, slot, party[place]):
		CompanionParty.choose(state, slot, place)
		state.events.append(CompanionChosen.new(slot, place))
