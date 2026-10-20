class_name TileKinds
extends RefCounted
## The kinds of tile a region is made of (#116), as the rules see them: Region.terrain holds one
## kind per tile, as its id. Each kind is a tile blueprint (content data, read by Content), named
## by its file (#802), never by a hand-kept number, so parallel pull requests adding kinds never
## claim the same one; an id is never reused or renamed once shipped. Only what rules need is kept
## here: each kind's traits; its color and model are the view's, read from the blueprints in
## core/io/ (Content).
##
## Tile rules are rules: changing a blueprint's traits (e.g. walkable) changes what the game does,
## so it adds a file to core/rules_changes/, like any rule change.
##
## Read here at first use rather than handed over from outside the core: the kinds are fixed data
## of the build, never state, so they need no hash of their own: a region hashes its tiles' kinds,
## each as its id's code (StateHash.name_code).

## Whether walkers can stand on each kind, by id. Empty until first used.
static var _walkable: Dictionary[String, bool] = {}
## Whether wild monsters hide in each kind, by id (#202).
static var _hides: Dictionary[String, bool] = {}


## Whether a tile blueprint has the id `kind`.
static func has(kind: String) -> bool:
	_read_once()
	return _walkable.has(kind)


## Whether walkers can stand on a tile of kind `kind`.
static func is_walkable(kind: String) -> bool:
	_read_once()
	return _walkable.has(kind) and _walkable[kind]


## Whether a wild monster standing on a tile of kind `kind` hides there (#202).
static func hides(kind: String) -> bool:
	_read_once()
	return _hides.has(kind) and _hides[kind]


static func _read_once() -> void:
	if not _walkable.is_empty():
		return
	var content: Content = Content.load_tiles()
	if not content.problem.is_empty():
		push_error("the tile blueprints didn't load: " + content.problem)
	for tile: TileBlueprint in content.tiles.values():
		_walkable[tile.id] = tile.walkable
		_hides[tile.id] = tile.hides
