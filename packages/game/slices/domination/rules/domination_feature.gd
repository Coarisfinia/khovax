class_name DominationFeature
extends Feature
## Domination (#20) with sealing (#219): when the allies' shared trail (#87) closes a ring around
## wild monsters, they are encircled, and the ring waits for a totem (#423), as long as it takes:
## it never times out. A player placing their totem (a command) on any tile of it spends one of its
## charges (PlaceholderTotems), and the ring seals. It must hold for a while as every wild monster
## inside pushes on its nearest wall segment; if it holds, everything inside is dominated (a
## WildMonsterDominated event each says who dominated it), and if a segment gives way, the ring
## breaks and nothing is (a RingBroken event). Either way the ring comes off the trail, and every
## player colors the tile they stand on.
##
## The domination goes to the lowest slot among the players in the instance who colored the ring's
## wall (owner, #86, #87): allies close rings together, whoever's move closes it. A ring around
## several monsters hands them out by contribution instead (#260, DominationShares).
##
## Enclosed means the monster's tile can't reach the region's edge without crossing the trail: one
## flood fill from the edge over the region's tiles, whatever their terrain, so only the trail
## encloses. The ring's wall is the trail tiles next to the enclosed tiles around the monsters.
## Bigger rings spread the same ring power over more segments, so their walls are thinner.
##
## While a ring waits or seals, its dominator gets no other ring, the monsters inside stay where
## they stand (outside a ring, a wild monster moves only where no ring could enclose it, #364, or
## enraged, chasing a player, #961), and a monster in one ring can't be in another. Companions
## strike an encircled monster, weakening it, but leave a sealing one alone (#418), as its seal was
## worked out from its HP. Any player standing on a wall segment reinforces it (#227): a reinforced
## segment takes only a share of the pressure on it, which is strong, but it puts the player right
## where the monsters push.
##
## It runs after the trail has grown this tick, reads the trail and the wild monsters, and clears a
## ring off the trail through TrailFeature.clear: features later in the order change an earlier one
## only through its public methods.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "domination"

## Every sealing ring, by its dominator's entity id.
var seals: Dictionary[int, RingSeal] = {}
## Every ring waiting for a totem, as the wild monsters it encircles (in id order), by its
## dominator's entity id. Its wall is worked out when needed (ring_waiting), since the trail may
## grow inside it meanwhile.
var encircled: Dictionary[int, Array] = {}
## Every player's placeholder totem.
var totems: PlaceholderTotems = PlaceholderTotems.new()
## The edge of `_edge_region`, cached by _edge_of.
var _edge: Array[Vector2i] = []
var _edge_region: Region = null


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [TrailFeature.ID, HealthFeature.ID]
	return needed


## The wild monsters it encircles, which an instance without wild monster spots lacks (#884): no
## ring closes there.
func after() -> Array[String]:
	var earlier: Array[String] = [WildMonsterFeature.ID]
	return earlier


func step(state: GameState, commands: Array[Command]) -> void:
	# Rings sealing since an earlier tick push first, so a seal started this tick pushes next tick,
	# and a ring closed this tick waits at least until the next.
	for dominator_id: int in _sealing_players():
		_push(state, dominator_id)
	_place_totems(state, commands)
	_close_rings(state)


## Every player, in id order, whose command places their totem while they stand on a tile of a ring
## waiting for one, and who has a charge left, spends it, and that ring starts sealing. The
## domination still goes to the ring's dominator.
func _place_totems(state: GameState, commands: Array[Command]) -> void:
	if encircled.is_empty():
		return
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	for entity: Entity in state.entities:
		var command: Command = Command.of(commands, entity.slot)
		if command == null or command.totem != Command.PLACE_TOTEM:
			continue
		if not can_place_totem(state, entity.id):
			continue
		var dominator_id: int = _waiting_under(state, entity.tile)
		var _spent: bool = totems.spend(entity.id)
		var inside: Array[int] = []
		inside.assign(encircled[dominator_id])
		var _dropped: bool = encircled.erase(dominator_id)
		seals[dominator_id] = RingSealing.build(state, trail, inside)


## Whether the player `player_id` placing their totem now would seal a ring (#931, the totem's
## button asks this too): they have a charge left and stand on a tile of a ring waiting for a totem,
## theirs or anyone else's.
func can_place_totem(state: GameState, player_id: int) -> bool:
	var player: Entity = state.entity(player_id)
	if player == null or totems.charges_of(player_id) == 0:
		return false
	return _waiting_under(state, player.tile) != 0


