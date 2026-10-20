class_name WildMonsterFeature
extends Feature
## Wild monsters (#19): when the instance loads, one stands on every spot the region marks for it,
## as an entity no player controls, and each is of a species (#133). A spot whose region piece names
## its species gets that one (a boss arena pins its boss); every other spot rolls one from the
## blueprint's weighted list, from the feature's own random stream, so a replay places the same
## species. Each gets its short id (#700) from the same stream once every spot has its species. Each
## stands where it is (its look is a placeholder, #85), unless no ring could enclose
## it
## there (#364, RingableGround): then it steps, once every STEP_TICKS, toward the nearest tile where
## one could, never onto the trail or onto anyone, so it never walks into a ring. One held (hiding,
## #202) stays put. Walkers can't step onto its tile (MovementFeature), and a ring dominates
## it (DominationFeature). Each has its species'
## strength (#219); its HP is HealthFeature's (#835), at its species' HP, or WOUNDED_HP of it where
## the region marks it wounded (#389). Companions' strikes wound it (#221), and a special attack
## can fell it (#410): it faints for good, staying where it fell, out of `monsters` and in
## `fainted`, so no rule moves, enrages, strikes or dominates it any more, and it
## still blocks walkers like anything that doesn't walk. Enraged (#220,
## EnrageFeature), it grows stronger with every stack of rage, which it keeps. Like every feature,
## switched off it keeps its state: the monsters stay where they are, and only its own rules stop.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "wild_monsters"
## The strength of a species the feature wasn't given one for: it pushes on nothing.
const UNKNOWN_STRENGTH: int = 0
## How much stronger each stack of rage makes a wild monster (thousandths), and the most stacks it
## takes. Placeholders to tune (#960).
const RAGE_STRENGTH: int = 500
const MOST_RAGE: int = 3
## How many ticks a wild monster that can't be ringed where it stands takes for each step away: its
## own pace, slower than a player's. A placeholder to tune (#960).
const STEP_TICKS: int = Simulation.TICKS_PER_SECOND
## The share of its full HP a wild monster a region marks wounded starts with (#389), in
## thousandths. A placeholder to tune (#960).
const WOUNDED_HP: int = 250

## Every wild monster's entity id, in id order.
var monsters: Array[int] = []
## Every fainted one's (#410), felled by a lethal strike, in id order: no longer a wild monster.
var fainted: Array[int] = []
## The blueprint's species ids for spots the region doesn't name, and how likely each one is.
var roster: Array[String] = []
var weights: Array[int] = []
## Each species' base strength, by species id, from the content data (the species slice reads it).
var strengths: Dictionary[String, int] = {}
## Each wild monster's own data (#820), standing or fainted, by entity id: one record, so its
## parts never drift apart.
var _wild: Dictionary[int, WildMonster] = {}
## The wild monsters held where they stand whatever the ground, in id order: HidingFeature holds
## the hidden ones (#202) and lets them go when they jump out, and restores them on loading, so
## they aren't saved here.
var held: Array[int] = []
## Every species id this instance can place, sorted: the hash counts a species by its place here.
var _known: Array[String] = []
## The tiles of `_unringable_region` no ring can enclose a wild monster on, cached by
## _unringable_in. Derived from the region, so not hashed, and worked out again when a tile of it
## changes (#530).
var _unringable: Dictionary[Vector2i, bool] = {}
var _unringable_region: Region = null


func _init(
	roster_ids: Array[String] = [],
	roster_weights: Array[int] = [],
	species_strengths: Dictionary[String, int] = {},
) -> void:
	roster = roster_ids
	weights = roster_weights
	strengths = species_strengths


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [TrailFeature.ID, HealthFeature.ID]
	return needed


