class_name DominationFeature
extends Feature
## Domination (#20) with sealing (#219): when the allies' shared trail (#87) closes a ring around
## wild monsters, the ring seals. It must hold for a while as every wild monster inside pushes on
## its nearest wall segment; if it holds, everything inside is dominated (a WildMonsterDominated
## event each says who dominated it), and if a segment gives way, the ring breaks and nothing is (a
## RingBroken event). Either way the ring comes off the trail, and every player colors the tile they
## stand on.
##
## The domination goes to the lowest slot among the players in the instance who colored the ring's
## wall (owner, #86, #87): allies close rings together, whoever's move closes it. Splitting a
## domination by contribution is #86 and #260.
##
## Enclosed means the monster's tile can't reach the region's edge without crossing the trail: one
## flood fill from the edge over the region's tiles, whatever their terrain, so only the trail
## encloses. The ring's wall is the trail tiles next to the enclosed tiles around the monsters.
## Bigger rings spread the same ring power over more segments, so their walls are thinner.
##
## While a ring seals, its dominator gets no other ring, the monsters inside stay where they stand
## (a wild monster only moves where no ring could enclose it, #364), and a monster sealed in one
## ring
## can't be sealed in another. Any
## player standing on a wall segment reinforces it (#227): a reinforced segment takes only a share
## of the pressure on it, which is strong, but it puts the player right where the monsters push.
##
## It runs after the trail has grown this tick, reads the trail and the wild monsters, and clears a
## ring off the trail through TrailFeature.clear: features later in the order change an earlier one
## only through its public methods.

## Every sealing ring, by its dominator's entity id.
var seals: Dictionary[int, RingSeal] = {}
## The edge of `_edge_region`, cached by _edge_of.
var _edge: Array[Vector2i] = []
var _edge_region: Region = null


func id() -> int:
	return Features.DOMINATION


func requires() -> Array[int]:
	var needed: Array[int] = [Features.TRAIL, Features.WILD_MONSTERS]
	return needed


func step(state: GameState, _commands: Array[Command]) -> void:
	# Rings sealing since an earlier tick push first, so a ring closed this tick starts next tick.
	for dominator_id: int in _sealing_players():
		_push(state, dominator_id)
	_close_rings(state)


## Every new ring closed this tick around wild monsters not sealing yet starts sealing, unless its
## dominator has a ring sealing already. A ring can only close when the trail grows, so rings are
## checked per new trail tile, in entity id order of who moved, whatever order the moves were raised
## in. This relies on no wild monster stepping into a ring after it closed: one that moves (#364)
## never steps onto the trail, and a ring's inside only borders the outside through its trail.
func _close_rings(state: GameState) -> void:
	var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	for grew: TrailGrew in _grown(state):
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
		if inside.is_empty():
			continue
		var seal: RingSeal = RingSealing.build(state, trail, inside)
		var dominator_id: int = dominator_of(state, trail, seal.walls)
		if dominator_id > 0 and not seals.has(dominator_id):
			seals[dominator_id] = seal


## Who a ring's domination goes to: of the players in the instance who colored a tile of its
## `walls`, the one in the lowest slot (owner, #86), as their entity id; 0 when none of them is here
## any more.
static func dominator_of(state: GameState, trail: Trail, walls: Array[Vector2i]) -> int:
	var best: Entity = null
	for wall: Vector2i in walls:
		var colorer_id: int = trail.tiles.get(wall, 0)
		var colorer: Entity = state.entity(colorer_id)
		var player: bool = colorer != null and colorer.slot != Entity.NO_SLOT
		if player and (best == null or colorer.slot < best.slot):
			best = colorer
	return best.id if best != null else 0


## The tick's TrailGrew events in entity id order, whatever order they were raised in: who seals a
## monster two players ring in the same tick never depends on the order of the events.
static func _grown(state: GameState) -> Array[TrailGrew]:
	var grown: Array[TrailGrew] = []
	for event: RefCounted in state.events:
		if event is TrailGrew:
			grown.append(event as TrailGrew)
	grown.sort_custom(func(a: TrailGrew, b: TrailGrew) -> bool: return a.entity_id < b.entity_id)
	return grown


## One tick of the dominator's seal (RingSealing.push): a segment whose damage reaches its integrity
## breaks the ring; a ring that holds for its seal ticks dominates everything inside.
func _push(state: GameState, dominator_id: int) -> void:
	var seal: RingSeal = seals[dominator_id]
	RingSealing.push(state, seal)
	var failed: int = seal.failed_segment()
	if failed >= 0:
		var slot: int = state.entity(dominator_id).slot
		var walls: Array[Vector2i] = seal.walls
		var broken: RingBroken = RingBroken.new(
			dominator_id,
			slot,
			walls[failed],
			walls,
			seal.monsters,
		)
		state.events.append(broken)
		_end(state, dominator_id)
	elif seal.ticks >= seal.seal_ticks:
		var takers: Dictionary[int, int] = _takers(state, dominator_id, seal)
		for monster_id: int in seal.monsters.duplicate():
			_dominate(state, monster_id, takers[monster_id], seal)
		_end(state, dominator_id)