## The dominator, lowest id first, whose ring waiting for a totem has a tile on `tile`, or 0.
func _waiting_under(state: GameState, tile: Vector2i) -> int:
	for dominator_id: int in _waiting_players():
		if ring_waiting(state, dominator_id).has(tile):
			return dominator_id
	return 0


## The wall of the ring waiting for a totem of the dominator `dominator_id`: the trail tiles next to
## the tiles it encircles.
func ring_waiting(state: GameState, dominator_id: int) -> Array[Vector2i]:
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	return RingShape.wall_around(state.region, trail, _spots(state, encircled[dominator_id]))


## Every new ring closed this tick around wild monsters in no ring yet waits for a totem, unless its
## dominator has a ring waiting or sealing already. A ring can only close when the trail grows, so
## rings are checked per new trail tile, in entity id order of who moved, whatever order the moves
## were raised in. This relies on no wild monster stepping into a ring after it closed: one that
## moves (#364) never steps onto the trail, and a ring's inside only borders the outside through its
## trail.
func _close_rings(state: GameState) -> void:
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for grew: TrailGrew in _grown(state):
		if wild == null or wild.monsters.is_empty() or not RingShape.may_close(trail, grew):
			continue
		# One flood per move, for every monster at once (#104).
		var edge: Array[Vector2i] = _edge_of(state.region)
		var reachable: Dictionary[Vector2i, bool] = RingShape.outside(state.region, trail, edge)
		var inside: Array[int] = []
		for monster_id: int in wild.monsters:
			var spot: Vector2i = state.entity(monster_id).tile
			if not trail.tiles.has(spot) and not reachable.has(spot) and not _in_ring(monster_id):
				inside.append(monster_id)
		if inside.is_empty():
			continue
		var walls: Array[Vector2i] = RingShape.wall_around(
			state.region,
			trail,
			_spots(state, inside),
		)
		var dominator_id: int = dominator_of(state, trail, walls)
		if dominator_id > 0 and not seals.has(dominator_id) and not encircled.has(dominator_id):
			encircled[dominator_id] = inside


## The tiles the entities `ids` stand on, in the same order.
static func _spots(state: GameState, ids: Array) -> Array[Vector2i]:
	var spots: Array[Vector2i] = []
	for each: int in ids:
		spots.append(state.entity(each).tile)
	return spots


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
		var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
		takers = DominationShares.hand_out(
			seal.monsters,
			DominationShares.contributions(state, trail, seal),
		)
	for monster_id: int in seal.monsters:
		if not takers.has(monster_id):
			takers[monster_id] = dominator_id
	return takers


## Ends the dominator's seal, held or broken: its ring comes off the trail (#87), but not the wall
## tiles another ring still sealing or waiting for a totem needs.
func _end(state: GameState, dominator_id: int) -> void:
	var walls: Array[Vector2i] = seals[dominator_id].walls
	var _dropped: bool = seals.erase(dominator_id)
	_clear_ring(state, walls)


## Takes the `walls` of a ring that ended off the trail, but not the tiles another ring sealing or
## waiting for a totem needs.
func _clear_ring(state: GameState, walls: Array[Vector2i]) -> void:
	var needed: Dictionary[Vector2i, bool] = ring_walls(state)
	var cleared: Array[Vector2i] = []
	for wall: Vector2i in walls:
		if not needed.has(wall):
			cleared.append(wall)
	(state.feature(TrailFeature.ID) as TrailFeature).clear(state, cleared)


## The players whose rings are sealing, in id order.
func _sealing_players() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(seals.keys())
	ids.sort()
	return ids


## The players whose rings wait for a totem, in id order.
func _waiting_players() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(encircled.keys())
	ids.sort()
	return ids


## Whether the wild monster with this id is sealing in a ring.
func is_sealed(monster_id: int) -> bool:
	for seal: RingSeal in seals.values():
		if seal.monsters.has(monster_id):
			return true
	return false


## Every wall segment of a ring sealing or waiting for a totem: only the wild monsters inside it
## attack it (#422). Waiting rings' walls are worked out here, so callers ask once per tick.
func ring_walls(state: GameState) -> Dictionary[Vector2i, bool]:
	var walls: Dictionary[Vector2i, bool] = {}
	for seal: RingSeal in seals.values():
		for wall: Vector2i in seal.walls:
			walls[wall] = true
	for waiting_id: int in _waiting_players():
		for wall: Vector2i in ring_waiting(state, waiting_id):
			walls[wall] = true
	return walls


