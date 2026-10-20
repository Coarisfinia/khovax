class_name WildAttackFeature
extends Feature
## Wild monsters attack (#422, owner on #421): every wild monster strikes once every STRIKE_TICKS,
## all on the same tick, for its strength (rage included), its species' own attack (#228). Rage
## makes it strike sooner (#961, WildMonsterFeature.paced): the enraged ones strike on the ticks of
## their own pace.
## Each hit raises WildMonsterStruck. Hidden in its tile (#202), it doesn't attack: it keeps out
## of sight.
##
## Free, it strikes something next to it, in this order: a companion (#338), then a player (not one
## a dialog holds, whom HealthFeature shields, #981), the player first when it's enraged (#220,
## #961), then a
## tile of the allies' trail (#87), the lowest id or the first tile in sorted order among each. A
## trail tile wears down: once it has taken TILE_INTEGRITY, it gives way and comes off the trail
## (TrailFeature.clear), so a ring drawn beside a wild monster must close before it breaks open.
## A hit on a companion or a player comes off their HP at once (HealthFeature.hurt, #455); one on
## a companion follows the type chart where the instance has it (TypeEffectivenessFeature, #626).
##
## Encircled, it attacks only its ring: in a ring waiting for a totem (#423), it strikes the wall
## segment nearest to it, wherever that is, and once a segment is worn through, the ring breaks
## (DominationFeature.break_waiting); sealing, its seal's pushes are its attacks (#219), so it
## isn't attacking here. Those are the only ways a ring breaks: nobody else's attack lands on a
## ring's wall.
##
## It runs right after domination, which it breaks waiting rings through, and before enrage, which
## enrages the wild monsters of a ring that broke this tick. So it strikes companions where they
## stood at the end of the last tick, as they step later.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "wild_attacks"
## The ticks between two strikes of one wild monster, and how much a trail tile takes before it
## gives way. Placeholders to tune (#960).
const STRIKE_TICKS: int = Simulation.TICKS_PER_SECOND
const TILE_INTEGRITY: int = 400

## The damage each trail tile has taken, by tile; one never hit isn't here.
var _wear: Dictionary[Vector2i, int] = {}
## The trail's feature, which the wear is read against (set in `start`).
var _trail: TrailFeature = null
## Worked out again each tick, so neither hashed nor saved: the lowest id of a companion and of a
## player on each tile, and every ring's wall (only once a free monster may strike the trail).
var _companion_at: Dictionary[Vector2i, int] = {}
var _player_at: Dictionary[Vector2i, int] = {}
var _ring_walls: Dictionary[Vector2i, bool] = {}
var _ring_walls_found: bool = false


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [
		TrailFeature.ID,
		HealthFeature.ID,
		DominationFeature.ID,
	]
	return needed


## The wild monsters that strike, which an instance without wild monster spots lacks (#884): nothing
## strikes there.
func after() -> Array[String]:
	var earlier: Array[String] = [WildMonsterFeature.ID]
	return earlier


## Hiding, the companions and the type chart, which an instance may lack, step later: a wild
## monster strikes from where they stood at the end of the last tick.
func before() -> Array[String]:
	var later: Array[String] = [
		HidingFeature.ID,
		CompanionFeature.ID,
		TypeEffectivenessFeature.ID,
	]
	return later


func start(state: GameState) -> void:
	_trail = state.feature(TrailFeature.ID) as TrailFeature


## Lets every wild monster strike, in id order, once every STRIKE_TICKS. Wear on tiles that left
## the trail (a ring that ended) is forgotten first. The features are looked up once: looking one
## up goes through them all.
func step(state: GameState, _commands: Array[Command]) -> void:
	var trail: TrailFeature = state.feature(TrailFeature.ID) as TrailFeature
	# Erasing needs no order, so the keys aren't sorted.
	for tile: Vector2i in _wear.keys():
		if not trail.shared.tiles.has(tile):
			var _dropped: bool = _wear.erase(tile)
	if not _anyone_strikes(state.tick):
		return
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var monsters: Array[Entity] = _find_standing(state, wild, health)
	var near: Dictionary[Vector2i, bool] = _near_targets(trail)
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	# Hiding steps later (`before`), so a wild monster that jumps out this tick strikes from the
	# next strike on.
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	_ring_walls_found = false
	for monster: Entity in monsters:
		var dominator_id: int = 0
		if not domination.encircled.is_empty():
			dominator_id = domination.waiting_dominator(monster.id)
		if dominator_id == 0 and not near.has(monster.tile):
			continue
		if hiding != null and hiding.is_hidden(monster.id):
			continue
		var damage: int = wild.strength_of(monster.id)
		if dominator_id > 0:
			_strike_ring(state, monster, dominator_id, damage)
		elif not domination.is_sealed(monster.id):
			_strike(state, monster, damage, wild.rage_of(monster.id) > 0)


