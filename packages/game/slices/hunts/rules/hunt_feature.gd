class_name HuntFeature
extends Feature
## Predators hunt (#1204, owner's ground rule, #1199): in the hunt hours of its day
## (ScheduleFeature), a wild monster of a `predator` species roams around its home, the tile it
## stood on when the instance began, up to ROAM_RADIUS from it, a random step at a time at its
## pace (WildMonsterFeature.chase). On sighting prey within SIGHT, a standing wild monster weaker
## than itself (WildMonsterFeature.strength_of) or of a `grazer` species, it stalks it, a step at
## a time, and next to it attacks it by the wild monsters' rules: a strike for its strength once
## every WildAttackFeature.STRIKE_TICKS, never lethal, so it never takes the prey below 1 HP
## (WildMonsterFeature.wound, which wakes a sleeping one). A tick it strikes a player, a companion
## or the trail (WildAttackFeature, earlier), it doesn't strike its prey too.
##
## The hunt ends one of two ways, and the hunter rests until its next hunt hours: it wins once
## its prey is down to 1 HP, or it gives up after GIVE_UP_TICKS stalking the same prey. Prey that
## gets out of sight is lost, and the hunter roams on. Prey down to 1 HP, held (hidden or bound,
## WildMonsterFeature.held) or in a ring is no prey; sleeping prey is. An enraged hunter goes for
## the players instead (EnrageFeature, which steps earlier); a sleeping, held or ringed one doesn't
## hunt.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "hunts"
## How far a hunter sees prey, how far from its home it roams, and how long it stalks one prey
## before it gives up. Placeholders to tune (#960).
const SIGHT: int = 4
const ROAM_RADIUS: int = 4
const GIVE_UP_TICKS: int = 20 * Simulation.TICKS_PER_SECOND

## Each hunter's home, by entity id: where it stood when the instance began. A hunter is a wild
## monster of a `predator` species.
var homes: Dictionary[int, Vector2i] = {}
## The prey each hunter stalks now, by the hunter's entity id, and the tick it sighted it.
var prey: Dictionary[int, int] = {}
var _sighted: Dictionary[int, int] = {}
## The hunters whose hunt ended, won or given up, in id order: they rest until their hunt hours
## are over.
var rested: Array[int] = []
var _rng: Rng


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, ScheduleFeature.ID, HealthFeature.ID]
	return needed


## Domination, whose rings hold their monsters, which an instance may lack.
func after() -> Array[String]:
	var earlier: Array[String] = [DominationFeature.ID]
	return earlier


## Every standing wild monster of a predator species is a hunter, at home where it stands.
func start(state: GameState) -> void:
	_rng = Rng.new(state.rng_seed, stream())
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	for monster: int in wild.monsters:
		if _is_predator(state, wild, monster):
			homes[monster] = state.entity(monster).tile


## Whether the wild monster is of a predator species.
static func _is_predator(state: GameState, wild: WildMonsterFeature, monster: int) -> bool:
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var traits: Array = schedules.traits.get(wild.species_of(monster), [])
	return traits.has(SpeciesBehaviour.PREDATOR)


## Every hunter in its hunt hours hunts, in id order; one out of them ends its hunt and rests no
## more.
func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var struck: Dictionary[int, bool] = {}
	for event: RefCounted in state.events:
		if event is WildMonsterStruck:
			struck[(event as WildMonsterStruck).monster_id] = true
	for hunter: int in wild.monsters:
		if not homes.has(hunter):
			continue
		if schedules.activity_of(state, hunter) != Schedule.HUNT:
			_end(hunter)
			rested.erase(hunter)
			continue
		if rested.has(hunter) or wild.asleep.has(hunter) or wild.rage_of(hunter) > 0:
			continue
		if not _free(state, wild, hunter):
			continue
		_hunt(state, wild, hunter, struck.has(hunter))


