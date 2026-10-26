class_name WildGround
extends RefCounted
## The ground a wild monster steps onto of its own accord (#364, #961, #1203): never the trail, so
## it never walks into a ring, never a tile something stands on, and never one no ring could enclose
## it on (RingableGround), so it stays catchable. Where no ring can enclose a monster depends on the
## terrain alone, so each holder keeps it for its region until a tile changes (`forget`).

## The tiles of `_region` no ring can enclose a wild monster on, kept by `unringable`. Derived from
## the region, so neither hashed nor saved.
var _unringable: Dictionary[Vector2i, bool] = {}
var _region: Region = null


## The walkable tiles of `region` no ring could enclose a wild monster on, worked out again for
## another region or after `forget`.
func unringable(region: Region) -> Dictionary[Vector2i, bool]:
	if region != _region:
		_region = region
		_unringable = RingableGround.unringable(region)
	return _unringable


## Forgets the tiles kept, for a tile of the region changed (#530).
func forget() -> void:
	_region = null


## The tiles a wild monster may not step onto: the trail, so it never walks into a ring, and every
## tile something stands on.
static func blocked(state: GameState) -> WildBlocked:
	var taken: Dictionary[Vector2i, bool] = {}
	for entity: Entity in state.entities:
		taken[entity.tile] = true
	return WildBlocked.new((state.feature(TrailFeature.ID) as TrailFeature).shared.tiles, taken)
