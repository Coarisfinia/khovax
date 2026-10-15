class_name TileKinds
extends RefCounted
## The kinds of tile a region is made of (#116), numbered for the simulation: Region.terrain holds
## one kind per tile, as its index here. Each kind is a tile blueprint (data/tiles/, read by
## Content). The built-in kinds keep the numbers regions always had (Region.GROUND, WATER and
## BLOCKED), so a region without new kinds hashes as before; every other kind follows in id order,
## so the same data always gives the same numbers on every machine.
##
## Read here at first use rather than handed over by meta/: regions are read in sim/ from files
## already (InstanceBlueprints), and the kinds are fixed data of the build, never state, so they
## need no hash of their own: a region hashes its tiles' numbers.

## The built-in kinds' ids, by number.
const BUILT_IN: Array[String] = ["ground", "water", "rock"]

## Every kind, by number; empty until first used.
static var _kinds: Array[TileBlueprint] = []


## The kind with this id's number, or -1 when there's none.
static func index_of(id: String) -> int:
	for kind: int in all().size():
		if _kinds[kind].id == id:
			return kind
	return -1


## The tile blueprint of kind `kind`; null for a number no kind has.
static func blueprint(kind: int) -> TileBlueprint:
	if kind < 0 or kind >= all().size():
		return null
	return _kinds[kind]


## Whether walkers can stand on a tile of kind `kind`.
static func is_walkable(kind: int) -> bool:
	return kind >= 0 and kind < all().size() and _kinds[kind].walkable


## Every kind, by number, read from the content data the first time.
static func all() -> Array[TileBlueprint]:
	if _kinds.is_empty():
		_kinds = _read()
	return _kinds


static func _read() -> Array[TileBlueprint]:
	var content: Content = Content.load_tiles()
	if not content.problem.is_empty():
		push_error("the tile blueprints didn't load: " + content.problem)
	var ids: Array[String] = []
	ids.assign(content.tiles.keys())
	ids.sort()
	var kinds: Array[TileBlueprint] = []
	# A missing built-in kind keeps its number, as a kind nobody walks on, so others keep theirs.
	var missing: TileBlueprint = TileBlueprint.new()
	for id: String in BUILT_IN:
		if not content.tiles.has(id):
			push_error("the built-in tile blueprint %s is missing" % id)
		kinds.append(content.tiles.get(id, missing))
	for id: String in ids:
		if not BUILT_IN.has(id):
			kinds.append(content.tiles[id])
	return kinds
