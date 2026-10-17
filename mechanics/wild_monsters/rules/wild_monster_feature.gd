class_name WildMonsterFeature
extends Feature
## Wild monsters (#19): when the instance loads, one stands on every spot the region marks for it,
## as an entity no player controls, and each is of a species (#133). A spot whose region piece names
## its species gets that one (a boss arena pins its boss); every other spot rolls one from the
## blueprint's weighted list, from the feature's own random stream, so a replay places the same
## species. Each stands where it is (its look is a placeholder, #85), unless no ring could enclose
## it
## there (#364, RingableGround): then it steps, once every STEP_TICKS, toward the nearest tile where
## one could, never onto the trail or onto anyone, so it never walks into a ring. One held (hiding,
## #202) stays put. Walkers can't step onto its tile (MovementFeature), and a ring dominates
## it (DominationFeature). Each has its species'
## strength and HP, and starts at full HP (#219); nothing hurts it yet. Enraged (#220,
## EnrageFeature), it grows stronger with every stack of rage, which it keeps. Like every feature,
## switched off it keeps its state: the monsters stay where they are, and only its own rules stop.

## The stats of a species the feature wasn't given any for: it pushes on nothing.
const UNKNOWN_MAX_HP: int = 1
const UNKNOWN_STRENGTH: int = 0
## How much stronger each stack of rage makes a wild monster (thousandths), and the most stacks it
## takes. Placeholders to tune (#220).
const RAGE_STRENGTH: int = 500
const MOST_RAGE: int = 3
## How many ticks a wild monster that can't be ringed where it stands takes for each step away: its
## own pace, slower than a player's. A placeholder to tune (#364).
const STEP_TICKS: int = Simulation.TICKS_PER_SECOND

## Every wild monster's entity id, in id order.
var monsters: Array[int] = []
## The blueprint's species ids for spots the region doesn't name, and how likely each one is.
var roster: Array[String] = []
var weights: Array[int] = []
## Each species' base HP and strength, by species id, from the content data (meta/ reads it).
var max_hps: Dictionary[String, int] = {}
var strengths: Dictionary[String, int] = {}
## Each wild monster's species id, by entity id.
var _species: Dictionary[int, String] = {}
## Each wild monster's HP left, by entity id.
var _hp: Dictionary[int, int] = {}
## Each wild monster's stacks of rage (#220), by entity id; none for one never enraged.
var _rage: Dictionary[int, int] = {}
## The wild monsters held where they stand whatever the ground, in id order: HidingFeature holds
## the hidden ones (#202) and lets them go when they jump out, and restores them on loading, so
## they aren't saved here.
var held: Array[int] = []
## Every species id this instance can place, sorted: the hash counts a species by its place here.
var _known: Array[String] = []
## The tiles of `_unringable_region` no ring can enclose a wild monster on, cached by
## _unringable_in. Derived from the region, which doesn't change during a session, so not hashed.
var _unringable: Dictionary[Vector2i, bool] = {}
var _unringable_region: Region = null


func _init(
	roster_ids: Array[String] = [],
	roster_weights: Array[int] = [],
	species_max_hps: Dictionary[String, int] = {},
	species_strengths: Dictionary[String, int] = {},
) -> void:
	roster = roster_ids
	weights = roster_weights
	max_hps = species_max_hps
	strengths = species_strengths


func id() -> int:
	return Features.WILD_MONSTERS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.TRAIL]
	return needed


func start(state: GameState) -> void:
	var rng: Rng = Rng.new(state.rng_seed, id())
	_known = roster.duplicate()
	for spot: Vector2i in state.region.wild_monsters:
		var species: String = state.region.named_species.get(spot, "")
		if species.is_empty() and not roster.is_empty():
			species = roster[rng.pick_weighted(weights)]
		if not _known.has(species):
			_known.append(species)
		# Can't be refused: an entity without a slot is always added.
		var monster: Entity = state.add_entity(Entity.NO_SLOT, spot)
		monsters.append(monster.id)
		_species[monster.id] = species
		_hp[monster.id] = max_hps.get(species, UNKNOWN_MAX_HP)
	_known.sort()


## Every wild monster no ring could enclose where it stands steps toward where one could, each on
## its own tick of every STEP_TICKS (by its id), in id order.
func step(state: GameState, _commands: Array[Command]) -> void:
	var stuck: Dictionary[Vector2i, bool] = _unringable_in(state.region)
	var blocked: Dictionary[Vector2i, bool] = {}
	for monster: int in monsters:
		# Only the monsters due this tick are looked up: finding an entity goes through them all.
		if (state.tick + monster) % STEP_TICKS != 0 or held.has(monster):
			continue
		var standing: Entity = state.entity(monster)
		if not stuck.has(standing.tile):
			continue
		if blocked.is_empty():
			blocked = _blocked(state)
		var from: Vector2i = standing.tile
		standing.tile = RingableGround.way_out(state.region, stuck, blocked, from)
		blocked[standing.tile] = true