## The entity id of the dominator whose ring waiting for a totem encircles the wild monster with
## this id, or 0.
func waiting_dominator(monster_id: int) -> int:
	for waiting_id: int in _waiting_players():
		if encircled[waiting_id].has(monster_id):
			return waiting_id
	return 0


## The wall segment the wild monster `monster_id` pushes on in the ring of `dominator_id` (#937):
## its seal's segment while that ring seals, else the segment of that waiting ring nearest to it,
## which it strikes (#422), else its own tile. The one rule for it, which WildAttackFeature and the
## spikes' look (SpikesHitView) both ask.
func wall_pushed_by(state: GameState, monster_id: int, dominator_id: int) -> Vector2i:
	var monster: Entity = state.entity(monster_id)
	var seal: RingSeal = seals.get(dominator_id)
	var index: int = seal.monsters.find(monster_id) if seal != null else -1
	if index >= 0:
		return seal.walls[seal.targets[index]]
	if encircled.has(dominator_id):
		var walls: Array[Vector2i] = ring_waiting(state, dominator_id)
		if not walls.is_empty():
			return walls[RingShape.nearest(walls, monster.tile)]
	return monster.tile


## Breaks the ring of `dominator_id` waiting for a totem, its segment `wall` worn through by the
## wild monsters inside (#422, WildAttackFeature): a RingBroken event, as when a seal breaks (so
## EnrageFeature enrages them), and the ring comes off the trail. A waiting ring breaks no other
## way.
func break_waiting(state: GameState, dominator_id: int, wall: Vector2i) -> void:
	var walls: Array[Vector2i] = ring_waiting(state, dominator_id)
	var inside: Array[int] = []
	inside.assign(encircled[dominator_id])
	var _dropped: bool = encircled.erase(dominator_id)
	var slot: int = state.entity(dominator_id).slot
	state.events.append(RingBroken.new(dominator_id, slot, wall, walls, inside))
	_clear_ring(state, walls)


## Whether the wild monster with this id is encircled by a ring waiting for a totem.
func is_encircled(monster_id: int) -> bool:
	for inside: Array in encircled.values():
		if inside.has(monster_id):
			return true
	return false


func _in_ring(monster_id: int) -> bool:
	return is_sealed(monster_id) or is_encircled(monster_id)


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
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var species: String = wild.species_of(monster_id)
	var short_id: String = wild.short_id_of(monster_id)
	var target: String = wild.target_of(monster_id)
	var slot: int = state.entity(dominator_id).slot
	state.remove_entity(monster_id)
	var dominated: WildMonsterDominated = WildMonsterDominated.new(
		monster_id,
		dominator_id,
		slot,
		tile,
		species,
	)
	dominated.short_id = short_id
	dominated.target = target
	DominationShares.add_contributions(state, seal, dominated)
	state.events.append(dominated)


## A player arriving holds a placeholder totem.
func entity_added(_state: GameState, added: Entity) -> void:
	if added.slot != Entity.NO_SLOT:
		totems.add(added.id)


## A player who leaves the instance takes their seal, their waiting ring and their totem with them;
## a wild monster that leaves it pushes no more, and a ring left encircling nothing waits no more.
func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = seals.erase(removed_id)
	_dropped = encircled.erase(removed_id)
	totems.drop(removed_id)
	for seal: RingSeal in seals.values():
		seal.drop(removed_id)
	for waiting_id: int in _waiting_players():
		encircled[waiting_id].erase(removed_id)
		if encircled[waiting_id].is_empty():
			_dropped = encircled.erase(waiting_id)


## Every sealing ring as its player's entity id and its seal, in id order.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for dominator_id: int in _sealing_players():
		var entry: Dictionary = seals[dominator_id].to_data()
		entry["dominator"] = dominator_id
		saved.append(entry)
	var waiting: Array[Dictionary] = []
	for dominator_id: int in _waiting_players():
		var inside: Array = encircled[dominator_id].duplicate()
		waiting.append({ "dominator": dominator_id, "monsters": inside })
	return { "seals": saved, "waiting": waiting, "totems": totems.flat() }


