class_name PlacementReader
extends RefCounted
## Reads the legend meanings of what one slice places on a region's ground (#824): people, chests,
## loot, tile triggers, named wild monsters. RegionDocument asks the readers it's handed which kind
## a meaning places, and the region keeps each such tile with its meaning under that kind
## (Region.placements); the slice reads the meaning again when it runs them. So a new placeable
## thing is a new reader in its slice, never a new region variable or core class. The instance
## blueprints hand every slice's reader over.


## The kind of thing `meaning` places, the key its tiles are kept under, or "" when it places none
## this reader knows.
func kind_of(_meaning: String) -> String:
	return ""


## The kinds this reader places, every one `kind_of` can give.
func kinds() -> Array[String]:
	return []


## The id of the feature that runs what this reader places (#879): an instance whose region holds
## any of its kinds has that feature, so its blueprint never lists it.
func feature() -> String:
	return ""


## The part of `meaning` that names the kind of tile its thing stands on, which the core reads like
## a tile kind's meaning (`sand`, `forest, turned 2`), or "" for ground.
func tile_of(_meaning: String) -> String:
	return ""


## Whether its things stand on ground (#824), as most do, rather than on a tile nobody walks, like a
## seal a guide opens (#1588): the region refuses one on a tile that isn't walkable unless it says
## no.
func on_ground() -> bool:
	return true


## Whether a wild monster stands where this reader's things are placed: the core keeps every wild
## monster's spot (Region.wild_monsters), which it hashes and the wild monster feature fills.
func places_wild_monster() -> bool:
	return false


## Why what this reader's kinds place on `region` doesn't hold together across the region (a thing
## marked twice), or "". Asked once everything is placed.
func problem_in(_region: Region) -> String:
	return ""
