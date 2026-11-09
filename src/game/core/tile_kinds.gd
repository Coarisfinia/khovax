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
## so it adds a file to core/rules_changes/, like any rule change. The blueprints are the resource
## packs' (#1901): a player's pack (#1858) that adds a kind or gives one other traits changes the
## rules too, so replays and co-op hold only between games with the same packs; how such a pack
## declares its rule change is #1858's.
##
## Read here at first use (TileContent, from the files game/ hands it at start): the kinds are fixed
## data of the packs, never state, so they need no hash of their own: a region hashes its tiles'
## kinds, each as its id's code (StateHash.name_code).


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


## Whether a tile of kind `kind` is grass a grazing wild monster eats (#1203).
static func is_grazable(kind: String) -> bool:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile != null and tile.grazable


## Whether a tile of kind `kind` is water a drinking wild monster drinks from (#1203).
static func is_drinkable(kind: String) -> bool:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile != null and tile.drinkable


## The id of the tile table a tile of kind `kind` drops when it's harvested (#696), or "" when it
## can't be harvested.
static func harvest_yields(kind: String) -> String:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile.harvest_yields if tile != null else ""


## The kind a harvested tile of kind `kind` turns into, its depleted kind (#696), or "" when it
## can't be harvested.
static func harvested_into(kind: String) -> String:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile.harvest_becomes if tile != null else ""


## Whether a tile of kind `kind` can be harvested by hand (#696, TileBlueprint.HANDS).
static func harvested_by_hand(kind: String) -> bool:
	var tile: TileBlueprint = TileContent.cached().tiles.get(kind)
	return tile != null and tile.harvest_takes == TileBlueprint.HANDS
