class_name QuestTie
extends Node
## Ties this machine's player's quests to the running session (#817): every event quests count is
## turned into its facts for that player (QuestFacts) and counted on their quests at once, each in
## the instance it happened in (#769), and so are the world's events that had already changed it as
## the session starts (#756). The keeper keeps the quests and saves them with the profile; this
## only listens.

## Where the events come from.
@export var bus: EventBus
## Whose events are this machine's player's.
@export var input: LocalInput
## The quests they advance.
@export var quests: QuestKeeper


func _ready() -> void:
	for event_class: Script in QuestFacts.events():
		bus.subscribe(event_class, _on_event)


func _on_event(event: RefCounted) -> void:
	var facts: Array[QuestFact] = QuestFacts.of(event, input.slot, bus.instance_of(event))
	if not facts.is_empty():
		quests.count(facts)


## Counts every event that had already changed the world as the session starts in it (#756), from
## its flags: the profile travels between worlds, so one that wasn't there when an event was raised
## (a guest, or this player back from another world) meets the world as it is. Like a live one, each
## counts only toward the step a quest waits on now, never past a step the player missed, and starts
## a side quest waiting on it (owner, #756); a quest already started or done isn't started again.
func catch_up(world_flags: Array[String]) -> void:
	var facts: Array[QuestFact] = QuestFacts.of_world_flags(world_flags)
	if not facts.is_empty():
		quests.count(facts)
