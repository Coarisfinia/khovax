class_name SleepFeature
extends Feature
## Wild monsters sleep by their schedules (#1202, owner's ground rule, #1199): when a sleep block of
## its day (ScheduleFeature) begins, a standing wild monster lies down where it stands and sleeps,
## and when the block ends, it wakes (WildMonsterFeature.sleep). Asleep, it neither moves nor
## starts a fight. A strike or rage wakes it at once (WildMonsterFeature.wound and enrage), and it
## stays awake until its next sleep block: it isn't put back to sleep within the block it was woken
## in. A player coming close doesn't wake it. A sleepless monster's day has no sleep block, so it
## never sleeps. One already in a sleep block when the instance loads fresh is asleep from the
## start. The schedules change only on the hour, so it acts only then; what it does is
## WildMonsterFeature's state (`asleep`), which is saved and hashed there, so it keeps none.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "sleep"


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, ScheduleFeature.ID]
	return needed


## Every wild monster in a sleep block when the instance starts is asleep from its first tick.
func start(state: GameState) -> void:
	_settle(state, true)


## On the hour, a wild monster whose sleep block begins falls asleep, and one whose block ended
## wakes.
func step(state: GameState, _commands: Array[Command]) -> void:
	if state.world_tick % DayClock.TICKS_PER_HOUR == 0:
		_settle(state, false)


## Puts every standing wild monster whose sleep block begins this hour to sleep (or, `starting`,
## every one in a sleep block), and wakes every one whose hour isn't one of sleep, in id order.
func _settle(state: GameState, starting: bool) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var hour: int = DayClock.hour_now(state)
	var last_hour: int = (hour + DayClock.HOURS - 1) % DayClock.HOURS
	for monster: int in wild.monsters:
		if schedules.activity_of(state, monster) != Schedule.SLEEP:
			wild.sleep(monster, false)
		elif starting or schedules.day_of(monster)[last_hour] != Schedule.SLEEP:
			wild.sleep(monster, true)
