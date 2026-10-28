class_name HarvestView
extends Node3D
## A felled wild monster's materials (#629) bursting from where it lies, the way a chest's loot does
## (ChestView): this machine's player's own roll only (#74), each item as its name and amount, so it
## never relies on color (#68), rising calmly and fading. The special's damage (DamageNumbersView)
## rises from the same tile in the same tick, so the materials wait until it has faded rather than
## rise over it: first the blow, then what it dropped. Only for a wild monster in the instance
## shown, and never through the fog. A tile harvested by hand (#696) bursts the same way, at once,
## as no blow lands there. It only reads the tick's events and the state.

@export var driver: Session
## Whose materials are this machine's player's.
@export var input: LocalInput

## The materials waiting or rising, newest last. Kept here so tests can read them.
var bursts: Array[Label3D] = []


func _ready() -> void:
	var _connected: int = driver.ticked.connect(_on_ticked)


func _on_ticked(_tick: int, events: Array[RefCounted]) -> void:
	if input == null:
		return
	for event: RefCounted in driver.local_events(events):
		var harvested: Harvested = event as Harvested
		var by_hand: TileHarvested = event as TileHarvested
		if harvested != null:
			_burst(harvested.tile, harvested.loot, DamageNumbersView.SECONDS)
		elif by_hand != null:
			_burst(by_hand.tile, by_hand.loot, 0.0)


## Shows this machine's player's own of `by_slot`'s loot on `tile` after `wait` seconds (a
## special's damage there fading first), then lets it rise and fade; nothing for no loot or a tile
## in the fog.
func _burst(tile: Vector2i, by_slot: Dictionary[int, Dictionary], wait: float) -> void:
	var loot: Dictionary = by_slot.get(input.slot, {})
	if loot.is_empty() or not FogView.ally_sees(driver.state, tile):
		return
	var label: Label3D = RisingText.make(tile, ChestView.loot_text(loot))
	label.visible = false
	add_child(label)
	bursts.append(label)
	var waiting: Tween = label.create_tween()
	var _waited: IntervalTweener = waiting.tween_interval(wait)
	var _risen: CallbackTweener = waiting.tween_callback(_rise.bind(label))


func _rise(label: Label3D) -> void:
	label.visible = true
	RisingText.rise(label, ChestView.LOOT_SECONDS, ChestView.LOOT_RISE, _drop)


func _drop(label: Label3D) -> void:
	bursts.erase(label)
	label.queue_free()
