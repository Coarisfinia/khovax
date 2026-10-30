class_name WaystoneNoticeTie
extends Node
## Tells this machine's player when they activated a waystone (#1890): a short notice
## (NoticeScreen) says it's now where they come back to when they fall, so they know it without
## telling the glow apart by colour (#68).

@export var driver: Session
## This machine's player, whose slot the event must name.
@export var input: LocalInput
## Where the notice shows.
@export var notice: NoticeScreen


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	for event: RefCounted in events:
		var activated: WaystoneActivated = event as WaystoneActivated
		if activated != null and input != null and activated.slot == input.slot:
			notice.notify(title(), line())


## The notice's title and line.
static func title() -> String:
	return TranslationServer.tr("Waystone activated")


static func line() -> String:
	return TranslationServer.tr("You'll return here when you fall.")