## Whether a wild monster of any rage strikes on `tick`: on most ticks none does.
static func _anyone_strikes(tick: int) -> bool:
	for rage: int in WildMonsterFeature.MOST_RAGE + 1:
		if _strikes_now(tick, rage):
			return true
	return false


## Whether a wild monster with `rage` stacks of rage strikes on `tick`: once every STRIKE_TICKS,
## paced by its rage (#961).
static func _strikes_now(tick: int, rage: int) -> bool:
	return tick % WildMonsterFeature.paced(STRIKE_TICKS, rage) == 0


## Finds, in one pass over the entities, which companion and which player stands on each tile,
## the one with the lowest id where several do, and returns the wild monsters that strike this tick
## by their pace, in id order. A
## shielded player isn't a target (#981). Companions aren't required, since an instance may have
## none.
func _find_standing(
	state: GameState,
	wild: WildMonsterFeature,
	health: HealthFeature,
) -> Array[Entity]:
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	_companion_at.clear()
	_player_at.clear()
	var monsters: Array[Entity] = []
	# Both lists are in id order, so the wild monsters are matched in step, not searched for.
	var next: int = 0
	for entity: Entity in state.entities:
		while next < wild.monsters.size() and wild.monsters[next] < entity.id:
			next += 1
		if next < wild.monsters.size() and wild.monsters[next] == entity.id:
			if _strikes_now(state.tick, wild.rage_of(entity.id)):
				monsters.append(entity)
		elif entity.slot != Entity.NO_SLOT:
			if not _player_at.has(entity.tile) and not health.is_shielded(entity.id):
				_player_at[entity.tile] = entity.id
		elif companions != null and companions.owners.has(entity.id):
			if not _companion_at.has(entity.tile):
				_companion_at[entity.tile] = entity.id
	return monsters


## Every tile next to a companion, a player or a trail tile: a wild monster elsewhere has nothing
## to strike unless it's encircled, and most have nothing.
func _near_targets(trail: TrailFeature) -> Dictionary[Vector2i, bool]:
	var near: Dictionary[Vector2i, bool] = {}
	var targets: Array[Vector2i] = []
	targets.assign(trail.shared.tiles.keys())
	targets.append_array(_companion_at.keys())
	targets.append_array(_player_at.keys())
	for target: Vector2i in targets:
		for direction: Vector2i in Hex.DIRECTIONS:
			near[target + direction] = true
	return near


## The encircled wild monster strikes the wall segment of its waiting ring nearest to it; worn
## through, the segment breaks the ring and comes off the trail.
func _strike_ring(state: GameState, monster: Entity, dominator_id: int, damage: int) -> void:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	var walls: Array[Vector2i] = domination.ring_waiting(state, dominator_id)
	var wall: Vector2i = walls[RingShape.nearest(walls, monster.tile)]
	state.events.append(WildMonsterStruck.new(monster.id, 0, wall, damage))
	if _worn_through(wall, damage):
		# The ring comes off the trail, but a wall another ring needs stays, so it's left to it.
		var _dropped: bool = _wear.erase(wall)
		domination.break_waiting(state, dominator_id, wall)


