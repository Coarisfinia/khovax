class_name GameState
extends RefCounted
## The core of the simulation's state, in integers: the tick, the seed, the region and the entities,
## plus the instance's features, which hold every game rule and their own state. The core holds no
## game rule itself. The presentation reads the state and never writes it.
## Randomness, once a rule needs it, comes from a generator kept in here and seeded by `rng_seed`.

## Players in this instance, each in its own slot; a tick's commands are indexed by slot.
const MAX_PLAYERS: int = 4

var tick: int = 0
var rng_seed: int = 0
## Which tiles exist and their terrain (#36). It doesn't change while the instance is loaded yet.
var region: Region
## The id the next added entity gets. Ids only grow, so a removed entity's id is never reused.
var next_entity_id: int = 1
## Every entity, in id order. Rules always go through entities in this order, never in a
## dictionary's or a hash's order, so every machine runs them the same way.
var entities: Array[Entity] = []
## The instance's features, in the order they step each tick.
var features: Array[Feature] = []
## What happened during the current tick, in order, for features later in the order; the driver
## hands a copy to views after the tick (GameDriver.ticked). Transient: cleared when a tick starts
## and derived from the tick's own changes, so it is not part of the state's contract or its hash,
## though a replay raises the same events.
var events: Array[RefCounted] = []
## Why the instance's feature order is invalid, or "" when it is valid. An invalid state has no
## features and must not be run: InstanceBlueprints.create refuses it.
var problem: String = ""


func _init(start_region: Region, seed_value: int, ordered: Array[Feature]) -> void:
	region = start_region
	rng_seed = seed_value
	problem = order_problem(ordered)
	if not problem.is_empty():
		return
	features = ordered
	for each: Feature in features:
		each.start(self)


## Why `ordered` isn't a valid feature order (a feature twice, or one before a feature it
## requires), or "" when it is.
static func order_problem(ordered: Array[Feature]) -> String:
	var seen: Array[int] = []
	for each: Feature in ordered:
		if seen.has(each.id()):
			return "feature %d appears twice" % each.id()
		for needed: int in each.requires():
			if not seen.has(needed):
				return "feature %d needs feature %d before it" % [each.id(), needed]
		seen.append(each.id())
	return ""


## Adds an entity owned by `slot` (or Entity.NO_SLOT) on `tile`, with the next id, and lets every
## feature, on or off, set up its data for it. A slot's entity is that player, so each slot has at
## most one: returns null, adding nothing, for a slot out of range or already taken.
func add_entity(slot: int, tile: Vector2i) -> Entity:
	if slot != Entity.NO_SLOT and (slot < 0 or slot >= MAX_PLAYERS or player(slot) != null):
		return null
	var added: Entity = Entity.new(next_entity_id, slot, tile)
	next_entity_id += 1
	# Ids only grow, so appending keeps the list in id order.
	entities.append(added)
	for each: Feature in features:
		each.entity_added(self, added)
	return added


## Removes the entity with this id, and every feature's data for it. The other entities keep
## their ids.
func remove_entity(id: int) -> void:
	for i: int in entities.size():
		if entities[i].id == id:
			entities.remove_at(i)
			for each: Feature in features:
				each.entity_removed(self, id)
			return


## The entity with this id, or null.
func entity(id: int) -> Entity:
	for candidate: Entity in entities:
		if candidate.id == id:
			return candidate
	return null


## The entity the player in this slot controls, or null when the slot is empty.
func player(slot: int) -> Entity:
	for candidate: Entity in entities:
		if candidate.slot == slot:
			return candidate
	return null


## The instance's feature with this id from Features, or null when the instance doesn't have it.
func feature(id: int) -> Feature:
	for candidate: Feature in features:
		if candidate.id() == id:
			return candidate
	return null


## Switches a feature on or off. Only rules call this, inside a tick; it applies from the
## feature's next step on. Does nothing for a feature the instance doesn't have.
func set_enabled(id: int, on: bool) -> void:
	var target: Feature = feature(id)
	if target != null:
		target.enabled = on


## A fingerprint of the whole state, the same on every platform: two sessions from the same start
## with the same commands must end with the same hash. A 32-bit FNV-1a over both 32-bit halves of
## every core value, the region, every entity in id order and, in order, every feature's id, on/off
## and state.
func state_hash() -> int:
	var values: Array[int] = [tick, rng_seed]
	values.append_array(region.hash_values())
	values.append(next_entity_id)
	values.append(entities.size())
	for each: Entity in entities:
		values.append(each.id)
		values.append(each.slot)
		values.append(each.tile.x)
		values.append(each.tile.y)
	for each: Feature in features:
		values.append(each.id())
		values.append(1 if each.enabled else 0)
		values.append_array(each.hash_values())
	var result: int = 2_166_136_261
	for value: int in values:
		result = _mix(result, value & 0xffff_ffff)
		result = _mix(result, (value >> 32) & 0xffff_ffff)
	return result


static func _mix(current: int, word: int) -> int:
	return ((current ^ word) * 16_777_619) & 0xffff_ffff
