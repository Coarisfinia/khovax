class_name WaystoneNoticeTie
extends Node
## Tells this machine's player when they activated a waystone (#1890): a short notice
## (NoticeScreen) says it's now where they come back to when they fall, so they know it without
## telling the glow apart by colour (#68). While the host has fainted beasts revived on waystones
## (#1891), it also says when they came back.

## Where the notice shows.
@export var notice: NoticeScreen
## This machine's player, whose slot the event must name.
@export var input: LocalInput
@export var driver: Session


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_say_activated)


## Shows the notice for this machine's player's WaystoneActivated and WaystoneRevived among a
## tick's `events`: one notice, saying both when both came in the tick.
func _say_activated(_tick: int, events: Array[RefCounted]) -> void:
	if input == null:
		return
	var activated: bool = false
	var revived: bool = false
	for event: RefCounted in events:
		if event is WaystoneActivated and (event as WaystoneActivated).slot == input.slot:
			activated = true
		if event is WaystoneRevived and (event as WaystoneRevived).slot == input.slot:
			revived = true
	if activated or revived:
		notice.notify(title() if activated else revived_title(), lines(activated, revived))


## The notice's line: what activating says, what reviving says, or both.
static func lines(activated: bool, revived: bool) -> String:
	var said: PackedStringArray = []
	if activated:
		var _added: bool = said.append(line())
	if revived:
		var _added: bool = said.append(revived_line())
	return "\n".join(said)


## The notice's title and line.
static func title() -> String:
	return TranslationServer.tr("Waystone activated")


static func line() -> String:
	return TranslationServer.tr("You'll return here when you fall.")


## The title and line when only the fainted beasts came back (#1891).
static func revived_title() -> String:
	return TranslationServer.tr("Waystone")


static func revived_line() -> String:
	return TranslationServer.tr("Your fainted beasts are back on their feet.")
