class_name GameState
extends RefCounted
## Everything the simulation knows, in integers. The presentation reads it and never writes it.
## Randomness, once a rule needs it, comes from a generator kept in here and seeded by `rng_seed`.

var tick: int = 0
var rng_seed: int = 0
var grid_radius: int = 0
var player_tile: Vector2i = Vector2i.ZERO
## The tile the player's current move started from.
var move_from: Vector2i = Vector2i.ZERO
## Ticks until the player's current move arrives; 0 when standing on `player_tile`.
var move_ticks_left: int = 0


func _init(radius: int, start: Vector2i, seed_value: int) -> void:
	grid_radius = radius
	player_tile = start
	move_from = start
	rng_seed = seed_value


func has_tile(tile: Vector2i) -> bool:
	return Hex.distance(Vector2i.ZERO, tile) <= grid_radius


func is_moving() -> bool:
	return move_ticks_left > 0


## A fingerprint of the whole state, the same on every platform: two runs from the same start
## with the same commands must end with the same hash. A 32-bit FNV-1a over every field.
func state_hash() -> int:
	var values: Array[int] = [
		tick,
		rng_seed,
		grid_radius,
		player_tile.x,
		player_tile.y,
		move_from.x,
		move_from.y,
		move_ticks_left,
	]
	var result: int = 2_166_136_261
	for value: int in values:
		result = ((result ^ (value & 0xffff_ffff)) * 16_777_619) & 0xffff_ffff
	return result
