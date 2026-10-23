class_name ForagingFeature
extends Feature
## Wild monsters graze and drink by their schedules (#1203, owner's ground rule, #1199). In an hour
## its day (ScheduleFeature) gives to grazing, a standing wild monster walks to the nearest grass
## within reach and eats there until the hour ends; in one it gives to drinking, it walks to the
## nearest tile beside water within reach and drinks there (ForageWay). It walks there a step at a
## time at its own pace, round whatever stands in its way (WildMonsterFeature.chase, WildWay), so
## it never steps onto the trail, onto anyone or off ground a ring could enclose it on (WildGround):
## it stays catchable. With no grass or water within reach, it stays where it is. One held (hiding,
## or bound), enraged (it goes for the players instead, EnrageFeature) or in a ring
## (DominationFeature, when the instance has one) doesn't go. Where it is is WildMonsterFeature's
## state and the hour follows from the tick, so it keeps no state of its own.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "foraging"

## The ground the wild monsters step onto, kept for the region until a tile of it changes.
var _ground: WildGround = WildGround.new()


func id() -> String:
	return ID


func requires() -> Array[String]:
	# The trail too, which WildGround.blocked reads: no step onto it.
	var needed: Array[String] = [TrailFeature.ID, WildMonsterFeature.ID, ScheduleFeature.ID]
	return needed


func after() -> Array[String]:
	var earlier: Array[String] = [DominationFeature.ID, EnrageFeature.ID]
	return earlier


## Every standing wild monster due to graze or drink this hour takes its next step toward its grass
## or water, on its tick to step, in id order.
func step(state: GameState, _commands: Array[Command]) -> void:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var schedules: ScheduleFeature = state.feature(ScheduleFeature.ID) as ScheduleFeature
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	for monster: int in wild.monsters:
		# Its calm pace (an enraged one doesn't forage), so the costly search runs only when chase
		# would take the step.
		if (state.tick + monster) % WildMonsterFeature.STEP_TICKS != 0:
			continue
		var activity: int = schedules.activity_of(state, monster)
		if activity != Schedule.GRAZE and activity != Schedule.DRINK:
			continue
		if wild.held.has(monster) or wild.rage_of(monster) > 0:
			continue
		if (domination != null
				and (domination.is_encircled(monster) or domination.is_sealed(monster))):
			continue
		var from: Vector2i = state.entity(monster).tile
		var food: Vector2i = ForageWay.target(
			state.region,
			_ground.unringable(state.region),
			WildGround.blocked(state),
			from,
			activity,
		)
		if food != from:
			wild.chase(state, monster, food)


func tile_changed(_state: GameState, _tile: Vector2i) -> void:
	_ground.forget()
