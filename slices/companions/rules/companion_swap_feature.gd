class_name CompanionSwapFeature
extends Feature
## Manual swaps (#55): a player in this instance makes another of the monsters they carry their
## companion, any time, by its place in their carried order (Command.swap). The feature only checks
## the choice and raises CompanionChosen; the world makes the choice theirs in every instance, and
## CompanionFeature then sends the old companion off and lets the new one join them. Choosing the
## companion they already have, or a place they carry nothing in, does nothing.


func id() -> int:
	return Features.COMPANION_SWAPS


## Lets every player here swap, in slot order.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.swap != Command.NO_SWAP and state.player(slot) != null:
			_swap(state, slot, command.swap - 1)


## Raises CompanionChosen when the player in `slot` carries a monster at `place` other than their
## companion.
static func _swap(state: GameState, slot: int, place: int) -> void:
	var party: PackedStringArray = state.carried[slot]
	if place < party.size() and party[place] != state.companions[slot]:
		state.events.append(CompanionChosen.new(slot, place))