## The hunter stalks its prey, or one it sights, and strikes it next to it, unless it `struck`
## something else this tick; it roams when it sees none, and gives up on prey it stalked too long.
func _hunt(state: GameState, wild: WildMonsterFeature, hunter: int, struck: bool) -> void:
	var tile: Vector2i = state.entity(hunter).tile
	# Prey another hunter beat counts as won: the pack fed.
	if prey.has(hunter) and wild.monsters.has(prey[hunter]) and _beaten(state, prey[hunter]):
		_rest(hunter)
		return
	var target: int = _prey_for(state, wild, hunter, tile)
	if target == 0:
		_end(hunter)
		_roam(state, wild, hunter, tile)
		return
	if prey.get(hunter, 0) != target:
		prey[hunter] = target
		_sighted[hunter] = state.tick
	if state.tick - _sighted[hunter] >= GIVE_UP_TICKS:
		_rest(hunter)
		return
	var prey_tile: Vector2i = state.entity(target).tile
	if Hex.distance(tile, prey_tile) > 1:
		wild.chase(state, hunter, prey_tile)
		return
	if struck or state.tick % WildAttackFeature.STRIKE_TICKS != 0:
		return
	# What the strike deals: never the prey's last HP, which a non-lethal strike leaves it.
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var damage: int = mini(wild.strength_of(hunter), health.hp_of(state, target) - 1)
	state.events.append(WildMonsterStruck.new(hunter, target, prey_tile, damage))
	wild.wound(state, target, damage)
	if _beaten(state, target):
		_rest(hunter)


## The prey the hunter on `tile` goes for: the one it stalks while it's still prey and in sight,
## else the nearest prey in sight, the lowest id of the equally near; 0 for none.
func _prey_for(state: GameState, wild: WildMonsterFeature, hunter: int, tile: Vector2i) -> int:
	var stalked: int = prey.get(hunter, 0)
	if stalked != 0 and _is_prey(state, wild, hunter, stalked, tile):
		return stalked
	var nearest: int = 0
	var gap: int = SIGHT + 1
	for monster: int in wild.monsters:
		if not _is_prey(state, wild, hunter, monster, tile):
			continue
		var distance: int = Hex.distance(state.entity(monster).tile, tile)
		if distance < gap:
			nearest = monster
			gap = distance
	return nearest


## Whether the wild monster `monster` is prey for `hunter` on `tile`: standing within SIGHT, free,
## not yet beaten, and weaker than the hunter or of a grazer species.
func _is_prey(
	state: GameState,
	wild: WildMonsterFeature,
	hunter: int,
	monster: int,
	tile: Vector2i,
) -> bool:
	if monster == hunter or not wild.monsters.has(monster) or not _free(state, wild, monster):
		return false
	if Hex.distance(state.entity(monster).tile, tile) > SIGHT or _beaten(state, monster):
		return false
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var traits: Array = schedules.traits.get(wild.species_of(monster), [])
	var weaker: bool = wild.strength_of(monster) < wild.strength_of(hunter)
	return weaker or traits.has(SpeciesBehaviour.GRAZER)


## Whether the standing wild monster is free to hunt or be hunted: not held or in a ring.
static func _free(state: GameState, wild: WildMonsterFeature, monster: int) -> bool:
	if wild.held.has(monster):
		return false
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	if domination == null:
		return true
	return not (domination.is_encircled(monster) or domination.is_sealed(monster))


## Whether the wild monster is beaten: down to its last HP, which no hunter's strike takes.
static func _beaten(state: GameState, monster: int) -> bool:
	return (state.feature(HealthFeature.ID) as HealthFeature).hp_of(state, monster) <= 1


## On its tick to step, the hunter on `tile` steps a random way, or back toward its home when that
## way leads further than ROAM_RADIUS from it.
func _roam(state: GameState, wild: WildMonsterFeature, hunter: int, tile: Vector2i) -> void:
	if (state.tick + hunter) % WildMonsterFeature.STEP_TICKS != 0:
		return
	var goal: Vector2i = tile + Hex.DIRECTIONS[_rng.below(Hex.DIRECTIONS.size())]
	if Hex.distance(goal, homes[hunter]) > ROAM_RADIUS:
		goal = homes[hunter]
	wild.chase(state, hunter, goal)


