class_name GuideNoticeTie
extends Node
## Tells this machine's player when a guide went ahead without them (#1589, #1553): the rules raise
## GuideWentAhead in the instance they left (#1588), so they're elsewhere by then, and a short
## notice (NoticeScreen) shows the guide's name and their line for it, which needs no answer and
## never holds them where they arrived. The line is the guide's own, in their content data
## (Person.went_ahead); one without a line says the plain one here.

## What a guide with no line of their own says.
const PLAIN_LINE: String = "I'll go on ahead and open the way."

## The session, whose ticks carry the events of the instance the player just left too.
@export var driver: Session
## This machine's player, whose slot the event must name.
@export var input: LocalInput
## Where the notice shows.
@export var notice: NoticeScreen


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for event: RefCounted in events:
		var went: GuideWentAhead = event as GuideWentAhead
		if went != null and input != null and went.slot == input.slot:
			notice.notify(TextTags.tag(TextTags.PERSON, went.npc), line_of(went.npc))


## What the guide `npc_id` says when they go ahead: their own line, or the plain one.
static func line_of(npc_id: String) -> String:
	var person: Person = PeopleContent.cached().people.get(npc_id)
	if person == null or person.went_ahead.is_empty():
		return PLAIN_LINE
	return person.went_ahead
