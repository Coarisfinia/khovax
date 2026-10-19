class_name HarvestView
extends Node3D
## A felled wild monster's materials (#629) bursting from where it lies, the way a chest's loot does
## (ChestView): this machine's player's own roll only (#74), each item as its name and amount, so it
## never relies on color (#68), rising calmly and fading. The special's damage (SpecialStrikeView)
## rises from the same tile in the same tick, so the materials wait until it has faded rather than
## rise over it: first the blow, then what it dropped. Only for a wild monster in the instance
## shown, and never through the fog. It only reads the tick's events and the state.

@export var driver: GameDriver
## Whose materials are this machine's player's.
@export var input: LocalInput

## The materials waiting or rising, newest last. Kept here so tests can read them.
var bursts: Array[Label3D] = []


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


## The driver also passes on the events of an instance the player just left: a felled monster
## that isn't lying on its tile in the instance shown isn't this one's.
func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	if input == null:
		return
	for event: RefCounted in events:
		var harvested: Harvested = event as Harvested
		var lying: Entity = driver.state.entity(harvested.monster_id) if harvested != null else null
		if lying == null or lying.tile != harvested.tile:
			continue
		var loot: Dictionary = harvested.loot.get(input.slot, {})
		if not loot.is_empty() and FogView.ally_sees(driver.state, harvested.tile):
			_burst(harvested.tile, ChestView.loot_text(loot))


## Shows `text` on `tile` once the special's damage there has faded, then lets it rise and fade.
func _burst(tile: Vector2i, text: String) -> void:
	var label: Label3D = RisingText.make(tile, text)
	label.visible = false
	add_child(label)
	bursts.append(label)
	var wait: Tween = label.create_tween()
	var _waited: IntervalTweener = wait.tween_interval(SpecialStrikeView.SECONDS)
	var _risen: CallbackTweener = wait.tween_callback(_rise.bind(label))


func _rise(label: Label3D) -> void:
	label.visible = true
	RisingText.rise(label, ChestView.LOOT_SECONDS, ChestView.LOOT_RISE, _drop)


func _drop(label: Label3D) -> void:
	bursts.erase(label)
	label.queue_free()
