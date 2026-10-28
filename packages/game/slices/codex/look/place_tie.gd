class_name PlaceTie
extends Node
## Ties the places this machine's player enters to the codex (#1175): entering an instance a realm
## draws meets its name and its realm's, so the codex book lists both, as seeing a species lists it
## in the bestiary; entering it while one of its variants loads a region of its own (#1448), such
## as a corrupted instance, meets that region's name too, and one that only changes it, like an
## opened passage (#1590), meets nothing more. An instance no realm draws (the test-only
## playground) meets nothing. The keeper keeps it in their profile; this only watches the session.

## The session, whose ticks say where the player is.
@export var driver: Session
## Where the names met are kept.
@export var keeper: CodexKeeper

## The instance the player was in at the last tick and the variant it was loaded from, so a name is
## met once per arrival.
var _here: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _on_ticked(_tick: int, _events: Array[RefCounted]) -> void:
	var where: String = driver.local_instance_name()
	var variant: String = WorldFlags.variant_of(driver.world, where) if driver.world != null else ""
	var here: PackedStringArray = PackedStringArray([where, variant])
	if here == _here:
		return
	_here = here
	var realm: Realm = Realms.holding(where)
	if realm != null:
		keeper.meet(TextTags.REALM, realm.id)
		keeper.meet(TextTags.PLACE, where)
		# A variant that only changes the instance (#1590) has no name or page of its own.
		if InstanceBlueprints.variant_owner(variant) == where:
			keeper.meet(TextTags.PLACE, variant)
