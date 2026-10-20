class_name ExitFeature
extends Feature
## Walking out through an exit (#120, #154): a player standing on an exit tile, not mid-step, whose
## command moves towards the exit's side leaves the instance. Movement can't take them there (the
## region ends), so this raises an ExitTaken event instead, and the world moves them into the
## instance the exit leads to. Instances whose region has exits have it. While any machine still
## waits for content (#816, Command.waiting), nobody leaves: the player stands at the edge, and
## walks through once every machine has it.

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "exits"


func id() -> String:
	return ID


func requires() -> Array[String]:
	var needed: Array[String] = [MovementFeature.ID]
	return needed


func step(state: GameState, commands: Array[Command]) -> void:
	if Command.any_waiting(commands):
		return
	for player: Entity in state.entities:
		var target: String = pressed_out(state, player, commands)
		if not target.is_empty():
			var side: int = Command.of(commands, player.slot).move
			state.events.append(_taken(player, target, side))


## The blueprint `player` presses out towards with their command among `commands`: a player
## standing on an exit tile, not mid-step, moving towards the exit's side; "" otherwise. Views read
## it too (ExitHoldHint, #1010), so they show the hold exactly where the rule holds.
static func pressed_out(state: GameState, player: Entity, commands: Array[Command]) -> String:
	if player.slot == Entity.NO_SLOT:
		return ""
	var movement: MovementFeature = state.feature(MovementFeature.ID) as MovementFeature
	var command: Command = Command.of(commands, player.slot)
	var walk: Walk = movement.walk(player.id) if movement != null else null
	if command == null or walk == null or walk.is_moving():
		return ""
	return _exit_towards(state.region, player.tile, command.move)


## The event of `player` leaving through an exit to `target` on side `side`.
static func _taken(player: Entity, target: String, side: int) -> ExitTaken:
	return ExitTaken.new(player.id, player.slot, target, player.tile, side)


## The blueprint the exit on `tile` leading to side `side` goes to, or "".
static func _exit_towards(region: Region, tile: Vector2i, side: int) -> String:
	for i: int in region.exits.size():
		var exit: Vector3i = region.exits[i]
		if Vector2i(exit.x, exit.y) == tile and exit.z == side:
			return region.exit_blueprints[i]
	return ""
