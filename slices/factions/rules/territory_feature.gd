class_name TerritoryFeature
extends Feature
## Territory changing hands (#638): a player who finishes a territory quest sends the territory it
## hands over in their command, as its code (Territory.code), and this raises that the instance is
## handed to the faction (Territory.handed_over), which the world carries out once every instance
## has stepped. A code no territory quest has is ignored. It keeps no state of its own.

## Every territory a quest hands over, by its code: the instance's name and the faction's id (the
## quests' content data).
var handovers: Dictionary[int, PackedStringArray] = {}


func _init(by_code: Dictionary[int, PackedStringArray] = {}) -> void:
	handovers = by_code


func id() -> int:
	return Features.TERRITORY


## Hands over the territory of every player's command, in slot order, that names one.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		if command == null or state.player(slot) == null or not handovers.has(command.hand_over):
			continue
		var handed: PackedStringArray = handovers[command.hand_over]
		state.events.append(Territory.handed_over(handed[0], handed[1]))
