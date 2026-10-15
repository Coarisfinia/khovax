class_name TileKinds
extends RefCounted
## The kinds of tile a region is made of (#116), as the rules see them: Region.terrain holds one
## kind per tile, as its number. Each kind is a tile blueprint (data/tiles/, read by Content), whose
## file gives it a permanent number, never reused or changed once shipped (like Features' ids), so
## adding a kind never renumbers another. The built-in kinds keep the numbers regions always had
## (Region.GROUND, WATER and BLOCKED). Only what rules need is kept here: each kind's id and
## traits; its color and model are the view's, read from the blueprints in meta/.
##
## Tile rules are rules: changing a blueprint's traits (e.g. walkable) changes what the game does,
## so it bumps Simulation.RULES_VERSION and rehashes the golden replays, like any rule change.
##
## Read here at first use rather than handed over by meta/: regions are read in sim/ from files
## already (InstanceBlueprints), and the kinds are fixed data of the build, never state, so they
## need no hash of their own: a region hashes its tiles' numbers.

## Each kind's id, by number; "" for a number no kind has. Empty until first used.
static var _ids: Array[String] = []
## Whether walkers can stand on each kind, by number.
static var _walkable: Array[bool] = []


## The number of the kind with this id, or -1 when there's none.
static func number_of(id: String) -> int:
	_read_once()
	return _ids.find(id) if not id.is_empty() else -1


## The id of kind `kind`, or "" for a number no kind has.
static func id_of(kind: int) -> String:
	_read_once()
	return _ids[kind] if kind >= 0 and kind < _ids.size() else ""


## Whether walkers can stand on a tile of kind `kind`.
static func is_walkable(kind: int) -> bool:
	_read_once()
	return kind >= 0 and kind < _walkable.size() and _walkable[kind]


## How many numbers there are, the largest kind's plus one; gaps count, as kinds nobody has.
static func count() -> int:
	_read_once()
	return _ids.size()


static func _read_once() -> void:
	if not _ids.is_empty():
		return
	var content: Content = Content.load_tiles()
	if not content.problem.is_empty():
		push_error("the tile blueprints didn't load: " + content.problem)
	for tile: TileBlueprint in content.tiles.values():
		if tile.number >= _ids.size():
			var _ids_grown: int = _ids.resize(tile.number + 1)
			var _walkable_grown: int = _walkable.resize(tile.number + 1)
		_ids[tile.number] = tile.id
		_walkable[tile.number] = tile.walkable