func start(state: GameState) -> void:
	var rng: Rng = Rng.new(state.rng_seed, stream())
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	_known = roster.duplicate()
	var placed: Dictionary[Vector2i, String] = state.region.placed(WildSpotPlacements.KIND)
	for spot: Vector2i in state.region.wild_monsters:
		var named: WildSpot = WildSpot.read(placed[spot]) if placed.has(spot) else null
		var species: String = named.species if named != null else ""
		if species.is_empty() and not roster.is_empty():
			species = roster[rng.pick_weighted(weights)]
		if not _known.has(species):
			_known.append(species)
		# Can't be refused: an entity without a slot is always added.
		var monster: Entity = state.add_entity(Entity.NO_SLOT, spot)
		monsters.append(monster.id)
		var wild: WildMonster = WildMonster.of(species)
		health.track(monster.id, species)
		if named != null:
			wild.emits = named.emits
			wild.target = named.target
			if named.wounded:
				var full: int = health.max_hp_of(state, monster.id)
				var _fell: bool = health.hurt(
					state,
					monster.id,
					full - maxi(Fixed.scale(full, WOUNDED_HP), 1),
					false,
				)
		_wild[monster.id] = wild
	# Drawn after every species, so the species roll as they did before short ids; one already
	# taken here is drawn again, so no two share one.
	for monster: int in monsters:
		var drawn: String = ShortId.drawn(rng)
		while _short_id_taken(drawn):
			drawn = ShortId.drawn(rng)
		_wild[monster].short_id = drawn
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
	for tile: Vector2i in (state.feature(TrailFeature.ID) as TrailFeature).shared.tiles:
		blocked[tile] = true
	for entity: Entity in state.entities:
		blocked[entity.tile] = true
	return blocked


func _unringable_in(region: Region) -> Dictionary[Vector2i, bool]:
	if region != _unringable_region:
		_unringable_region = region
		_unringable = RingableGround.unringable(region)
	return _unringable


func tile_changed(_state: GameState, _tile: Vector2i) -> void:
	_unringable_region = null


func entity_removed(_state: GameState, removed_id: int) -> void:
	monsters.erase(removed_id)
	fainted.erase(removed_id)
	held.erase(removed_id)
	var _dropped: bool = _wild.erase(removed_id)


## Holds the wild monster with this entity id where it stands, or lets it go again.
func hold(entity_id: int, holding: bool) -> void:
	held.erase(entity_id)
	if holding and monsters.has(entity_id):
		held.append(entity_id)
		held.sort()


## The species id of the wild monster with this entity id, or "" when it has none.
func species_of(entity_id: int) -> String:
	var wild: WildMonster = _wild.get(entity_id)
	return wild.species if wild != null else ""


## The short id of the wild monster with this entity id (#700), or "" when it has none.
func short_id_of(entity_id: int) -> String:
	var wild: WildMonster = _wild.get(entity_id)
	return wild.short_id if wild != null else ""


## The quest target the wild monster with this entity id is (#625), or "" when it's none.
func target_of(entity_id: int) -> String:
	var wild: WildMonster = _wild.get(entity_id)
	return wild.target if wild != null else ""


## Its species' strength, raised by RAGE_STRENGTH for every stack of rage it has (#220).
func strength_of(entity_id: int) -> int:
	var base: int = strengths.get(species_of(entity_id), UNKNOWN_STRENGTH)
	return Fixed.scale(base, Fixed.ONE + rage_of(entity_id) * RAGE_STRENGTH)


## The wild monster's stacks of rage.
func rage_of(entity_id: int) -> int:
	var wild: WildMonster = _wild.get(entity_id)
	return wild.rage if wild != null else 0


## Whether the entity with this id is a fainted one (#410).
func is_fainted(entity_id: int) -> bool:
	return fainted.has(entity_id)


## Takes `damage` off the standing wild monster's HP (HealthFeature, #835). A non-lethal hit (#221)
## never takes it below 1, so it weakens it for a domination; a `lethal` one (#410) can take it to
## 0, and then it faints: it loses its rage and emits in `state` the event its region names for it,
## if any (#541).
func wound(state: GameState, entity_id: int, damage: int, lethal: bool = false) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if not monsters.has(entity_id) or not health.hurt(state, entity_id, damage, lethal):
		return
	var wild: WildMonster = _wild[entity_id]
	monsters.erase(entity_id)
	held.erase(entity_id)
	wild.rage = 0
	fainted.append(entity_id)
	fainted.sort()
	if not wild.emits.is_empty():
		state.events.append(EventEmitted.new(wild.emits))
		wild.emits = ""


## Enrages the standing wild monster once more (#220), up to MOST_RAGE stacks: it grows stronger and
## heals `heal` thousandths of its full HP, never past it. EnrageFeature's rule calls this.
func enrage(state: GameState, entity_id: int, heal: int) -> void:
	if not monsters.has(entity_id):
		return
	_wild[entity_id].rage = mini(_wild[entity_id].rage + 1, MOST_RAGE)
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	health.heal(state, entity_id, Fixed.scale(health.max_hp_of(state, entity_id), heal))


