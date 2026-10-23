class_name ScheduleFeature
extends Feature
## Every wild monster's daily schedule (#1201, owner's ground rule, #1199): made once, when the
## instance loads, from its species' behaviour traits (Schedule) and the instance's seed, and what
## it's doing now by the DayClock (`activity_of`), for the behaviours that act on it (#1202 to
## #1205). Each monster draws from a random stream of its own, seeded from the instance's seed and
## its entity id, so its day never depends on the other monsters, and follows from what the save
## holds already: a loaded instance makes them again, the same, rather than saving them. The
## schedules are in the state hash. It doesn't step: the time of day follows from the world's tick.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "schedules"

## Each species' behaviour traits, by species id (SpeciesBehaviour), from the content data (the
## species slice reads them).
var traits: Dictionary[String, Array] = {}
## Each wild monster's day, standing or fainted, by entity id: one activity (Schedule) per hour.
var _days: Dictionary[int, Array] = {}


func _init(species_traits: Dictionary[String, Array] = {}) -> void:
	traits = species_traits


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID]
	return needed


func start(state: GameState) -> void:
	_make_days(state)


## What the wild monster with this entity id is doing now (a Schedule activity): its schedule's
## activity for the hour of the day, or Schedule.NONE when it has none or has fainted.
func activity_of(state: GameState, entity_id: int) -> int:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild.is_fainted(entity_id):
		return Schedule.NONE
	return activity_at(entity_id, DayClock.hour_now(state))


## What the wild monster with this entity id does at `hour` o'clock by its schedule (a Schedule
## activity), or Schedule.NONE when it has none.
func activity_at(entity_id: int, hour: int) -> int:
	if not _days.has(entity_id):
		return Schedule.NONE
	var day: Array = _days[entity_id]
	var activity: int = day[hour]
	return activity


## The whole day of the wild monster with this entity id (Schedule.made), or empty when it has
## none.
func day_of(entity_id: int) -> Array[int]:
	var stored: Array = _days.get(entity_id, [])
	var day: Array[int] = []
	day.assign(stored)
	return day


## Whether the wild monster with this entity id is of a species with the behaviour trait `named`
## (SpeciesBehaviour).
func has_trait(state: GameState, entity_id: int, named: String) -> bool:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var its_traits: Array = traits.get(wild.species_of(entity_id), [])
	return its_traits.has(named)


func entity_removed(_state: GameState, removed_id: int) -> void:
	var _dropped: bool = _days.erase(removed_id)


## Makes the days again for the wild monsters the save restored, which WildMonsterFeature loaded
## before it: the same, since each follows from the seed, its entity id and its species.
func load_values(state: GameState, _values: DataReader) -> void:
	_make_days(state)


func hash_values() -> Array[int]:
	var ids: Array[int] = []
	ids.assign(_days.keys())
	ids.sort()
	var values: Array[int] = [ids.size()]
	for monster: int in ids:
		values.append(monster)
		values.append_array(_days[monster])
	return values


## Makes every wild monster's day, standing or fainted, each from its own stream.
func _make_days(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	_days.clear()
	for monster: int in wild.monsters + wild.fainted:
		_days[monster] = _made_day(state, monster, wild.species_of(monster))


## The day of the wild monster with this entity id, of `species`, from its own stream.
func _made_day(state: GameState, monster: int, species: String) -> Array[int]:
	var its_traits: Array = traits.get(species, [])
	return Schedule.made(its_traits, Rng.new(state.rng_seed, StateHash.mix(stream(), monster)))
