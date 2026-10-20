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
## Which tiles exist and their terrain (#36). While the instance is loaded, only `change_tile`
## changes it.
var region: Region
## The tiles `change_tile` changed since the region was arranged (#530), whose kinds are in the
## region: the save keeps them (`to_data`), since arranging the region again can't give them back.
## Hashed through the region's tiles.
var changed_tiles: Dictionary[Vector2i, bool] = {}
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
## Each player slot's world store (#724): what features keep for that player across exits,
## instances and sessions (PlayerStore). The world hands every instance it loads a copy of each and
## takes the one of a player back from the instance they're in once it stepped; within an instance,
## a feature reads and writes its own entry (`store`, `stored`).
var stores: Array[PlayerStore] = []
## The ground of the instances next door (#191): each tile their regions have that this one doesn't,
## with its terrain, in this instance's coordinates. The world hands it over, so sight crosses the
## seam: a loaded neighbour's region as it is, with its tiles changed in place (#538), and the
## others' from their blueprints and seeds, without loading them. Derived data, like the region, so
## it's in no hash; `next_door_version` goes up whenever it changes (`hand_next_door`).
var next_door: Dictionary[Vector2i, int] = {}
var next_door_version: int = 0
## Why the instance's feature order is invalid, or "" when it is valid. An invalid state has no
## features and must not be run: InstanceBlueprints.create refuses it.
var problem: String = ""


func _init(start_region: Region, seed_value: int, ordered: Array[Feature]) -> void:
	region = start_region
	rng_seed = seed_value
	stores = PlayerStore.for_every_slot()
	problem = order_problem(ordered)
	if not problem.is_empty():
		return
	features = ordered
	for each: Feature in features:
		each.start(self)


## Why `ordered` isn't a valid feature order (a feature twice, or one before a feature it
## requires), or "" when it is.
static func order_problem(ordered: Array[Feature]) -> String:
	var seen: Array[String] = []
	for each: Feature in ordered:
		if seen.has(each.id()):
			return "feature %s appears twice" % each.id()
		for needed: String in each.requires():
			if not seen.has(needed):
				return "feature %s needs feature %s before it" % [each.id(), needed]
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


## The entry of the feature `feature_id` in the world store of the player in `slot` (#724), to read
## and write in place: only that feature's rules write it.
func store(slot: int, feature_id: String) -> Dictionary:
	return stores[slot].entry(feature_id)


## The entry of the feature `feature_id` in the world store of the player in `slot`, to read only:
## for views and other features, which never write it.
func stored(slot: int, feature_id: String) -> Dictionary:
	return stores[slot].stored(feature_id)


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


## The instance's feature with this id (Feature.id), or null when the instance doesn't have it.
func feature(id: String) -> Feature:
	for candidate: Feature in features:
		if candidate.id() == id:
			return candidate
	return null


## Switches a feature on or off. Only rules call this, inside a tick; it applies from the
## feature's next step on. Does nothing for a feature the instance doesn't have.
func set_enabled(id: String, on: bool) -> void:
	var target: Feature = feature(id)
	if target != null:
		target.enabled = on


## Changes the kind of `tile` to `kind` in place (#530), e.g. boulders cleared from a path, keeping
## the rest of the instance as it is: every feature hears of it at once (Feature.tile_changed), the
## tick's events get a TileChanged for the views, and the region keeps it until the instance is
## purged, its save too (`to_data`). Only rules call it, inside a tick. Returns whether the tile
## changed: not when it's off the region, already of that kind, or of a kind no blueprint has.
func change_tile(tile: Vector2i, kind: int) -> bool:
	if not region.has_tile(tile) or region.terrain[tile] == kind:
		return false
	var was: int = region.terrain[tile]
	if not region.change(tile, kind):
		return false
	changed_tiles[tile] = true
	for each: Feature in features:
		each.tile_changed(self, tile)
	events.append(TileChanged.new(region, tile, was, kind))
	return true


## Takes `ground` as the ground next door (#191), which only the world hands over: every feature
## hears of it at once (Feature.next_door_changed), so sight across the seam never lags behind it.
func hand_next_door(ground: Dictionary[Vector2i, int]) -> void:
	next_door = ground
	next_door_version += 1
	for each: Feature in features:
		each.next_door_changed(self)


## The instance's state as save data (#119): its tick, its entities as id, slot, q and r in id
## order, the next entity id, the tiles changed in place (#530) as q, r and kind in tile order, and
## each feature's id, on/off and state, in order. The seed and the rest of the region follow from
## the world's seed and the blueprint, so they aren't saved.
func to_data() -> Dictionary:
	var flat: Array[int] = []
	for each: Entity in entities:
		flat.append_array([each.id, each.slot, each.tile.x, each.tile.y])
	var changed: Array[int] = []
	var tiles: Array[Vector2i] = []
	tiles.assign(changed_tiles.keys())
	tiles.sort()
	for tile: Vector2i in tiles:
		changed.append_array([tile.x, tile.y, region.terrain[tile]])
	var saved: Array[Dictionary] = []
	for each: Feature in features:
		saved.append({
			"id": each.id(),
			"enabled": 1 if each.enabled else 0,
			"values": each.save_values(),
		})
	return {
		"tick": tick,
		"next_entity_id": next_entity_id,
		"entities": flat,
		"changed_tiles": changed,
		"features": saved,
	}


