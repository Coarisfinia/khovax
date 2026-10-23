class_name PlaceTie
extends Node
## Ties the places this machine's player enters to the codex (#1175): entering an instance a realm
## draws meets its name and its realm's, so the codex book lists both, as seeing a species lists it
## in the bestiary. An instance no realm draws (the test-only playground) meets nothing. The keeper
## keeps it in their profile; this only watches the session.

## The session, whose ticks say where the player is.
@export var driver: Session
## Where the names met are kept.
@export var keeper: CodexKeeper

## The instance the player was in at the last tick, so a name is met once per arrival.
var _here: String = ""


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _on_ticked(_tick: int, _events: Array[RefCounted]) -> void:
	var where: String = driver.local_instance_name()
	if where == _here:
		return
	_here = where
	var realm: Realm = Realms.holding(where)
	if realm != null:
		keeper.meet(TextTags.REALM, realm.id)
		keeper.meet(TextTags.PLACE, where)
