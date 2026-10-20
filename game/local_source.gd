class_name LocalSource
extends CommandSource
## The local player's commands, from their devices through LocalInput: sampled when the driver is
## about to run a tick and put `delay` ticks ahead, like a network would deliver them. Each says
## whether this machine still waits for content (#816, Command.waiting).

var input: LocalInput
## The session whose world this machine plays, or none in tests that build a source alone.
var session: Session


func _init(local_input: LocalInput, played: Session = null) -> void:
	input = local_input
	slot = local_input.slot
	session = played


func poll(schedule: CommandSchedule, tick: int, state: GameState) -> void:
	# Sampled once per scheduled tick; a tick waiting for others doesn't sample again.
	if not schedule.has(tick + schedule.delay, slot):
		var given: Command = input.command(state)
		given.waiting = _waiting()
		schedule.put(tick + schedule.delay, slot, given)


## Whether some instance next to one a player is in isn't cached on this machine yet (#816): every
## machine plays every instance, so whoever walks out anywhere needs it here.
func _waiting() -> bool:
	if session == null or session.world == null:
		return false
	var world: World = session.world
	for instance_name: String in world.active():
		for target: String in world.instances[instance_name].region.exit_blueprints:
			if not world.source.cached(target):
				return true
	return false