## The free wild monster strikes the first target next to it, if there is one: the companion with
## the lowest id, else the player with the lowest id (the other way round when it's `enraged`), else
## a trail tile that's no ring's wall.
func _strike(state: GameState, monster: Entity, damage: int, enraged: bool) -> void:
	var tile: Vector2i = monster.tile
	var on_companion: bool = not enraged
	var side: Vector2i = _lowest_beside(_companion_at if on_companion else _player_at, tile)
	if side == tile:
		on_companion = not on_companion
		side = _lowest_beside(_companion_at if on_companion else _player_at, tile)
	if side != tile:
		var target_id: int = _companion_at[side] if on_companion else _player_at[side]
		var struck: WildMonsterStruck = WildMonsterStruck.new(monster.id, target_id, side, damage)
		if on_companion:
			struck = _on_companion(state, struck)
		state.events.append(struck)
		var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
		var _fell: bool = health.hurt(state, target_id, struck.damage)
		return
	side = _trail_target(state, tile)
	if side == tile:
		return
	state.events.append(WildMonsterStruck.new(monster.id, 0, side, damage))
	if _worn_through(side, damage):
		_clear(state, side)


## The wild monster's strike `struck` on a companion, after the type chart where the instance has
## it (#626): its damage scaled, and which of the companion's types it was strong against (#764).
## Companions are present, since one stands there.
static func _on_companion(state: GameState, struck: WildMonsterStruck) -> WildMonsterStruck:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var companions: CompanionFeature = state.feature(CompanionFeature.ID) as CompanionFeature
	var attacker: String = wild.species_of(struck.monster_id)
	var defender: String = companions.species_of(struck.target_id)
	return WildMonsterStruck.new(
		struck.monster_id,
		struck.target_id,
		struck.tile,
		TypeEffectivenessFeature.scaled(state, struck.damage, attacker, false, defender),
		TypeEffectivenessFeature.strong_against(state, attacker, false, defender),
	)


## Adds `damage` to the wear on the trail tile `tile`; whether it's worn through now.
func _worn_through(tile: Vector2i, damage: int) -> bool:
	_wear[tile] = _wear.get(tile, 0) + damage
	return _wear[tile] >= TILE_INTEGRITY


## Takes the worn-through `tile` off the trail.
func _clear(state: GameState, tile: Vector2i) -> void:
	var _dropped: bool = _wear.erase(tile)
	var cleared: Array[Vector2i] = [tile]
	(state.feature(TrailFeature.ID) as TrailFeature).clear(state, cleared)


## The tile next to `tile` whose entity in `at` has the lowest id, or `tile` itself when none
## of them stands next to it.
static func _lowest_beside(at: Dictionary[Vector2i, int], tile: Vector2i) -> Vector2i:
	var best: Vector2i = tile
	for direction: Vector2i in Hex.DIRECTIONS:
		var side: Vector2i = tile + direction
		if at.has(side) and (best == tile or at[side] < at[best]):
			best = side
	return best


## The first trail tile next to `tile`, in sorted order, that is no ring's wall, or `tile` itself
## when there is none: a wild monster never stands on the trail.
func _trail_target(state: GameState, tile: Vector2i) -> Vector2i:
	var trail: TrailFeature = state.feature(TrailFeature.ID) as TrailFeature
	for side: Vector2i in _sides(tile):
		if trail.shared.tiles.has(side) and not _is_ring_wall(state, side):
			return side
	return tile


## Whether `tile` is a wall segment of a ring, waiting or sealing; the walls are worked out once a
## tick, when first asked.
func _is_ring_wall(state: GameState, tile: Vector2i) -> bool:
	if not _ring_walls_found:
		var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
		_ring_walls = domination.ring_walls(state)
		_ring_walls_found = true
	return _ring_walls.has(tile)


## The tiles next to `tile`, sorted.
static func _sides(tile: Vector2i) -> Array[Vector2i]:
	var sides: Array[Vector2i] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		sides.append(tile + direction)
	sides.sort()
	return sides


## The worn tiles still on the trail, sorted: a tile a ring took off the trail since the last step
## keeps its entry until the next, but its wear counts no more.
func _worn_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for tile: Vector2i in _wear:
		if _trail.shared.tiles.has(tile):
			tiles.append(tile)
	tiles.sort()
	return tiles


func hash_values() -> Array[int]:
	var tiles: Array[Vector2i] = _worn_tiles()
	var values: Array[int] = [tiles.size()]
	for tile: Vector2i in tiles:
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
	for i: int in tiles.size():
		if not _trail.shared.tiles.has(tiles[i]) or _wear.has(tiles[i]):
			values.fail("worn tile %s isn't on the trail once" % tiles[i])
			return
		_wear[tiles[i]] = wear[i]
