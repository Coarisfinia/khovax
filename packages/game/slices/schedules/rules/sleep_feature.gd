class_name SleepFeature
extends Feature
## Wild monsters sleep by their schedules (#1202, owner's ground rule, #1199): when a sleep block of
## its day (ScheduleFeature) begins, a standing wild monster lies down where it stands and sleeps,
## and when the block ends, it wakes (WildMonsterFeature.sleep). Asleep, it neither moves nor
## starts a fight. A strike or rage wakes it at once (WildMonsterFeature.wound and enrage), and it
## stays awake until its next sleep block: it isn't put back to sleep within the block it was woken
## in. A player coming close doesn't wake it, unless its species is a light sleeper (#1230): one
## wakes as soon as a player stands next to it, on any tick, and stays awake the same way. A
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
## wakes. Then, every tick, a light sleeper with a player next to it wakes.
func step(state: GameState, _commands: Array[Command]) -> void:
	# A clock set back (only tests do) settles this tick's hour, as a step always did.
	var last: int = mini(_stepped_at, state.world_tick - 1)
	var turned: int = (Fixed.div_floor(state.world_tick, DayClock.TICKS_PER_HOUR)
			- Fixed.div_floor(last, DayClock.TICKS_PER_HOUR))
	for ago: int in range(mini(turned, DayClock.HOURS) - 1, -1, -1):
		_settle(state, DayClock.hour_of(state.world_tick - ago * DayClock.TICKS_PER_HOUR))
	_stepped_at = state.world_tick
	_wake_light_sleepers(state)


func hash_values() -> Array[int]:
	var values: Array[int] = [_stepped_at]
	return values


func save_values() -> Dictionary:
	return { "stepped_at": _stepped_at }


func load_values(_state: GameState, values: DataReader) -> void:
	_stepped_at = values.whole("stepped_at", 0, DataReader.MOST)


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


## Wakes every sleeping light sleeper (#1230) with a player on a tile next to it.
func _wake_light_sleepers(state: GameState) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	for monster: int in wild.asleep.duplicate():
		if (schedules.has_trait(state, monster, SpeciesBehaviour.LIGHT_SLEEPER)
				and _player_next_to(state, state.entity(monster).tile)):
			wild.sleep(monster, false)


## Whether a player stands on a tile next to `tile`.
static func _player_next_to(state: GameState, tile: Vector2i) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player != null and Hex.distance(player.tile, tile) == 1:
			return true
	return false
