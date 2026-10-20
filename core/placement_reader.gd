class_name PlacementReader
extends RefCounted
## Reads the legend meanings of what one slice places on a region's ground (#824): people, chests,
## loot. RegionDocument asks the readers it's handed which kind a meaning places, and the region
## keeps each such tile with its meaning under that kind (Region.placements); the slice reads the
## meaning again when it runs them. So a new placeable thing is a new reader in its slice, never a
## new region variable or core class. The instance blueprints hand every slice's reader over.


## The kind of thing `meaning` places, the key its tiles are kept under, or "" when it places none
## this reader knows.
func kind_of(_meaning: String) -> String:
	return ""
