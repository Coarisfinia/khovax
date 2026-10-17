class_name WildAttackFeature
extends Feature
## Wild monsters attack (#422, owner on #421): every wild monster strikes something next to it
## once every STRIKE_TICKS, on its own tick (by its id), for its strength (rage included), its
## species' own attack (#228). It picks, in this order: a companion (#338), then a player, then a
## tile of the allies' trail (#87), the lowest id or the first tile in sorted order among each.
## Each hit raises WildMonsterStruck.
##
## A trail tile wears down: once it has taken TILE_INTEGRITY, it gives way and comes off the trail
## (TrailFeature.clear), so a ring drawn next to a wild monster must close before it breaks open.
## Companions and players have no HP yet, so a hit on them only raises the event (#426).
##
## A wild monster sealing in a ring is encircled: it attacks only the ring, through its seal's
## pushes on the nearest wall segment (DominationFeature, #219), the only way a ring breaks. So it
## isn't attacking here, and nobody else's attack lands on a sealing ring's wall either. Nor does
## a wild monster hiding in its tile (#202) attack: it keeps out of sight.

## The ticks between two strikes of one wild monster, and how much a trail tile takes before it
## gives way. Placeholders to tune (#422).
const STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND
const TILE_INTEGRITY: int = 400

## The damage each trail tile has taken, by tile; one never hit isn't here.
var _wear: Dictionary[Vector2i, int] = {}


func id() -> int:
	return Features.WILD_ATTACKS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.TRAIL, Features.WILD_MONSTERS]
	return needed


## Lets every wild monster due this tick strike, in id order. Wear on tiles that left the trail
## (a ring that ended) is forgotten first.
func step(state: GameState, _commands: Array[Command]) -> void:
	var trail: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	for tile: Vector2i in _worn_tiles():
		if not trail.shared.tiles.has(tile):
			var _dropped: bool = _wear.erase(tile)
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for monster: int in wild.monsters:
		if (state.tick + monster) % STRIKE_TICKS == 0 and _attacking(state, monster):
			_strike(state, monster, wild.strength_of(monster))


## The wild monster strikes the first target next to it, if there is one, for `damage`.
func _strike(state: GameState, monster: int, damage: int) -> void:
	var tile: Vector2i = state.entity(monster).tile
	var target: Entity = _entity_target(state, tile)
	if target != null:
		state.events.append(WildMonsterStruck.new(monster, target.id, target.tile, damage))
		return
	var trail: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	var side: Vector2i = _trail_target(state, trail, tile)
	if side == tile:
		return
	state.events.append(WildMonsterStruck.new(monster, 0, side, damage))
	_wear[side] = _wear.get(side, 0) + damage
	if _wear[side] >= TILE_INTEGRITY:
		var _dropped: bool = _wear.erase(side)
		var cleared: Array[Vector2i] = [side]
		trail.clear(state, cleared)


## The first trail tile next to `tile`, in sorted order, that isn't a sealing ring's wall, or
## `tile` itself when there is none: a wild monster never stands on the trail.
static func _trail_target(state: GameState, trail: TrailFeature, tile: Vector2i) -> Vector2i:
	var domination: DominationFeature = state.feature(Features.DOMINATION) as DominationFeature
	for side: Vector2i in _sides(tile):
		var sealing: bool = domination != null and domination.is_sealing_wall(side)
		if trail.shared.tiles.has(side) and not sealing:
			return side
	return tile


## The companion next to `tile` with the lowest id, else the player next to it with the lowest
## id, else null. Companions aren't required, since an instance may have none.
static func _entity_target(state: GameState, tile: Vector2i) -> Entity:
	var companions: CompanionFeature = state.feature(Features.COMPANIONS) as CompanionFeature
	if companions != null:
		for companion_id: int in companions.companions():
			var companion: Entity = state.entity(companion_id)
			if Hex.distance(companion.tile, tile) == 1:
				return companion
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT and Hex.distance(entity.tile, tile) == 1:
			return entity
	return null


## Whether the wild monster attacks at all: not while it hides or seals in a ring. Hiding and
## domination aren't required, since an instance may have neither; where it has them,
## InstanceBlueprints lists them earlier, so they have stepped already.
static func _attacking(state: GameState, monster: int) -> bool:
	var hiding: HidingFeature = state.feature(Features.HIDING) as HidingFeature
	var domination: DominationFeature = state.feature(Features.DOMINATION) as DominationFeature
	var hidden: bool = hiding != null and hiding.is_hidden(monster)
	return not hidden and not (domination != null and domination.is_sealed(monster))


## The tiles next to `tile`, sorted.
static func _sides(tile: Vector2i) -> Array[Vector2i]:
	var sides: Array[Vector2i] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		sides.append(tile + direction)
	sides.sort()
	return sides


## The worn tiles, sorted.
func _worn_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.assign(_wear.keys())
	tiles.sort()
	return tiles


func hash_values() -> Array[int]:
	var values: Array[int] = [_wear.size()]
	for tile: Vector2i in _worn_tiles():
		values.append_array([tile.x, tile.y, _wear[tile]])
	return values


## The worn tiles, sorted, and the wear on each, in the same order.
func save_values() -> Dictionary:
	var tiles: Array[Vector2i] = _worn_tiles()
	var wear: Array[int] = []
	for tile: Vector2i in tiles:
		wear.append(_wear[tile])
	return { "tiles": DataReader.flat(tiles), "wear": wear }


## Each worn tile must be on the restored trail, once, with less wear than gives way.
func load_values(state: GameState, values: DataReader) -> void:
	_wear.clear()
	var tiles: Array[Vector2i] = values.tiles("tiles", state.region)
	var wear: Array[int] = values.wholes("wear", 1, TILE_INTEGRITY - 1)
	if values.failed():
		return
	if wear.size() != tiles.size():
		values.fail("the worn tiles and their wear don't match")
		return
	var trail: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	for i: int in tiles.size():
		if not trail.shared.tiles.has(tiles[i]) or _wear.has(tiles[i]):
			values.fail("worn tile %s isn't on the trail once" % tiles[i])
			return
		_wear[tiles[i]] = wear[i]
