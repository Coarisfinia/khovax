class_name LocalSource
extends CommandSource
## The local player's commands, from their devices through LocalInput: sampled when the driver is
## about to run a tick and put `delay` ticks ahead, like a network would deliver them.

var input: LocalInput


func _init(local_input: LocalInput) -> void:
	input = local_input
	slot = local_input.slot


func poll(schedule: CommandSchedule, tick: int, state: GameState) -> void:
	# Sampled once per scheduled tick; a tick waiting for others doesn't sample again.
	if not schedule.has(tick + schedule.delay, slot):
		schedule.put(tick + schedule.delay, slot, input.command(state))