## Who gets each wild monster of a held ring, by monster id: its dominator when it holds one; split
## by contribution when it holds several (#260, DominationShares), the dominator taking any nobody
## earned.
func _takers(state: GameState, dominator_id: int, seal: RingSeal) -> Dictionary[int, int]:
	var takers: Dictionary[int, int] = {}
	if seal.monsters.size() > 1:
		var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
		takers = DominationShares.hand_out(
			seal.monsters,
			DominationShares.contributions(state, trail, seal),
		)
	for monster_id: int in seal.monsters:
		if not takers.has(monster_id):
			takers[monster_id] = dominator_id
	return takers


## Ends the dominator's seal, held or broken: its ring comes off the trail (#87), but not the wall
## tiles another ring still sealing needs.
func _end(state: GameState, dominator_id: int) -> void:
	var walls: Array[Vector2i] = seals[dominator_id].walls
	var _dropped: bool = seals.erase(dominator_id)
	var cleared: Array[Vector2i] = []
	for wall: Vector2i in walls:
		var needed: bool = false
		for other: RingSeal in seals.values():
			needed = needed or other.walls.has(wall)
		if not needed:
			cleared.append(wall)
	(state.feature(Features.TRAIL) as TrailFeature).clear(state, cleared)


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


func _dominate(state: GameState, monster_id: int, dominator_id: int, seal: RingSeal) -> void:
	var tile: Vector2i = state.entity(monster_id).tile
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	var species: String = wild.species_of(monster_id)
	var slot: int = state.entity(dominator_id).slot
	state.remove_entity(monster_id)
	var dominated: WildMonsterDominated = WildMonsterDominated.new(
		monster_id,
		dominator_id,
		slot,
		tile,
		species,
	)
	DominationShares.add_contributions(state, seal, dominated)
	state.events.append(dominated)


## A player who leaves the instance takes their seal with them, unfinished; a wild monster that
## leaves it pushes no more.
func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = seals.erase(removed_id)
	for seal: RingSeal in seals.values():
		seal.drop(removed_id)


## Every sealing ring as its player's entity id and its seal, in id order. The id's key keeps its
## name from before domination (#317), "catcher", so saved worlds keep loading.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for dominator_id: int in _sealing_players():
		var entry: Dictionary = seals[dominator_id].to_data()
		entry["catcher"] = dominator_id
		saved.append(entry)
	return { "seals": saved }


## Restores each seal by building it again from the restored trail and monsters, with the same
## code that builds a new one, and taking only its damage and ticks from the save. A save whose
## walls differ from the rebuilt ones, or that names a monster twice, in two seals or outside the
## ring, is refused.
func load_values(state: GameState, values: DataReader) -> void:
	seals.clear()
	for entry: DataReader in values.entries("seals"):
		var dominator_id: int = entry.whole("catcher", 1, DataReader.MOST)
		var dominator: Entity = state.entity(dominator_id)
		if dominator == null or dominator.slot == Entity.NO_SLOT or seals.has(dominator_id):
			values.fail("sealing ring of %d isn't one player's" % dominator_id)
			return
		var monsters: Array[int] = entry.wholes("monsters", 1, DataReader.MOST)
		var problem: String = _monsters_problem(state, monsters)
		if not problem.is_empty():
			values.fail("sealing ring of %d: %s" % [dominator_id, problem])
			return
		var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
		var seal: RingSeal = RingSealing.build(state, trail, monsters)
		if dominator_of(state, trail, seal.walls) != dominator_id:
			values.fail("sealing ring of %d: its domination goes to someone else" % dominator_id)
			return
		problem = _progress_problem(state, seal, entry)
		if not problem.is_empty():
			values.fail("sealing ring of %d: %s" % [dominator_id, problem])
			return
		seals[dominator_id] = seal


## Why the saved monsters can't be sealing in the ring, or "": they must be wild monsters, in
## increasing id order (so none twice), in no other seal, and enclosed by the trail.
func _monsters_problem(state: GameState, monsters: Array[int]) -> String:
	var trail: Trail = (state.feature(Features.TRAIL) as TrailFeature).shared
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	if monsters.is_empty():
		return "it has no wild monsters"
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
	var braced: Array[int] = entry.wholes("braced", 0, DataReader.MOST)
	var braced_walls: Array[int] = entry.wholes("braced_walls", -DataReader.MOST, DataReader.MOST)
	if entry.failed() or walls != seal.walls or damage.size() != walls.size():
		return "its walls aren't the ring's"
	if braced.size() % 2 != 0 or braced_walls.size() % 3 != 0:
		return "its braced ticks or segments aren't a player and ticks, or a player and a tile"
	seal.damage = damage
	seal.ticks = ticks
	for i: int in range(0, braced.size(), 2):
		seal.braced[braced[i]] = braced[i + 1]
	for i: int in range(0, braced_walls.size(), 3):
		var wall: Vector2i = Vector2i(braced_walls[i + 1], braced_walls[i + 2])
		if not seal.walls.has(wall):
			return "a segment it says was braced isn't one of its walls"
		var walls_stood_on: Array = seal.braced_walls.get(braced_walls[i], [])
		walls_stood_on.append(wall)
		seal.braced_walls[braced_walls[i]] = walls_stood_on
	if seal.failed_segment() >= 0 or ticks >= seal.seal_ticks:
		return "it has already broken or held"
	return ""


func hash_values() -> Array[int]:
	var values: Array[int] = [seals.size()]
	for dominator_id: int in _sealing_players():
		values.append(dominator_id)
		values.append_array(seals[dominator_id].hash_values())
	return values
