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
## sleeper next to them wakes only when they have just stepped (an EntityMoved this tick) and a roll
## on the feature's own stream doesn't spare it, so standing still beside it never wakes it. A
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
## Each hushed player's hush (#1563), by slot: the share of their steps next to a light sleeper that
## don't wake it, in thousandths (Fixed); a player without one isn't hushed.
var _hushes: Dictionary[int, int] = {}
var _rng: Rng


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [WildMonsterFeature.ID, ScheduleFeature.ID]
	return needed


## Every wild monster in a sleep block when the instance starts is asleep from its first tick.
func start(state: GameState) -> void:
	_stepped_at = state.world_tick
	_rng = Rng.new(state.rng_seed, stream())
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	for monster: int in wild.monsters:
		wild.sleep(monster, schedules.activity_of(state, monster) == Schedule.SLEEP)


## On every hour that turned since the last step (this tick's alone, while the instance steps
## every tick), a wild monster whose sleep block begins falls asleep, and one whose block ended
## wakes. Then, every tick, a light sleeper with a player next to it wakes, unless that player is
## hushed and the roll spares it.
func step(state: GameState, _commands: Array[Command]) -> void:
	# A clock set back (only tests do) settles this tick's hour, as a step always did.
	var last: int = mini(_stepped_at, state.world_tick - 1)
	var turned: int = (Fixed.div_floor(state.world_tick, DayClock.TICKS_PER_HOUR)
			- Fixed.div_floor(last, DayClock.TICKS_PER_HOUR))
	for ago: int in range(mini(turned, DayClock.HOURS) - 1, -1, -1):
		_settle(state, DayClock.hour_of(state.world_tick - ago * DayClock.TICKS_PER_HOUR))
	_stepped_at = state.world_tick
	_wake_light_sleepers(state)


## Hushes the player in `slot` by `share` (#1563): the share of their steps next to a light sleeper
## that don't wake it, in thousandths, kept below a whole (Fixed.ONE); 0 for none. Only rules call
## it, inside a tick (#30).
func hush(slot: int, share: int) -> void:
	if share <= 0:
		var _unhushed: bool = _hushes.erase(slot)
	else:
		_hushes[slot] = mini(share, Fixed.ONE - 1)


func hash_values() -> Array[int]:
	var values: Array[int] = [_stepped_at]
	values.append_array(DataReader.flat_pairs(_hushes))
	values.append_array(_rng.hash_values())
	return values


func save_values() -> Dictionary:
	return {
		"stepped_at": _stepped_at,
		"hushes": DataReader.flat_pairs(_hushes),
		"rng": _rng.hash_values(),
	}


func load_values(_state: GameState, values: DataReader) -> void:
	_stepped_at = values.whole("stepped_at", 0, DataReader.MOST)
	_hushes.clear()
	var hushes: Dictionary[int, int] = values.pairs("hushes", 0, Fixed.ONE - 1)
	for slot: int in hushes:
		if slot >= GameState.MAX_PLAYERS or hushes[slot] < 1:
			values.fail("slot %d's hush isn't a player's, from 1 to %d" % [slot, Fixed.ONE - 1])
			return
		_hushes[slot] = hushes[slot]
	var restored: Rng = Rng.restored(values.wholes("rng", 0, Rng.MASK))
	if restored == null:
		values.fail("the sleep's random stream isn't four 32-bit words, not all zero")
		return
	_rng = restored


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
				and _woken_by_players(state, state.entity(monster).tile, stepped)):
			wild.sleep(monster, false)


## Whether a player on a tile next to `tile` wakes the light sleeper there, in slot order: one
## who isn't hushed does; a hushed one only when they stepped this tick (in `stepped`) and the roll
## doesn't spare it. It rolls only for those, and stops once one wakes it.
func _woken_by_players(state: GameState, tile: Vector2i, stepped: Array[int]) -> bool:
	for slot: int in GameState.MAX_PLAYERS:
		var player: Entity = state.player(slot)
		if player == null or Hex.distance(player.tile, tile) != 1:
			continue
		if not _hushes.has(slot):
			return true
		if stepped.has(slot) and not _rng.chance(_hushes[slot], Fixed.ONE):
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
