extends RefCounted
## Tonics through an exit: a pondweed draught drunk on the forest's exit, and the player walks into
## the glade. Their wait between two drinks goes with them (#2334): they wait there until 10 s after
## the drink and no longer. So does the draught's Ward (#2343): they're still warded in the glade,
## at its strength, for the rest of its 30 s. A Ward, since a Mend for a player at full HP would be
## refused (#2311).

## The draught drunk, and its Ward's strength in thousandths and seconds (the potion design on
## #2049, section 2).
const DRAUGHT: String = "draught_pondweed"
const WARD: int = 200
const WARD_SECONDS: int = 30


func run(_tree: SceneTree) -> String:
	var world: World = World.new(BlueprintSource.new(), 3, FlowSteps.FOREST)
	var profile: Profile = Profile.new()
	profile.materials.assign({ DRAUGHT: 2 })
	var why: String = _drunk_on_exit(world, profile)
	if not why.is_empty():
		return why
	var drunk_at: int = world.tick
	_walk_in(world, FlowSteps.INTO_GLADE[-1])
	if world.instance_of(0) != FlowSteps.GLADE:
		return "walking southeast off the forest's exit didn't lead into the glade"
	var glade: GameState = world.instances[FlowSteps.GLADE]
	# It starts on the tick after the drink and lasts its 30 s from then.
	why = _still_warded(glade, drunk_at + 1 + WARD_SECONDS * Simulation.TICKS_PER_SECOND)
	if why.is_empty():
		why = _refused(profile, glade, "a draught just through an exit")
	while why.is_empty() and world.tick < drunk_at + DrinkingFeature.WAIT_TICKS - 1:
		world.step(FlowSteps.command(Command.NO_MOVE))
	if why.is_empty():
		why = _refused(profile, glade, "a draught through an exit a tick early")
	world.step(FlowSteps.command(Command.NO_MOVE))
	var refusal: String = TonicDrinking.problem(profile, glade, 0, DRAUGHT)
	if why.is_empty() and not refusal.is_empty():
		why = "a draught through an exit was refused once the wait was over: " + refusal
	return why


## Walks player 0 of `world` onto the forest's exit into the glade and has them drink a DRAUGHT
## from `profile` there; returns why that went wrong, or "".
static func _drunk_on_exit(world: World, profile: Profile) -> String:
	for direction: int in FlowSteps.INTO_GLADE.slice(0, -1):
		_walk_in(world, direction)
	var forest: GameState = world.instances[FlowSteps.FOREST]
	var refusal: String = TonicDrinking.drink(profile, forest, 0, DRAUGHT)
	if not refusal.is_empty() or profile.outbox.entries.size() != 1:
		return "a draught on the forest's exit was refused or posted nothing: " + refusal
	var command: Command = Command.new()
	profile.outbox.entries[0].fill(command)
	var _dropped: bool = profile.outbox.drop(profile.outbox.entries[0].id)
	var commands: Array[Command] = [command]
	world.step(commands)
	return ""


## Why the player in slot 0 of `state` isn't warded at WARD with its time running out on the world
## tick `ends`, or "".
static func _still_warded(state: GameState, ends: int) -> String:
	var player: Entity = state.player(0)
	var ward: int = TonicEffectReads.strength_of(state, player.id, TonicEffectsFeature.WARD)
	var effects: TonicEffectsFeature = state.feature(TonicEffectsFeature.ID) as TonicEffectsFeature
	var effect: TonicEffect = effects.effect_of(player.id)
	var left: int = effect.ticks if effect != null else 0
	if ward != WARD or state.world_tick + left != ends:
		return "a Ward through an exit was %d, running out on tick %d, not %d on tick %d" % [
			ward,
			state.world_tick + left,
			WARD,
			ends,
		]
	return ""


## Why drinking a DRAUGHT from `profile` for player 0 in `state`, which `what` names, wasn't
## refused, or spent or posted something; "" when it was refused and changed nothing.
static func _refused(profile: Profile, state: GameState, what: String) -> String:
	var held: Dictionary[String, int] = {}
	held.assign(profile.materials)
	var refusal: String = TonicDrinking.drink(profile, state, 0, DRAUGHT)
	if refusal.is_empty() or profile.materials != held or not profile.outbox.entries.is_empty():
		return "%s wasn't refused before anything was spent: %s" % [what, refusal]
	return ""


## Walks the player in slot 0 of `world` one whole step in `direction`, through an exit there.
static func _walk_in(world: World, direction: int) -> void:
	world.step(FlowSteps.command(direction))
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(FlowSteps.command(Command.NO_MOVE))
