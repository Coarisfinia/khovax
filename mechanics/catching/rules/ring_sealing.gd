class_name RingSealing
extends RefCounted
## How strong a sealing ring is (#219, #286): its power, spread over its wall's segments; how hard
## each wild monster inside pushes on its nearest segment; how long the seal takes; and how a player
## standing on a segment reinforces it (#227). CatchFeature closes the rings and decides what a
## held or broken one gives; the numbers live here.

## The ring rules' constants (#219). Every one is a placeholder, to tune (#219).
## Players have no level yet: every player draws rings at this level until they do.
const PLAYER_LEVEL: int = 1
## Ring power is BASE + level × PER_LEVEL (+ companion passives, none yet): the issue's 100 + 20 ×
## level scaled up, so a monster's pressure each tick (its strength) wears a wall down over a
## whole seal rather than in one tick.
const RING_POWER_BASE: int = 30_000
const RING_POWER_PER_LEVEL: int = 6_000
## A seal takes this many ticks, plus one per SEAL_PRESSURE_PER_TICK of pressure inside
## (thousandths): more resistance seals slower.
const SEAL_BASE_TICKS: int = 40
const SEAL_PRESSURE_PER_TICK: int = 10 * Fixed.ONE
## The share of the pressure a wall segment takes while a player stands on it (thousandths).
const REINFORCED_SHARE: int = 100


## The power of a ring drawn at `level`.
static func ring_power(level: int) -> int:
	return RING_POWER_BASE + level * RING_POWER_PER_LEVEL


## How hard the wild monster pushes on a wall each tick, in thousandths: its strength, scaled by
## the HP it has left, so weakening it first makes the ring easier to hold.
static func pressure(wild: WildMonsterFeature, monster_id: int) -> int:
	var left: int = Fixed.ratio(wild.hp_of(monster_id), wild.max_hp_of(monster_id))
	return wild.strength_of(monster_id) * left


## A new seal of the ring `trail` closed around the wild monsters `inside`.
static func build(state: GameState, trail: Trail, inside: Array[int]) -> RingSeal:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var seal: RingSeal = RingSeal.new()
	var spots: Array[Vector2i] = []
	for monster_id: int in inside:
		spots.append(state.entity(monster_id).tile)
	seal.walls = RingShape.wall_around(state.region, trail, spots)
	var _sized: int = seal.damage.resize(seal.walls.size())
	seal.damage.fill(0)
	seal.integrity = Fixed.mul_div(ring_power(PLAYER_LEVEL), Fixed.ONE, seal.walls.size())
	seal.monsters = inside
	var total: int = 0
	for i: int in inside.size():
		seal.targets.append(RingShape.nearest(seal.walls, spots[i]))
		total += pressure(wild, inside[i])
	seal.seal_ticks = SEAL_BASE_TICKS + Fixed.div_floor(total, SEAL_PRESSURE_PER_TICK)
	return seal


## One tick of `seal`: every player standing on its wall braces that segment, and every monster
## inside pushes on its own segment, which takes only REINFORCED_SHARE of that while a player
## stands on it.
static func push(state: GameState, seal: RingSeal) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var braced: Array[Vector2i] = reinforced(state, seal)
	seal.ticks += 1
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT and seal.walls.has(entity.tile):
			seal.brace(entity.id, entity.tile)
	for i: int in seal.monsters.size():
		var pushed: int = pressure(wild, seal.monsters[i])
		if braced.has(seal.walls[seal.targets[i]]):
			pushed = Fixed.scale(pushed, REINFORCED_SHARE)
		seal.damage[seal.targets[i]] += pushed


## The seal's wall segments a player stands on, reinforcing them (#227), in the wall's order. The
## rules and the views (#234) both ask this.
static func reinforced(state: GameState, seal: RingSeal) -> Array[Vector2i]:
	var stood_on: Dictionary[Vector2i, bool] = {}
	for entity: Entity in state.entities:
		if entity.slot != Entity.NO_SLOT:
			stood_on[entity.tile] = true
	var braced: Array[Vector2i] = []
	for wall: Vector2i in seal.walls:
		if stood_on.has(wall):
			braced.append(wall)
	return braced
