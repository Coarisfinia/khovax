class_name SealPlacements
extends PlacementReader
## Reads the seals a region's legend places (#1588), for EscortFeature: tiles nobody walks that a
## guide, a person the same region piece places, opens once they're led there. The legend says the
## tile's
## kind, then whose seal it is: `<tile kind>; sealed until <person id> opens it`, e.g. `boulder;
## sealed until teska_na_amvrel opens it`.

## The kind the region keeps its seals under (Region.placements).
const KIND: String = "seal"
## What separates the tile's kind from whose seal it is, and the words around the person's id.
const SAID: String = "; "
const UNTIL: String = "sealed until "
const OPENS: String = " opens it"


func kinds() -> Array[String]:
	return [KIND]


func feature() -> String:
	return EscortFeature.ID


func kind_of(meaning: String) -> String:
	return KIND if not opener(meaning).is_empty() else ""


func tile_of(meaning: String) -> String:
	return meaning.get_slice(SAID, 0)


## A seal stands on a tile nobody walks, until it's opened.
func on_ground() -> bool:
	return false


## A seal on a tile anyone walks seals nothing, one whose person the region piece doesn't place has
## nobody to open it, and one with no walkable tile beside it has nowhere for them to stand.
func problem_in(region: Region) -> String:
	var people: Array[String] = []
	var placed: Dictionary[Vector2i, String] = region.placed(NpcPlacements.KIND)
	for tile: Vector2i in placed:
		people.append(NpcSpot.read(placed[tile]).id)
	var sealed: Dictionary[Vector2i, String] = region.placed(KIND)
	var standing: Array[String] = []
	for tile: Vector2i in sealed:
		for direction: Vector2i in Hex.DIRECTIONS:
			if region.is_walkable(tile + direction) and not standing.has(opener(sealed[tile])):
				standing.append(opener(sealed[tile]))
	for tile: Vector2i in sealed:
		if not standing.has(opener(sealed[tile])):
			return "the seal on %s has no walkable tile beside it" % tile
		if region.is_walkable(tile):
			return "the seal on %s is on a tile anyone walks" % tile
		if not people.has(opener(sealed[tile])):
			return "the seal on %s is %s's, who the region doesn't place" % [
				tile,
				opener(sealed[tile]),
			]
	return ""


## The id of the person who opens the seal a legend `meaning` places, or "" when it places none.
static func opener(meaning: String) -> String:
	var parts: PackedStringArray = meaning.split(SAID)
	if parts.size() != 2 or not parts[1].begins_with(UNTIL) or not parts[1].ends_with(OPENS):
		return ""
	var person: String = parts[1].trim_prefix(UNTIL).trim_suffix(OPENS)
	return person if Ids.is_id(person) else ""
