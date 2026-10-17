class_name HidingFeature
extends Feature
## Hiding tiles (#202): a wild monster that starts on a tile whose kind hides (a tile blueprint's
## `hides` trait, e.g. shrubs) stays hidden there until a player comes next to it, then jumps out
## (a MonsterJumpedOut event) and is a wild monster like any other from then on. Hidden, it still
## blocks walkers, and a ring around it still dominates it: hiding only keeps it out of sight. It
## stays in its tile while hidden, held there (WildMonsterFeature.hold), even where no ring could
## enclose it (#364).
## Instances whose region has such a monster have it.

## How near a player comes before a hidden wild monster jumps out: next to it.
const NEAR: int = 1

## Every hidden wild monster's entity id, in id order.
var hidden: Array[int] = []


func id() -> int:
	return Features.HIDING


func requires() -> Array[int]:
	var needed: Array[int] = [Features.WILD_MONSTERS]
	return needed


## Hides every wild monster that starts on a tile that hides.
func start(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for monster: int in wild.monsters:
		if hides_at(state.region, state.entity(monster).tile):
			hidden.append(monster)
			wild.hold(monster, true)


func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var still: Array[int] = []
	for monster: int in hidden:
		var tile: Vector2i = state.entity(monster).tile
		if _player_near(state, tile):
			state.events.append(_jumped_out(monster, tile))
			wild.hold(monster, false)
		else:
			still.append(monster)
	hidden = still


func entity_removed(_state: GameState, removed_id: int) -> void:
	hidden.erase(removed_id)


## Whether the wild monster with this entity id is hidden.
func is_hidden(entity_id: int) -> bool:
	return hidden.has(entity_id)


## Whether a wild monster on `tile` of `region` hides there.
static func hides_at(region: Region, tile: Vector2i) -> bool:
	var kind: int = region.terrain.get(tile, Region.GROUND)
	return TileKinds.hides(kind)


## Whether any wild monster spot of `region` hides, so its instance needs the feature.
static func has_hiding(region: Region) -> bool:
	for spot: Vector2i in region.wild_monsters:
		if hides_at(region, spot):
			return true
	return false


func hash_values() -> Array[int]:
	var values: Array[int] = [hidden.size()]
	values.append_array(hidden)
	return values


## The wild monsters still hidden, by entity id.
func save_values() -> Dictionary:
	return { "hidden": hidden }


func load_values(state: GameState, values: DataReader) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var saved: Array[int] = values.wholes("hidden", 1, DataReader.MOST)
	hidden.clear()
	for monster: int in saved:
		if not wild.is_wild_monster(monster) or hidden.has(monster):
			values.fail("hidden %d isn't one wild monster" % monster)
			return
		hidden.append(monster)
		wild.hold(monster, true)
	hidden.sort()


static func _jumped_out(monster: int, tile: Vector2i) -> MonsterJumpedOut:
	return MonsterJumpedOut.new(monster, tile)


static func _player_near(state: GameState, tile: Vector2i) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null and Hex.distance(player.tile, tile) <= NEAR:
			return true
	return false
