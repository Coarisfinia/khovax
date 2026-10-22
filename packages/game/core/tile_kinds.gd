class_name TileKinds
extends RefCounted
## The kinds of tile a region is made of (#116), as the rules see them: Region.terrain holds one
## kind per tile, as its id. Each kind is a tile blueprint (content data, read by TileContent),
## named by its file (#802), never by a hand-kept number, so parallel pull requests adding kinds
## never claim the same one; an id is never reused or renamed once shipped. Only what rules need is
## read here: each kind's traits; its color and model are the view's, read from the blueprints in
## core/io/ (TileContent).
##
## Tile rules are rules: changing a blueprint's traits (e.g. walkable) changes what the game does,
## so it adds a file to core/rules_changes/, like any rule change.
##
## Read here at first use rather than handed over from outside the core: the kinds are fixed data
## of the build, never state, so they need no hash of their own: a region hashes its tiles' kinds,
## each as its id's code (StateHash.name_code).


## Whether a tile blueprint has the id `kind`.
static func has(kind: String) -> bool:
	return TileContent.cached().tiles.has(kind)


## Whether walkers can stand on a tile of kind `kind`.
static func is_walkable(kind: String) -> bool:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile != null and tile.walkable


## Whether a wild monster standing on a tile of kind `kind` hides there (#202).
static func hides(kind: String) -> bool:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile != null and tile.hides
