class_name WaystoneNoticeTie
extends Node
## Tells this machine's player when they activated a waystone (#1890): a short notice
## (NoticeScreen) says it's now where they come back to when they fall, so they know it without
## telling the glow apart by colour (#68).

## Where the notice shows.
@export var notice: NoticeScreen
## This machine's player, whose slot the event must name.
@export var input: LocalInput
@export var driver: Session


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_say_activated)


## Shows the notice for this machine's player's WaystoneActivated among a tick's `events`.
func _say_activated(_tick: int, events: Array[RefCounted]) -> void:
	if input == null:
		return
	for event: RefCounted in events:
		if event is WaystoneActivated and (event as WaystoneActivated).slot == input.slot:
			notice.notify(title(), line())


## The notice's title and line.
static func title() -> String:
	return TranslationServer.tr("Waystone activated")


static func line() -> String:
	return TranslationServer.tr("You'll return here when you fall.")
