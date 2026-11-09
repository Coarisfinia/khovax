class_name SleepFeature
extends Feature
## Wild monsters sleep by their schedules (#1202, owner's ground rule, #1199): when a sleep block of
## its day (ScheduleFeature) begins, a standing wild monster lies down where it stands and sleeps,
## and when the block ends, it wakes (WildMonsterFeature.sleep). Asleep, it neither moves nor
## starts a fight. A strike or rage wakes it at once (WildMonsterFeature.wound and enrage), and it
## stays awake until its next sleep block: it isn't put back to sleep within the block it was woken
## in. A player coming close doesn't wake it, unless its species is a light sleeper (#1230): one
## wakes as soon as a player stands next to it, on any tick, and stays awake the same way. A player
## may be hushed (#1563, `hush`, which a later rule sets from a passive of their companion): a light
## sleeper next to them hears only their steps (an EntityMoved this tick), so standing still beside
## it never wakes it, and wakes on the step that makes its count reach their hush (#2235). The count
## is the sleeper's own, so co-op players' steps add up on it, and it starts over once it wakes. A
## sleepless monster's day has no sleep block, so it never sleeps. One already in a sleep block when
## the instance loads fresh is asleep from the start. The schedules change only on the hour, so it
## puts to sleep only then. Who sleeps is WildMonsterFeature's state (`asleep`), saved and hashed
## there.
##
## An instance nobody is in keeps the world's time but doesn't step (#1215), so its monsters can
## miss hours. When it steps again (#1245), every hour that turned since its last step is settled
## first, in order, as if it had stepped all along: it keeps the world tick of its last step for
## that, saved and hashed. Only the last day of them counts, since a day holds every hour.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "sleep"

## The world tick (GameState.world_tick) of the feature's last step, or of the instance's start.
var _stepped_at: int = 0
## Each hushed player's hush (#1563, #2235), by slot: a light sleeper wakes on the step of theirs
## that makes this many it has heard; a player without one isn't hushed.
var _hushes: Dictionary[int, int] = {}
## How many hushed steps next to it each sleeping light sleeper has heard (#2235), by entity id.
var _steps_heard: Dictionary[int, int] = {}


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, ScheduleFeature.ID]
	return needed


## Every wild monster in a sleep block when the instance starts is asleep from its first tick.
func start(state: GameState) -> void:
	_stepped_at = state.world_tick
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	for monster: int in wild.monsters:
		wild.sleep(monster, schedules.activity_of(state, monster) == Schedule.SLEEP)


## On every hour that turned since the last step (this tick's alone, while the instance steps
## every tick), a wild monster whose sleep block begins falls asleep, and one whose block ended
## wakes. Then, every tick, a light sleeper with a player next to it wakes, unless that player is
## hushed and hasn't made its count yet.
func step(state: GameState, _commands: Array[Command]) -> void:
	# A clock set back (only tests do) settles this tick's hour, as a step always did.
	var last: int = mini(_stepped_at, state.world_tick - 1)
	var turned: int = (Fixed.div_floor(state.world_tick, DayClock.TICKS_PER_HOUR)
			- Fixed.div_floor(last, DayClock.TICKS_PER_HOUR))
	for ago: int in range(mini(turned, DayClock.HOURS) - 1, -1, -1):
		_settle(state, DayClock.hour_of(state.world_tick - ago * DayClock.TICKS_PER_HOUR))
	_stepped_at = state.world_tick
	_wake_light_sleepers(state)


## Hushes the player in `slot` (#1563, #2235): a light sleeper wakes on every `every`th step next
## to it; 0 for none. Only rules call it, inside a tick (#30).
func hush(slot: int, every: int) -> void:
	if every < 2:
		var _unhushed: bool = _hushes.erase(slot)
	else:
		_hushes[slot] = every


func hash_values() -> Array[int]:
	var values: Array[int] = [_stepped_at]
	values.append_array(DataReader.flat_pairs(_hushes))
	values.append_array(DataReader.flat_pairs(_steps_heard))
	return values


func save_values() -> Dictionary:
	return {
		"stepped_at": _stepped_at,
		"hushes": DataReader.flat_pairs(_hushes),
		"steps_heard": DataReader.flat_pairs(_steps_heard),
	}


func load_values(_state: GameState, values: DataReader) -> void:
	_stepped_at = values.whole("stepped_at", 0, DataReader.MOST)
	_hushes.clear()
	var hushes: Dictionary[int, int] = values.pairs("hushes", 0, DataReader.MOST)
	for slot: int in hushes:
		if slot >= GameState.MAX_PLAYERS or hushes[slot] < 2:
			values.fail("slot %d's hush isn't a player's, from 2" % slot)
			return
		_hushes[slot] = hushes[slot]
	_steps_heard = values.pairs("steps_heard", 0, DataReader.MOST)


## The hour `hour` has begun: puts every standing wild monster whose sleep block begins with it to
## sleep, and wakes every one for whom it isn't an hour of sleep, in id order.
func _settle(state: GameState, hour: int) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var last_hour: int = (hour + DayClock.HOURS - 1) % DayClock.HOURS
	for monster: int in wild.monsters:
		if schedules.activity_at(monster, hour) != Schedule.SLEEP:
			wild.sleep(monster, false)
		elif schedules.activity_at(monster, last_hour) != Schedule.SLEEP:
			wild.sleep(monster, true)


## Wakes every sleeping light sleeper (#1230) a player next to it wakes, in id order.
func _wake_light_sleepers(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var stepped: Array[int] = _stepped_slots(state)
	for monster: int in wild.asleep.duplicate():
		if (schedules.has_trait(state, monster, SpeciesBehaviour.LIGHT_SLEEPER)
				and _woken_by_players(state, monster, stepped)):
			wild.sleep(monster, false)
	for heard: int in _steps_heard.keys():
		if not wild.asleep.has(heard):
			var _forgotten: bool = _steps_heard.erase(heard)


## Whether a player next to the light sleeper `monster` wakes it, in slot order: one who isn't
## hushed does; a hushed one's step this tick (in `stepped`) adds to its count, and wakes it when
## the count reaches their hush.
func _woken_by_players(state: GameState, monster: int, stepped: Array[int]) -> bool:
	var tile: Vector2i = state.entity(monster).tile
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null or Hex.distance(player.tile, tile) != 1:
			continue
		if not _hushes.has(slot):
			return true
		if stepped.has(slot):
			_steps_heard[monster] = _steps_heard.get(monster, 0) + 1
			if _steps_heard[monster] >= _hushes[slot]:
				return true
	return false


## The slots of the players who stepped this tick (EntityMoved, from MovementFeature, earlier).
static func _stepped_slots(state: GameState) -> Array[int]:
	var stepped: Array[int] = []
	for event: RefCounted in state.events:
		var moved: EntityMoved = event as EntityMoved
		if moved == null:
			continue
		var walker: Entity = state.entity(moved.entity_id)
		if walker != null and walker.slot != Entity.NO_SLOT and not stepped.has(walker.slot):
			stepped.append(walker.slot)
	return stepped