## The hunter's hunt ends, and it rests until its hunt hours are over.
func _rest(hunter: int) -> void:
	_end(hunter)
	if not rested.has(hunter):
		rested.append(hunter)
		rested.sort()


## The hunter stalks nothing any more.
func _end(hunter: int) -> void:
	var _dropped: bool = prey.erase(hunter)
	_dropped = _sighted.erase(hunter)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = homes.erase(removed_id)
	_end(removed_id)
	rested.erase(removed_id)
	# Prey that's gone is lost: its hunters sight another.
	for hunter: int in prey.keys():
		if prey[hunter] == removed_id:
			_end(hunter)


func hash_values() -> Array[int]:
	var values: Array[int] = []
	values.append_array(_flat_homes())
	values.append_array(_hunts())
	values.append(rested.size())
	values.append_array(rested)
	values.append_array(_rng.hash_values())
	return values


## The hunters' homes, the hunts going on, the resting hunters and the stream's state.
func save_values() -> Dictionary:
	return {
		"homes": _flat_homes(),
		"hunts": _hunts(),
		"rested": rested,
		"rng": _rng.hash_values(),
	}


## Each hunter must be a wild monster of a predator species, once, at home on a tile of the
## region; each hunt a hunter's, on another wild monster, sighted no later than now.
func load_values(state: GameState, values: DataReader) -> void:
	homes.clear()
	prey.clear()
	_sighted.clear()
	rested.clear()
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var flat: Array[int] = values.wholes("homes", -DataReader.MOST, DataReader.MOST)
	var hunts: Array[int] = values.wholes("hunts", 0, DataReader.MOST)
	var resting: Array[int] = values.wholes("rested", 1, DataReader.MOST)
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	if values.failed():
		return
	if flat.size() % 3 != 0 or hunts.size() % 3 != 0 or restored == null:
		values.fail("the hunts' homes, hunts or random stream are cut off")
		return
	for i: int in range(0, flat.size(), 3):
		var home: Vector2i = Vector2i(flat[i + 1], flat[i + 2])
		var known: bool = _is_predator(state, wild, flat[i]) and not homes.has(flat[i])
		if not known or not state.region.has_tile(home):
			values.fail("hunter %d isn't a predator, once, at home in the region" % flat[i])
			return
		homes[flat[i]] = home
	for i: int in range(0, hunts.size(), 3):
		var wrong: bool = not homes.has(hunts[i]) or hunts[i + 1] == hunts[i]
		wrong = wrong or prey.has(hunts[i]) or not wild.monsters.has(hunts[i + 1])
		if wrong or hunts[i + 2] > state.tick:
			values.fail("hunt %d isn't a hunter's on a wild monster" % hunts[i])
			return
		prey[hunts[i]] = hunts[i + 1]
		_sighted[hunts[i]] = hunts[i + 2]
	for hunter: int in resting:
		if not homes.has(hunter) or resting.count(hunter) > 1:
			values.fail("resting hunter %d isn't a hunter once" % hunter)
			return
	rested = resting
	rested.sort()
	_rng = restored


## Every hunter's id and home, in id order.
func _flat_homes() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(homes.keys())
	ids.sort()
	var flat: Array[int] = []
	for hunter: int in ids:
		flat.append_array([hunter, homes[hunter].x, homes[hunter].y])
	return flat


## Every hunt going on as its hunter's id, its prey's and the tick the prey was sighted, by hunter.
func _hunts() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(prey.keys())
	ids.sort()
	var flat: Array[int] = []
	for hunter: int in ids:
		flat.append_array([hunter, prey[hunter], _sighted[hunter]])
	return flat
