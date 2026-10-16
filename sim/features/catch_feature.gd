class_name CatchFeature
extends Feature
## Catching (#20) with sealing (#219): when a player's trail closes a ring around wild monsters, the
## ring seals. It must hold for a while as every wild monster inside pushes on its nearest wall
## segment; if it holds, everything inside is caught (a WildMonsterCaught event each says who caught
## it), and if a segment gives way, the ring breaks and nothing is (a RingBroken event). Either way
## the player's trail starts over from where they stand.
##
## Enclosed means the monster's tile can't reach the region's edge without crossing that player's
## trail: one flood fill from the edge over the region's tiles, whatever their terrain, so only the
## trail encloses. The ring's wall is the trail tiles next to the enclosed tiles around the
## monsters. Bigger rings spread the same ring power over more segments, so their walls are thinner.
##
## While a ring seals, its player walks on as usual but draws no new ring, the monsters inside stay
## where they stand (wild monsters don't move yet), and a monster sealed in one player's ring can't
## be sealed in another's: each player's ring seals on its own. Any player standing on a wall
## segment reinforces it (#227), whoever's ring it is: a reinforced segment takes only a share of
## the pressure on it, which is strong, but it puts the player right where the monsters push.
## Enraged monsters after a break (#220) and shared co-op rings (#87) build on this later.
##
## It runs after the trail has grown this tick, reads the trail and the wild monsters, and starts
## the catcher's trail over through TrailFeature.restart: features later in the order change an
## earlier one only through its public methods.

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

## Every sealing ring, by its player's entity id.
var seals: Dictionary[int, RingSeal] = {}
## The edge of `_edge_region`, cached by _edge_of.
var _edge: Array[Vector2i] = []
var _edge_region: Region = null


func id() -> int:
	return Features.CATCH


func requires() -> Array[int]:
	var needed: Array[int] = [Features.TRAIL, Features.WILD_MONSTERS]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	# Rings sealing since an earlier tick push first, so a ring closed this tick starts next tick.
	for catcher_id: int in _sealing_players():
		_push(state, catcher_id)
	_close_rings(state)


## The power of a ring drawn at `level`.
static func ring_power(level: int) -> int:
	return RING_POWER_BASE + level * RING_POWER_PER_LEVEL


## How hard the wild monster pushes on a wall each tick, in thousandths: its strength, scaled by
## the HP it has left, so weakening it first makes the ring easier to hold.
static func pressure(wild: WildMonsterFeature, monster_id: int) -> int:
	var left: int = Fixed.ratio(wild.hp_of(monster_id), wild.max_hp_of(monster_id))
	return wild.strength_of(monster_id) * left


## Every new ring closed this tick around wild monsters not sealing yet starts sealing. A ring can
## only close when its player's trail grows, so rings are checked per new trail tile, in the order
## the moves happened: entity id order, so when two players close rings around the same monster in
## one tick, the earlier one seals it. This relies on wild monsters standing still: every monster
## inside a ring was found when the ring closed. A rule that moves monsters must also check when a
## monster steps into an old ring.
func _close_rings(state: GameState) -> void:
	var trails: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for grew: TrailGrew in _grown(state):
		if trails.trail(grew.entity_id) == null or seals.has(grew.entity_id):
			continue
		var trail: Trail = trails.trail(grew.entity_id)
		if wild.monsters.is_empty() or not RingShape.may_close(trail, grew):
			continue
		# One flood per move, for every monster at once (#104).
		var edge: Array[Vector2i] = _edge_of(state.region)
		var reachable: Dictionary[Vector2i, bool] = RingShape.outside(state.region, trail, edge)
		var inside: Array[int] = []
		for monster_id: int in wild.monsters:
			var spot: Vector2i = state.entity(monster_id).tile
			if not trail.tiles.has(spot) and not reachable.has(spot) and not _is_sealed(monster_id):
				inside.append(monster_id)
		if not inside.is_empty():
			seals[grew.entity_id] = _seal(state, trail, inside)


## The tick's TrailGrew events in entity id order, whatever order they were raised in: who seals a
## monster two players ring in the same tick never depends on the order of the events.
static func _grown(state: GameState) -> Array[TrailGrew]:
	var grown: Array[TrailGrew] = []
	for event: RefCounted in state.events:
		if event is TrailGrew:
			grown.append(event as TrailGrew)
	grown.sort_custom(func(a: TrailGrew, b: TrailGrew) -> bool: return a.entity_id < b.entity_id)
	return grown


## A new seal of the ring `trail` closed around the wild monsters `inside`.
func _seal(state: GameState, trail: Trail, inside: Array[int]) -> RingSeal:
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


## One tick of the player's seal: every monster inside pushes on its segment, which takes only
## REINFORCED_SHARE of that while a player stands on it. A segment whose damage reaches its
## integrity breaks the ring; a ring that holds for its seal ticks catches everything inside.
func _push(state: GameState, catcher_id: int) -> void:
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var seal: RingSeal = seals[catcher_id]
	var braced: Array[Vector2i] = reinforced(state, seal)
	seal.ticks += 1
	for i: int in seal.monsters.size():
		var push: int = pressure(wild, seal.monsters[i])
		if braced.has(seal.walls[seal.targets[i]]):
			push = Fixed.scale(push, REINFORCED_SHARE)
		seal.damage[seal.targets[i]] += push
	var failed: int = seal.failed_segment()
	if failed >= 0:
		var slot: int = state.entity(catcher_id).slot
		var walls: Array[Vector2i] = seal.walls
		var broken: RingBroken = RingBroken.new(
			catcher_id,
			slot,
			walls[failed],
			walls,
			seal.monsters,
		)
		state.events.append(broken)
		_end(state, catcher_id)
	elif seal.ticks >= seal.seal_ticks:
		for monster_id: int in seal.monsters.duplicate():
			_catch(state, monster_id, catcher_id)
		_end(state, catcher_id)


