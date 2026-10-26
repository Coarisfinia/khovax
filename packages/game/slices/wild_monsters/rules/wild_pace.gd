class_name WildPace
extends RefCounted
## A wild monster's pace (#961): rage makes its steps and its strikes come sooner, by RAGE_SPEED
## for every stack (WildMonsterFeature's steps and chase, WildAttackFeature's strikes).

## How much faster each stack of rage makes a wild monster (thousandths, #961): its steps and its
## strikes come this much more often. Its number is in Tuning (#1309).
const RAGE_SPEED: int = Tuning.RAGE_SPEED


## `ticks` (a wild monster's pace between two steps or strikes) made shorter by RAGE_SPEED for
## every stack of rage in `rage` (#961), never below one tick.
static func paced(ticks: int, rage: int) -> int:
	return maxi(Fixed.mul_div(ticks, Fixed.ONE, Fixed.ONE + rage * RAGE_SPEED), 1)
