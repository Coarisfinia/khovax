class_name CommandSource
extends RefCounted
## Where one player slot's commands come from (#38): the local player's input, later a network
## peer or a replay. The driver polls every source before each tick and doesn't care which kind
## it is; a source puts what it knows into the schedule.

## The player slot this source speaks for.
var slot: int = 0


## Puts this source's commands into `schedule`, as far as it knows them. Called before the driver
## tries to run `tick`, again while that tick waits for a missing command.
func poll(_schedule: CommandSchedule, _tick: int, _state: GameState) -> void:
	return
