class_name WildPace
extends RefCounted
## A wild monster's pace (#961): the host's difficulty (HostSettings, #1315) and rage make its
## steps and its strikes come sooner, by RAGE_SPEED for every stack of rage (WildMonsterFeature's
## steps and chase, WildAttackFeature's strikes, the hunts' and the foraging's steps).

## How much faster each stack of rage makes a wild monster (thousandths, #961): its steps and its
## strikes come this much more often. Its number is in Tuning (#1309).
const RAGE_SPEED: int = Tuning.RAGE_SPEED


## `ticks` (a wild monster's pace between two steps or strikes) at the host's difficulty in
## `state`, made shorter by RAGE_SPEED for every stack of rage in `rage` (#961), never below one
## tick.
static func paced(state: GameState, ticks: int, rage: int) -> int:
	var at_difficulty: int = HostSettings.enemy_ticks(state, ticks)
	return maxi(Fixed.mul_div(at_difficulty, Fixed.ONE, Fixed.ONE + rage * RAGE_SPEED), 1)
