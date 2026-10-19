class_name CompanionSwapFeature
extends Feature
## Manual swaps (#55): a player in this instance makes another of the monsters they carry their
## companion, any time, by its place in their carried order (Command.swap). The feature only checks
## the choice and raises CompanionChosen; the world makes the choice theirs in every instance, and
## CompanionFeature then sends the old companion off and lets the new one join them. Choosing the
## companion they already have, a place they carry nothing in, or a monster that fainted here
## (#597) does nothing.


func id() -> int:
	return Features.COMPANION_SWAPS


## After the companions, whose fainted monsters it reads.
func requires() -> Array[int]:
	var needed: Array[int] = [Features.COMPANIONS]
	return needed


## Lets every player here swap, in slot order.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command != null and command.swap != Command.NO_SWAP and state.player(slot) != null:
			_swap(state, slot, command.swap - 1)


## Raises CompanionChosen when the player in `slot` carries a monster at `place` other than their
## companion, and it hasn't fainted here.
static func _swap(state: GameState, slot: int, place: int) -> void:
	var party: PackedStringArray = state.carried[slot]
	if place >= party.size() or party[place] == state.companions[slot]:
		return
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	if not companions.has_fainted(slot, party[place]):
		state.events.append(CompanionChosen.new(slot, place))
