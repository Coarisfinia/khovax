class_name TerritoryFeature
extends Feature
## Territory changing hands (#638): a player who finishes a territory quest sends the territory it
## hands over in their command, as a request (OutboxEntry.TERRITORY) whose data is its code
## (Territory.code), and this raises that the instance is handed to the faction
## (Territory.handed_over), which the world carries out once every instance has stepped. A code no
## territory quest has is ignored. A hand-over comes from the player's
## profile's outbox (#771) with its request's id: the ids it applied are kept in its entry in the
## player's world store (OutboxReceipts), so one sent again isn't handed over twice.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "territory"

## Every territory a quest hands over, by its code: the instance's name and the faction's id (the
## quests' content data).
var handovers: Dictionary[int, PackedStringArray] = {}


func _init(by_code: Dictionary[int, PackedStringArray] = {}) -> void:
	handovers = by_code


func id() -> String:
	return ID


## Hands over the territory of every player's command, in slot order, that names one, unless its
## request was applied before. A request naming a territory no quest of this build hands over is
## neither applied nor acknowledged, so the profile keeps sending it, as it keeps the progress of a
## quest missing from a build's data until it's back.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var handing: bool = command != null and command.request_kind == OutboxEntry.TERRITORY
		if not handing or state.player(slot) == null or not handovers.has(command.request_data):
			continue
		if not OutboxReceipts.take(state, slot, id(), command.request):
			continue
		var handed: PackedStringArray = handovers[command.request_data]
		state.events.append(Territory.handed_over(handed[0], handed[1]))