## Restores the rest of what `to_data` saved into this state, freshly loaded from the same
## blueprint and seed, once `load_changed_tiles` restored its tiles and the world handed it the
## ground next door (WorldData): its tick and entities, then each feature's state, which is worked
## out from both. Bad data is reported to `data`.
func load_data(data: DataReader) -> void:
	tick = data.whole("tick", 0, DataReader.MOST)
	next_entity_id = data.whole("next_entity_id", 1, DataReader.MOST)
	var flat: Array[int] = data.wholes("entities", -DataReader.MOST, DataReader.MOST)
	if flat.size() % 4 != 0:
		data.fail("an entity is cut off")
		return
	entities.clear()
	for i: int in range(0, flat.size(), 4):
		var problem_here: String = _entity_problem(flat[i], flat[i + 1], flat[i + 2], flat[i + 3])
		if not problem_here.is_empty():
			data.fail(problem_here)
			return
		entities.append(_restored(flat[i], flat[i + 1], Vector2i(flat[i + 2], flat[i + 3])))
	var saved: Array[DataReader] = data.entries("features")
	if saved.size() != features.size():
		data.fail("the instance has %d features, the save %d" % [features.size(), saved.size()])
		return
	for i: int in features.size():
		if saved[i].text("id") != features[i].id():
			data.fail("the instance's features are in another order than the save's")
			return
		features[i].enabled = saved[i].whole("enabled", 0, 1) == 1
		features[i].load_values(self, saved[i].read("values"))


## Changes the region's tiles as `to_data` saved them (#530), without events: a loaded instance
## shows them from the start. Returns whether they were valid; reports why not to `data`.
func load_changed_tiles(data: DataReader) -> bool:
	var flat: Array[int] = data.wholes("changed_tiles", -DataReader.MOST, DataReader.MOST)
	if flat.size() % 3 != 0:
		data.fail("a changed tile is cut off")
		return false
	for i: int in range(0, flat.size(), 3):
		var tile: Vector2i = Vector2i(flat[i], flat[i + 1])
		if changed_tiles.has(tile) or not region.change(tile, flat[i + 2]):
			data.fail("tile %s can't be kind %d, or is changed twice" % [tile, flat[i + 2]])
			return false
		changed_tiles[tile] = true
	return true


## Why an entity with these values can't follow the ones restored so far, or "": ids grow and
## stay below the next id, a slot has one entity at most, and it stands on the region.
func _entity_problem(id: int, slot: int, q: int, r: int) -> String:
	var last: int = entities[entities.size() - 1].id if not entities.is_empty() else 0
	if id <= last or id >= next_entity_id:
		return "entity %d is out of order or not below the next id" % id
	if (slot < Entity.NO_SLOT
			or slot >= MAX_PLAYERS
			or (slot != Entity.NO_SLOT and player(slot) != null)):
		return "entity %d is of slot %d, which is invalid or taken" % [id, slot]
	if not region.has_tile(Vector2i(q, r)):
		return "entity %d stands off the region" % id
	return ""


static func _restored(id: int, slot: int, tile: Vector2i) -> Entity:
	return Entity.new(id, slot, tile)


## A fingerprint of the whole state, the same on every platform: two sessions from the same start
## with the same commands must end with the same hash. A 32-bit FNV-1a over both 32-bit halves of
## every core value, every slot's world store (#724), the region, every entity in id order and, in
## order, every feature's id (as its code, World.name_code), on/off and state.
func state_hash() -> int:
	var values: Array[int] = [tick, rng_seed]
	for each: PlayerStore in stores:
		var stored_values: Array[int] = each.hash_values()
		values.append(stored_values.size())
		values.append_array(stored_values)
	values.append_array(region.hash_values())
	values.append(next_entity_id)
	values.append(entities.size())
	for each: Entity in entities:
		values.append(each.id)
		values.append(each.slot)
		values.append(each.tile.x)
		values.append(each.tile.y)
	for each: Feature in features:
		values.append(World.name_code(each.id()))
		values.append(1 if each.enabled else 0)
		values.append_array(each.hash_values())
	var result: int = 2_166_136_261
	for value: int in values:
		result = _mix(result, value & 0xffff_ffff)
		result = _mix(result, (value >> 32) & 0xffff_ffff)
	return result


static func _mix(current: int, word: int) -> int:
	return ((current ^ word) * 16_777_619) & 0xffff_ffff