## Restores each seal by building it again from the restored trail and monsters, with the same
## code that builds a new one, and taking only its damage and ticks from the save. A save whose
## walls differ from the rebuilt ones, or that names a monster twice, in two seals or outside the
## ring, is refused.
func load_values(state: GameState, values: DataReader) -> void:
	seals.clear()
	for entry: DataReader in values.entries("seals"):
		var dominator_id: int = entry.whole("dominator", 1, DataReader.MOST)
		var dominator: Entity = state.entity(dominator_id)
		if dominator == null or dominator.slot == Entity.NO_SLOT or seals.has(dominator_id):
			values.fail("sealing ring of %d isn't one player's" % dominator_id)
			return
		var monsters: Array[int] = entry.wholes("monsters", 1, DataReader.MOST)
		var problem: String = _monsters_problem(state, monsters)
		if not problem.is_empty():
			values.fail("sealing ring of %d: %s" % [dominator_id, problem])
			return
		var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
		var seal: RingSeal = RingSealing.build(state, trail, monsters)
		if dominator_of(state, trail, seal.walls) != dominator_id:
			values.fail("sealing ring of %d: its domination goes to someone else" % dominator_id)
			return
		problem = _progress_problem(state, seal, entry)
		if not problem.is_empty():
			values.fail("sealing ring of %d: %s" % [dominator_id, problem])
			return
		seals[dominator_id] = seal
	_load_waiting(state, values)
	var refused: String = totems.load_flat(state, values.pairs("totems", 0, DataReader.MOST))
	if not refused.is_empty():
		values.fail(refused)


## Restores the rings waiting for a totem, each checked like a seal: its dominator a player with no
## other ring, its monsters in no other ring and enclosed, and its domination still theirs.
func _load_waiting(state: GameState, values: DataReader) -> void:
	encircled.clear()
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	for entry: DataReader in values.entries("waiting"):
		var dominator_id: int = entry.whole("dominator", 1, DataReader.MOST)
		var dominator: Entity = state.entity(dominator_id)
		var taken: bool = seals.has(dominator_id) or encircled.has(dominator_id)
		if dominator == null or dominator.slot == Entity.NO_SLOT or taken:
			values.fail("waiting ring of %d isn't one player's only ring" % dominator_id)
			return
		var monsters: Array[int] = entry.wholes("monsters", 1, DataReader.MOST)
		var problem: String = _monsters_problem(state, monsters)
		if not problem.is_empty():
			values.fail("waiting ring of %d: %s" % [dominator_id, problem])
			return
		var walls: Array[Vector2i] = RingShape.wall_around(
			state.region,
			trail,
			_spots(state, monsters),
		)
		if dominator_of(state, trail, walls) != dominator_id:
			values.fail("waiting ring of %d: its domination goes to someone else" % dominator_id)
			return
		encircled[dominator_id] = monsters


## Why the saved monsters can't be in the ring, or "": they must be wild monsters, in increasing id
## order (so none twice), in no other ring, and enclosed by the trail.
func _monsters_problem(state: GameState, monsters: Array[int]) -> String:
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if monsters.is_empty() or wild == null:
		return "it has no wild monsters"
	var edge: Array[Vector2i] = _edge_of(state.region)
	var reachable: Dictionary[Vector2i, bool] = RingShape.outside(state.region, trail, edge)
	for i: int in monsters.size():
		var monster_id: int = monsters[i]
		if i > 0 and monster_id <= monsters[i - 1]:
			return "its monsters are out of order or there twice"
		if not wild.monsters.has(monster_id) or _in_ring(monster_id):
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
	var braced: Dictionary[int, int] = entry.pairs("braced", 0, DataReader.MOST)
	var braced_walls: Array[int] = entry.wholes("braced_walls", -DataReader.MOST, DataReader.MOST)
	if entry.failed() or walls != seal.walls or damage.size() != walls.size():
		return "its walls aren't the ring's"
	if braced_walls.size() % 3 != 0:
		return "its braced segments aren't a player and a tile"
	seal.damage = damage
	seal.ticks = ticks
	seal.braced = braced
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
	values.append(encircled.size())
	for dominator_id: int in _waiting_players():
		values.append_array([dominator_id, encircled[dominator_id].size()])
		values.append_array(encircled[dominator_id])
	var charges: Array[int] = totems.flat()
	values.append(charges.size())
	values.append_array(charges)
	return values
