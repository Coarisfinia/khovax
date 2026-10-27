class_name QuestEventFeature
extends Feature
## A quest's events reaching the world (#755): a step done or a choice taken that emits an event
## (#575) posts it to the player's profile's outbox (#771) as a request (OutboxEntry.QUEST_EVENT)
## whose data is the event's code (CommandCodes), and this raises it in the instance the player is
## in (EventEmitted), which sets its world flag in lockstep. The quests count it only once the world
## raises it back (WorldChanged, owner, #755), so every player's side quests start on it alike and
## nothing counts twice. A code no quest emits is neither applied nor acknowledged, as a hand-over
## of a territory no quest hands over (TerritoryFeature). Like every request, it's applied once
## (OutboxReceipts).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "quest_events"

## Every event a quest emits, by its code (the quests' content data).
var events: Dictionary[int, String] = {}


func _init(by_code: Dictionary[int, String] = {}) -> void:
	events = by_code


func id() -> String:
	return ID


## Raises the event of every player's command, in slot order, that names one a quest emits, unless
## its request was applied before.
func step(state: GameState, commands: Array[Command]) -> void:
	for slot: int in GameState.MAX_PLAYERS:
		var command: Command = Command.of(commands, slot)
		var emitting: bool = command != null and command.request_kind == OutboxEntry.QUEST_EVENT
		if not emitting or state.player(slot) == null or not events.has(command.request_data):
			continue
		if OutboxReceipts.take(state, slot, id(), command):
			state.events.append(_raised(events[command.request_data]))


## The event that raises the quest's event `event_name` in the instance.
static func _raised(event_name: String) -> EventEmitted:
	return EventEmitted.new(event_name)
