class_name AllySight
extends RefCounted
## Whether any player sees a tile, answered from a lookup set of each player's sight (#1395): the
## views ask it for every wild monster, person and chest on every frame (FogView.ally_sees), and a
## search through the fog's sight arrays grew with the sight and the figures. A player's set is
## built again only when the fog hands them a new sight array (FogFeature replaces it whenever their
## sight changes), so the fog's state and its hash stay as they are.

## The sight array each slot's set was built from, to tell when it's replaced.
static var _built_from: Array = []
## Each slot's sight as a set: its tiles, each to true.
static var _sets: Array[Dictionary] = []


## Whether any player sees `tile` by `fog`'s sight.
static func sees(fog: FogFeature, tile: Vector2i) -> bool:
	if _sets.is_empty():
		var _sized: int = _built_from.resize(GameState.MAX_PLAYERS)
		for slot: int in GameState.MAX_PLAYERS:
			_sets.append({})
	for slot: int in GameState.MAX_PLAYERS:
		if not fog.visible.has(slot):
			# A player who left lets their old sight go.
			if _built_from[slot] != null:
				_built_from[slot] = null
				_sets[slot] = {}
			continue
		var tiles: Array = fog.visible[slot]
		if not is_same(tiles, _built_from[slot]):
			_built_from[slot] = tiles
			_sets[slot] = _set_of(tiles)
		if _sets[slot].has(tile):
			return true
	return false


## The tiles in `tiles`, each to true.
static func _set_of(tiles: Array) -> Dictionary:
	var lookup: Dictionary = {}
	for tile: Vector2i in tiles:
		lookup[tile] = true
	return lookup
