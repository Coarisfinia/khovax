class_name GameState
extends RefCounted
## The core of the simulation's state, in integers: the tick, the seed, the map and the player,
## plus the instance's features, which hold every game rule and their own state. The core holds no
## game rule itself. The presentation reads the state and never writes it.
## Randomness, once a rule needs it, comes from a generator kept in here and seeded by `rng_seed`.

var tick: int = 0
var rng_seed: int = 0
var grid_radius: int = 0
var player_tile: Vector2i = Vector2i.ZERO
## The instance's features, in the order they step each tick.
var features: Array[Feature] = []
## What happened during the current tick, in order, for features later in the order.
var events: Array[RefCounted] = []


func _init(radius: int, start: Vector2i, seed_value: int, ordered: Array[Feature]) -> void:
	grid_radius = radius
	player_tile = start
	rng_seed = seed_value
	var problem: String = order_problem(ordered)
	if not problem.is_empty():
		push_error("invalid feature order: " + problem)
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


func has_tile(tile: Vector2i) -> bool:
	return Hex.distance(Vector2i.ZERO, tile) <= grid_radius


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


## A fingerprint of the whole state, the same on every platform: two runs from the same start
## with the same commands must end with the same hash. A 32-bit FNV-1a over both 32-bit halves of
## every core value and, in order, every feature's id, on/off and state.
func state_hash() -> int:
	var values: Array[int] = [tick, rng_seed, grid_radius, player_tile.x, player_tile.y]
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