## The tiles a wild monster may not step onto: the trail, so it never walks into a ring, and every
## tile something stands on.
static func _blocked(state: GameState) -> Dictionary[Vector2i, bool]:
	var blocked: Dictionary[Vector2i, bool] = {}
	for tile: Vector2i in (state.feature(Features.TRAIL) as TrailFeature).shared.tiles:
		blocked[tile] = true
	for entity: Entity in state.entities:
		blocked[entity.tile] = true
	return blocked


func _unringable_in(region: Region) -> Dictionary[Vector2i, bool]:
	if region != _unringable_region:
		_unringable_region = region
		_unringable = RingableGround.unringable(region)
	return _unringable


func entity_removed(_state: GameState, removed_id: int) -> void:
	monsters.erase(removed_id)
	held.erase(removed_id)
	var _dropped: bool = _species.erase(removed_id)
	_dropped = _hp.erase(removed_id)
	_dropped = _rage.erase(removed_id)


## Holds the wild monster with this entity id where it stands, or lets it go again.
func hold(entity_id: int, holding: bool) -> void:
	held.erase(entity_id)
	if holding and is_wild_monster(entity_id):
		held.append(entity_id)
		held.sort()


## Whether the entity with this id is a wild monster.
func is_wild_monster(entity_id: int) -> bool:
	return monsters.has(entity_id)


## The species id of the wild monster with this entity id, or "" when it has none.
func species_of(entity_id: int) -> String:
	return _species.get(entity_id, "")


## The wild monster's HP left, its species' full HP, and its species' strength.
func hp_of(entity_id: int) -> int:
	return _hp.get(entity_id, 0)


func max_hp_of(entity_id: int) -> int:
	return max_hps.get(species_of(entity_id), UNKNOWN_MAX_HP)


## Its species' strength, raised by RAGE_STRENGTH for every stack of rage it has (#220).
func strength_of(entity_id: int) -> int:
	var base: int = strengths.get(species_of(entity_id), UNKNOWN_STRENGTH)
	return Fixed.scale(base, Fixed.ONE + rage_of(entity_id) * RAGE_STRENGTH)


## The wild monster's stacks of rage.
func rage_of(entity_id: int) -> int:
	return _rage.get(entity_id, 0)


## Enrages the wild monster once more (#220), up to MOST_RAGE stacks: it grows stronger and heals
## `heal` thousandths of its full HP, never past it. EnrageFeature's rule calls this.
func enrage(entity_id: int, heal: int) -> void:
	if not is_wild_monster(entity_id):
		return
	_rage[entity_id] = mini(rage_of(entity_id) + 1, MOST_RAGE)
	var full: int = max_hp_of(entity_id)
	_hp[entity_id] = mini(hp_of(entity_id) + Fixed.scale(full, heal), full)


## Each wild monster still in the instance as its entity's id, its species and its HP left, in id
## order. The roster, the species this instance can place and their stats follow from the
## blueprint, the region and the content.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	for monster: int in monsters:
		var entry: Dictionary = {
			"entity": monster,
			"species": _species[monster],
			"hp": _hp[monster],
		}
		entry["rage"] = rage_of(monster)
		saved.append(entry)
	return { "wild_monsters": saved }


func load_values(state: GameState, values: DataReader) -> void:
	monsters.clear()
	held.clear()
	_species.clear()
	_hp.clear()
	_rage.clear()
	for entry: DataReader in values.entries("wild_monsters"):
		var monster: int = entry.whole("entity", 1, DataReader.MOST)
		var species: String = entry.text("species")
		var standing: Entity = state.entity(monster)
		if standing == null or standing.slot != Entity.NO_SLOT or _species.has(monster):
			values.fail("wild monster %d isn't one entity without a player" % monster)
			return
		if not _known.has(species):
			values.fail("wild monster %d is of %s, which this instance doesn't place" % [
				monster,
				species,
			])
			return
		monsters.append(monster)
		_species[monster] = species
		_hp[monster] = entry.whole("hp", 0, max_hp_of(monster))
		var rage: int = entry.whole("rage", 0, MOST_RAGE)
		if rage > 0:
			_rage[monster] = rage
	monsters.sort()


func hash_values() -> Array[int]:
	var values: Array[int] = [monsters.size()]
	for monster: int in monsters:
		values.append(monster)
		values.append(_known.find(_species[monster]))
		values.append_array([_hp[monster], max_hp_of(monster), strength_of(monster)])
		values.append(rage_of(monster))
	values.append(held.size())
	values.append_array(held)
	return values