## Ends the player's seal, held or broken: their trail starts over from where they stand.
func _end(state: GameState, catcher_id: int) -> void:
	var _dropped: bool = seals.erase(catcher_id)
	var trails: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
	trails.restart(catcher_id, state.entity(catcher_id).tile)


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


## The players whose rings are sealing, in id order.
func _sealing_players() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(seals.keys())
	ids.sort()
	return ids


func _is_sealed(monster_id: int) -> bool:
	for seal: RingSeal in seals.values():
		if seal.monsters.has(monster_id):
			return true
	return false


## The region's edge: every tile next to where the region ends, in a fixed order. Regions don't
## change during a session (a rule that edits one in place must clear this cache), so it's worked
## out once per region, and a replaced region is noticed. Derived from the region, so not part of
## the hash.
func _edge_of(region: Region) -> Array[Vector2i]:
	if region != _edge_region:
		_edge_region = region
		_edge = RingShape.edge_of(region)
	return _edge


func _catch(state: GameState, monster_id: int, catcher_id: int) -> void:
	var tile: Vector2i = state.entity(monster_id).tile
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var species: String = wild.species_of(monster_id)
	var slot: int = state.entity(catcher_id).slot
	state.remove_entity(monster_id)
	state.events.append(WildMonsterCaught.new(monster_id, catcher_id, slot, tile, species))


## A player who leaves the instance takes their seal with them, unfinished; a wild monster that
## leaves it pushes no more.
func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = seals.erase(removed_id)
	for seal: RingSeal in seals.values():
		seal.drop(removed_id)


## Every sealing ring as its player's entity id and its seal, in id order.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for catcher_id: int in _sealing_players():
		var entry: Dictionary = seals[catcher_id].to_data()
		entry["catcher"] = catcher_id
		saved.append(entry)
	return { "seals": saved }


## Restores each seal by building it again from the restored trail and monsters, with the same
## code that builds a new one, and taking only its damage and ticks from the save. A save whose
## walls differ from the rebuilt ones, or that names a monster twice, in two seals or outside the
## ring, is refused.
func load_values(state: GameState, values: DataReader) -> void:
	seals.clear()
	for entry: DataReader in values.entries("seals"):
		var catcher_id: int = entry.whole("catcher", 1, DataReader.MOST)
		var catcher: Entity = state.entity(catcher_id)
		if catcher == null or catcher.slot == Entity.NO_SLOT or seals.has(catcher_id):
			values.fail("sealing ring of %d isn't one player's" % catcher_id)
			return
		var monsters: Array[int] = entry.wholes("monsters", 1, DataReader.MOST)
		var problem: String = _monsters_problem(state, catcher_id, monsters)
		if not problem.is_empty():
			values.fail("sealing ring of %d: %s" % [catcher_id, problem])
			return
		var trails: TrailFeature = state.feature(Features.TRAIL) as TrailFeature
		var seal: RingSeal = _seal(state, trails.trail(catcher_id), monsters)
		problem = _progress_problem(state, seal, entry)
		if not problem.is_empty():
			values.fail("sealing ring of %d: %s" % [catcher_id, problem])
			return
		seals[catcher_id] = seal


## Why the saved monsters can't be sealing in the player's ring, or "": they must be wild monsters,
## in increasing id order (so none twice), in no other seal, and enclosed by the player's trail.
func _monsters_problem(state: GameState, catcher_id: int, monsters: Array[int]) -> String:
	var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).trail(catcher_id)
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	if trail == null or monsters.is_empty():
		return "it has no trail or no wild monsters"
	var edge: Array[Vector2i] = _edge_of(state.region)
	var reachable: Dictionary[Vector2i, bool] = RingShape.outside(state.region, trail, edge)
	for i: int in monsters.size():
		var monster_id: int = monsters[i]
		if i > 0 and monster_id <= monsters[i - 1]:
			return "its monsters are out of order or there twice"
		if not wild.is_wild_monster(monster_id) or _is_sealed(monster_id):
			return "%d isn't a wild monster, or is in another seal" % monster_id
		var spot: Vector2i = state.entity(monster_id).tile
		if trail.tiles.has(spot) or reachable.has(spot):
			return "%d isn't inside the ring" % monster_id
	return ""


## Why the saved walls, damage and ticks don't fit the rebuilt `seal`, or ""; when they do, the
## damage and ticks go into it. The ring must not have broken or held yet.
static func _progress_problem(state: GameState, seal: RingSeal, entry: DataReader) -> String:
	var walls: Array[Vector2i] = entry.tiles("walls", state.region)
	var damage: Array[int] = entry.wholes("damage", 0, DataReader.MOST)
	var ticks: int = entry.whole("ticks", 0, DataReader.MOST)
	if entry.failed() or walls != seal.walls or damage.size() != walls.size():
		return "its walls aren't the ring's"
	seal.damage = damage
	seal.ticks = ticks
	if seal.failed_segment() >= 0 or ticks >= seal.seal_ticks:
		return "it has already broken or held"
	return ""


func hash_values() -> Array[int]:
	var values: Array[int] = [seals.size()]
	for catcher_id: int in _sealing_players():
		values.append(catcher_id)
		values.append_array(seals[catcher_id].hash_values())
	return values
