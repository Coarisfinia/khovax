class_name ExitFeature
extends Feature
## Walking out through an exit (#120, #154): a player standing on an exit tile, not mid-step, whose
## command moves towards the exit's side leaves the instance. Movement can't take them there (the
## region ends), so this raises an ExitTaken event instead, and the world moves them into the
## instance the exit leads to. Instances whose region has exits have it.


func id() -> int:
	return Features.EXITS


func requires() -> Array[int]:
	var needed: Array[int] = [Features.MOVEMENT]
	return needed


func step(state: GameState, commands: Array[Command]) -> void:
	var movement: MovementFeature = state.feature(Features.MOVEMENT) as MovementFeature
	for player: Entity in state.entities:
		if player.slot == Entity.NO_SLOT:
			continue
		var command: Command = Command.of(commands, player.slot)
		var walk: Walk = movement.walk(player.id)
		if command == null or walk == null or walk.is_moving():
			continue
		var target: String = _exit_towards(state.region, player.tile, command.move)
		if not target.is_empty():
			state.events.append(_taken(player, target))


## The event of `player` leaving through an exit to `target`.
static func _taken(player: Entity, target: String) -> ExitTaken:
	return ExitTaken.new(player.id, player.slot, target)


## The blueprint the exit on `tile` leading to side `side` goes to, or "".
static func _exit_towards(region: Region, tile: Vector2i, side: int) -> String:
	for i: int in region.exits.size():
		var exit: Vector3i = region.exits[i]
		if Vector2i(exit.x, exit.y) == tile and exit.z == side:
			return region.exit_blueprints[i]
	return ""