## Each wild monster still in the instance as its entity's id, its species, its short id and
## whether it fainted, in id order, its rage, the event a standing one emits when it
## faints, if any (#541), and the quest target it is, if any (#625). The roster, the species this
## instance can place and their stats follow from the
## blueprint, the region and the content.
func save_values() -> Dictionary:
	var saved: Array[Dictionary] = []
	var standing: Array[int] = monsters.duplicate()
	standing.append_array(fainted)
	standing.sort()
	for monster: int in standing:
		var wild: WildMonster = _wild[monster]
		var entry: Dictionary = {
			"entity": monster,
			"species": wild.species,
			"short_id": wild.short_id,
			"fainted": 1 if fainted.has(monster) else 0,
		}
		entry["rage"] = wild.rage
		if not wild.emits.is_empty():
			entry["emits"] = wild.emits
		if not wild.target.is_empty():
			entry["target"] = wild.target
		saved.append(entry)
	return { "wild_monsters": saved }


func load_values(state: GameState, values: DataReader) -> void:
	monsters.clear()
	fainted.clear()
	held.clear()
	_wild.clear()
	for entry: DataReader in values.entries("wild_monsters"):
		var monster: int = entry.whole("entity", 1, DataReader.MOST)
		var species: String = entry.text("species")
		var standing: Entity = state.entity(monster)
		if standing == null or standing.slot != Entity.NO_SLOT or _wild.has(monster):
			values.fail("wild monster %d isn't one entity without a player" % monster)
			return
		if not _known.has(species):
			values.fail("wild monster %d is of %s, which this instance doesn't place" % [
				monster,
				species,
			])
			return
		var short_id: String = entry.text("short_id")
		if not ShortId.is_valid(short_id) or _short_id_taken(short_id):
			values.fail("wild monster %d has no valid short id of its own" % monster)
			return
		var wild: WildMonster = WildMonster.of(species)
		wild.short_id = short_id
		_wild[monster] = wild
		if (entry.data as Dictionary).has("target"):
			wild.target = entry.text("target")
		if entry.whole("fainted", 0, 1) == 1:
			fainted.append(monster)
			continue
		monsters.append(monster)
		wild.rage = entry.whole("rage", 0, MOST_RAGE)
		if (entry.data as Dictionary).has("emits"):
			wild.emits = entry.text("emits")
	monsters.sort()
	fainted.sort()
	_track_loaded(state, values)


## Tracks every restored wild monster's species with the health feature, restored before it, and
## checks its HP: none left exactly for a fainted one.
func _track_loaded(state: GameState, values: DataReader) -> void:
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	for monster: int in _wild:
		health.track(monster, _wild[monster].species)
		var down: bool = health.hp_of(state, monster) == 0
		if not health.fits(state, monster) or down != fainted.has(monster):
			values.fail("wild monster %d's HP doesn't match whether it fainted" % monster)
			return


func hash_values() -> Array[int]:
	var values: Array[int] = [monsters.size()]
	for monster: int in monsters:
		values.append(monster)
		var wild: WildMonster = _wild[monster]
		values.append_array([_known.find(wild.species), StateHash.name_code(wild.short_id)])
		values.append_array([strength_of(monster), wild.rage])
	values.append(held.size())
	values.append_array(held)
	values.append(fainted.size())
	for monster: int in fainted:
		values.append_array([monster, _known.find(_wild[monster].species)])
		values.append(StateHash.name_code(_wild[monster].short_id))
	var emits: Dictionary[int, String] = {}
	var targets: Dictionary[int, String] = {}
	for monster: int in _wild:
		if not _wild[monster].emits.is_empty():
			emits[monster] = _wild[monster].emits
		if not _wild[monster].target.is_empty():
			targets[monster] = _wild[monster].target
	_hash_names(values, emits)
	_hash_names(values, targets)
	return values


## Whether a wild monster here already has this short id (#700).
func _short_id_taken(short_id: String) -> bool:
	for monster: int in _wild:
		if _wild[monster].short_id == short_id:
			return true
	return false


## Adds `names`, each by its monster's entity id, to `values`, in id order after how many there
## are. Only a region naming events (#541) or quest targets (#625) has any, so every other instance
## hashes as before.
static func _hash_names(values: Array[int], names: Dictionary[int, String]) -> void:
	if names.is_empty():
		return
	values.append(names.size())
	var ids: Array[int] = []
	ids.assign(names.keys())
	ids.sort()
	for monster: int in ids:
		values.append_array([monster, StateHash.name_code(names[monster])])
