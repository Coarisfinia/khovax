extends RefCounted
## World flow (#120, #139): the instances hang together through exits in their region pieces.
## Every exit leads to a blueprint that exists and has the way back on the opposite side; the basic
## instance's east edge leads to the glade; the glade keeps its layout, so its way back stays west
## for every seed, and arranging its pieces never covers the tile outside it. Broken exit lines are
## refused. The web is validated as a whole (#143): every blueprint loads as a full instance, every
## exit can be walked to from the players' starts for every seed, and every blueprint with exits
## can be reached from the starting instance. In every region file and region piece, the walkable
## tiles hang together, so a blocking tile never cuts a part off, and every tile under a crown
## (a decoration reaching over its neighbours, #232) fits beneath it. The world holds several loaded
## instances and
## steps the ones a player is in (#148), and purges one left behind for an hour of play (#212).
## Each player's companion (#338) joins them, roams within its reach and follows them through exits.
## A player swaps it for another monster they carry (#55), by a tap or a click on the roster at the
## top left of the screen, which shows the monsters they carry and which is their companion (#540).
## The world raises that a player entered an instance (#370) when they start in it and whenever
## they walk through an exit into another, and only then. A rule can change a tile of a loaded
## instance in place (#530), which the world keeps through its save data. A world flag chooses a
## blueprint's variant, and setting it purges the instance once nobody is in it (#529). A named
## event sets its own flag, and the corrupted glade's corrupting monster emits one when it falls,
## which purifies the glade once nobody is in it (#541). The first time a named event sets its
## flag, the world raises a world-changing moment, once (#499).

const SEEDS: int = 40
## Seeds every blueprint is loaded with as a full instance: fewer, since that includes the load
## test's big region.
const INSTANCE_SEEDS: int = 6
## Where _check_documents' region document has its stump, turned and set lower (#232) by hand.
const STUMP: Vector2i = Vector2i(0, -1)
## Where it has its water, made walkable by hand.
const WATER: Vector2i = Vector2i(0, 1)
## A made-up tile kind number for _check_room_caught's crown: no blueprint has it.
const CROWN_KIND: int = 250
## The screen _check_roster lays the roster out for.
const ROSTER_SCREEN: Vector2 = Vector2(1280.0, 720.0)

## The made-up crown _check_room_caught gives CROWN_KIND.
var _crown: TileBlueprint
## The instances player 0 entered while _walk_in walked them, in order (#370).
var _entered: Array[String] = []


func run(tree: SceneTree) -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var problem: String = InstanceBlueprints.exit_problem(instance_name)
		if not problem.is_empty():
			return problem
	var basic: Region = InstanceBlueprints.region_of(InstanceBlueprints.BASIC, 0)
	var east: bool = basic.exits.size() == 1 and basic.exits[0] == Vector3i(3, -2, 0)
	if not east or basic.exit_blueprints[0] != InstanceBlueprints.GLADE:
		return "the basic instance's east edge doesn't lead to the glade: %s" % [basic.exits]
	var steps: Array[Callable] = [
		_check_glade_exit,
		_check_refused,
		_check_exits_reachable,
		_check_pieces_connected,
		_check_room,
		_check_web_connected,
		_check_world,
		_check_documents,
		_check_walk_through,
		_check_companions,
		_check_swaps,
		_check_purge,
		_check_flags,
		_check_corruption,
		_check_story_beat,
		_check_start_kept,
		_check_sent_to_spawn,
		_check_layout,
		_check_tile_changed,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return await _check_roster(tree)


## A tile changed in place (#530): a rule turns the ground beside the player into rock in the loaded
## basic instance. The region has it at once, nobody can stand on it, the player's sight is worked
## out again around it, the tick's events say what it was and what it is, and the hash tells the
## world from one left alone. The same kind, a tile off the region or a kind no blueprint has
## change nothing. Through its save data and back, the world keeps the rock without raising the
## change again, hashes the same and goes on alike; a save with a changed tile that can't be is
## refused.
func _check_tile_changed() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	var untouched: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	world.step(_still())
	untouched.step(_still())
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var beside: Vector2i = _free_ground_beside(basic, world.player(0).tile)
	var seen: Array[Vector2i] = FlowSteps.sight_of(basic)
	var raised: int = basic.events.size()
	var refused: bool = basic.change_tile(beside, Region.GROUND) or basic.change_tile(
		Vector2i(99, 99),
		Region.BLOCKED,
	)
	refused = refused or basic.change_tile(beside, CROWN_KIND) or basic.events.size() != raised
	if refused or not basic.change_tile(beside, Region.BLOCKED):
		return "a tile changed to its own kind, off the region or to no kind, or not to rock"
	var changed: TileChanged = basic.events[basic.events.size() - 1] as TileChanged
	var told: bool = changed != null and changed.tile == beside and changed.region == basic.region
	told = told and changed.was == Region.GROUND and changed.kind == Region.BLOCKED
	if not told or basic.region.is_walkable(beside) or world.state_hash() == untouched.state_hash():
		return "the tile changed in place wasn't told, isn't rock, or isn't hashed"
	var sight: Array[Vector2i] = FogFeature.sight(
		basic.region,
		world.player(0).tile,
		FogFeature.SIGHT_RADIUS,
		basic.next_door,
	)
	if FlowSteps.sight_of(basic) == seen or FlowSteps.sight_of(basic) != sight:
		return "the player's sight wasn't worked out again around the rock"
	return _check_tile_change_saved(world, beside)


## `world`, whose basic instance has rock changed in place on `rock`, goes through its save data and
## back with it, raising nothing, and both go on alike; a changed tile that can't be is refused.
func _check_tile_change_saved(world: World, rock: Vector2i) -> String:
	var data: Dictionary = WorldData.of(world)
	var reloaded: World = WorldData.to_world(data, BlueprintSource.new())
	if not reloaded.problem.is_empty() or reloaded.state_hash() != world.state_hash():
		return "the world didn't go through its save data with a changed tile: " + reloaded.problem
	var basic: GameState = reloaded.instances[InstanceBlueprints.BASIC]
	if basic.region.terrain[rock] != Region.BLOCKED or not basic.events.is_empty():
		return "the reloaded world lost the rock, or raised its change again"
	for _tick: int in 60:
		world.step(_moving(posmod(world.tick, Hex.DIRECTIONS.size())))
		reloaded.step(_moving(posmod(reloaded.tick, Hex.DIRECTIONS.size())))
	if reloaded.state_hash() != world.state_hash():
		return "the reloaded world went another way than the one with the tile changed"
	var saved: Array = data["instances"]
	var first: Dictionary = saved[0]
	var state: Dictionary = first["state"]
	var source: BlueprintSource = BlueprintSource.new()
	for bad: Array in [[rock.x, rock.y, CROWN_KIND], [rock.x, rock.y], [99, 99, Region.WATER]]:
		state["changed_tiles"] = bad
		var problem: String = WorldData.to_world(data, source).problem
		if problem.is_empty():
			return "a save with the changed tiles %s wasn't refused" % [bad]
	return ""


## A ground tile next to `tile` in `state` that nothing stands on.
static func _free_ground_beside(state: GameState, tile: Vector2i) -> Vector2i:
	for direction: Vector2i in Hex.DIRECTIONS:
		var next: Vector2i = tile + direction
		var taken: bool = false
		for each: Entity in state.entities:
			taken = taken or each.tile == next
		if state.region.terrain.get(next, -1) == Region.GROUND and not taken:
			return next
	return tile


## A player whose HP runs out, here beside the basic instance's wild monster, is sent back to the
## world's spawn (#457): onto their start in the starting instance, as a new entity at full HP.
func _check_sent_to_spawn() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var first: Entity = world.player(0)
	var wild: WildMonsterFeature = basic.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	first.tile = basic.entity(wild.monsters[0]).tile + Hex.DIRECTIONS[0]
	var start: Vector2i = basic.region.starts[0]
	for _tick: int in WildAttackFeature.STRIKE_TICKS * 60:
		world.step(FlowSteps.command(Command.NO_MOVE))
		if world.player(0).id != first.id:
			break
	var back: Entity = world.player(0)
	var health: HealthFeature = basic.feature(Features.HEALTH) as HealthFeature
	if back.id == first.id or back.tile != start or world.instance_of(0) != world.start_name:
		return "a player out of HP wasn't sent back onto their start: %s" % back.tile
	if health.hp_of(basic, back.id) != HealthFeature.PLAYER_HP:
		return "a player sent back to the spawn isn't at full HP"
	return ""


## Walking through exits (#154): from the basic instance's start, onto its exit on (3, -2) and on
## east into the glade, arriving on the glade's way back; then west again, back onto the basic
## instance's exit, while the glade stays loaded for the next visit. The player enters the basic
## instance on the first tick, then the glade, then the basic instance again, and nothing else.
func _check_walk_through() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	_entered.clear()
	# From the start at (1, -1): east, northeast onto the exit on (3, -2), and east once more.
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var arrived: Entity = world.player(0)
	if glade == null or world.instance_of(0) != InstanceBlueprints.GLADE:
		return "walking east out of the basic instance didn't lead into the glade"
	if arrived.tile != Vector2i(
		-2,
		0,
	) or world.instances[InstanceBlueprints.BASIC].player(0) != null:
		return "the player arrived on %s, not the glade's way back" % arrived.tile
	_walk_in(world, 3)
	var back: Entity = world.player(0)
	if world.instance_of(0) != InstanceBlueprints.BASIC or back.tile != Vector2i(3, -2):
		return "walking west out of the glade didn't lead back onto the basic instance's exit"
	if world.instances[InstanceBlueprints.GLADE] != glade:
		return "coming back loaded a new glade instead of the same one"
	var basic: String = InstanceBlueprints.BASIC
	var expected: Array[String] = [basic, InstanceBlueprints.GLADE, basic]
	if _entered != expected:
		return "walking there and back entered %s, not %s" % [_entered, expected]
	return ""


## Companions (#338): the player who brings one is joined by it on the first tick, beside them; the
## other player, who brings none, isn't. A weak species' reach is shorter than a strong one's.
## Standing, the player watches it roam within its reach; walking off, they're never more than a
## step out of it, and only players color the trail. The player walks through it, and it follows
## them out through the exit into the glade, while the one in the basic instance goes.
func _check_companions() -> String:
	var world: World = World.new(
		BlueprintSource.new(),
		3,
		InstanceBlueprints.BASIC,
		2,
		["storm_finch"],
	)
	world.step(_still())
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var companions: CompanionFeature = basic.feature(Features.COMPANIONS) as CompanionFeature
	var companion: Entity = basic.entity(companions.companion_of(0))
	if companion == null or companions.companion_of(1) != 0:
		return "only the player bringing a companion should be joined by one"
	if Hex.distance(companion.tile, world.player(0).tile) != 1:
		return "the companion joined on %s, not beside its player" % companion.tile
	if companions.reaches["moss_toad"] >= companions.reaches["storm_finch"]:
		return "the weaker moss toad doesn't stay closer than the storm finch"
	var reach: int = companions.reach_of_companion(companion.id)
	var roamed: Dictionary[Vector2i, bool] = {}
	for _tick: int in 400:
		world.step(_still())
		roamed[companion.tile] = true
		if Hex.distance(companion.tile, world.player(0).tile) > reach:
			return "the companion roamed out of its reach of %d" % reach
	if roamed.size() < 3:
		return "the companion didn't roam: it stood on %s" % [roamed.keys()]
	for direction: int in [3, 3, 0, 0, 3, 0]:
		for tick: int in MovementFeature.MOVE_TICKS:
			world.step(_moving(direction) if tick == 0 else _still())
			if Hex.distance(companion.tile, world.player(0).tile) > reach + 1:
				return "the companion fell more than a step behind its walking player"
	var trails: TrailFeature = basic.feature(Features.TRAIL) as TrailFeature
	for tile: Vector2i in trails.shared.tiles:
		if trails.shared.tiles[tile] == companion.id:
			return "the companion colored %s on the trail" % tile
	return _check_companion_passed(world, companion)


## Standing east of its player, the companion lets them walk through, and it follows them out
## through the exit into the glade, while the one left in the basic instance goes.
func _check_companion_passed(world: World, companion: Entity) -> String:
	var start: Vector2i = world.player(0).tile
	companion.tile = start + Hex.DIRECTIONS[0]
	world.step(_moving(0))
	if world.player(0).tile != start + Hex.DIRECTIONS[0]:
		return "the companion stopped its own player"
	_idle_until(world, world.tick + MovementFeature.MOVE_TICKS)
	# From (2, -1), northeast onto the exit on (3, -2), and east once more.
	for direction: int in [1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var followed: CompanionFeature = glade.feature(Features.COMPANIONS) as CompanionFeature
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var left: CompanionFeature = basic.feature(Features.COMPANIONS) as CompanionFeature
	if world.instance_of(0) != InstanceBlueprints.GLADE or followed.companion_of(0) == 0:
		return "the companion didn't follow its player into the glade"
	if left.companion_of(0) != 0 or basic.entity(companion.id) != null:
		return "the companion stayed in the basic instance its player left"
	return ""


## Manual swaps (#55): a player carrying a storm finch and a moss toad is joined by the finch.
## Swapping to the companion they have or to a place they carry nothing in does nothing; swapping
## to the toad raises that they chose it, and the next tick the toad has taken the finch's place.
## A recorded session with the swaps plays back the same, and the choice goes through the world's
## save data and back. With swapping switched off, a swap does nothing. The toad follows its player
## into the glade.
func _check_swaps() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	world.set_carried([PackedStringArray(["storm_finch", "moss_toad"])])
	var recorded: Replay = Replay.new(InstanceBlueprints.BASIC, 3)
	recorded.begin(world)
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	var companions: CompanionFeature = basic.feature(Features.COMPANIONS) as CompanionFeature
	var joined: bool = _swap_in(world, recorded, Command.NO_SWAP) == 0
	if not joined or companions.species_of(companions.companion_of(0)) != "storm_finch":
		return "a player carrying two monsters wasn't joined by the first"
	if _swap_in(world, recorded, 1) + _swap_in(world, recorded, 3) != 0:
		return "swapping to the companion they have, or to an empty place, raised a swap"
	if _swap_in(world, recorded, 2) != 1 or world.companions[0] != "moss_toad":
		return "swapping to the second carried monster didn't make it the companion"
	var finch: int = companions.companion_of(0)
	var _settled: int = _swap_in(world, recorded, Command.NO_SWAP)
	var toad: int = companions.companion_of(0)
	if companions.species_of(toad) != "moss_toad" or basic.entity(finch) != null:
		return "the chosen moss toad didn't take the storm finch's place beside its player"
	recorded.finish(world)
	return _check_swap_kept(world, recorded)


## The swaps `recorded` in `world` play back the same, and the choice is kept: through the save
## data, with swapping switched off, and into the glade.
func _check_swap_kept(world: World, recorded: Replay) -> String:
	var problem: String = ReplayFile.parse(ReplayFile.to_text(recorded)).play()
	if not problem.is_empty():
		return "a recorded session with swaps didn't play back: " + problem
	var restored: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	var kept: bool = restored.companions == world.companions and restored.carried == world.carried
	if not restored.problem.is_empty() or not kept:
		return "the chosen companion didn't go through the save data and back: " + restored.problem
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	basic.set_enabled(Features.COMPANION_SWAPS, false)
	if _swap_in(world, null, 1) != 0 or world.companions[0] != "moss_toad":
		return "a player swapped with swapping switched off"
	basic.set_enabled(Features.COMPANION_SWAPS, true)
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var followed: CompanionFeature = glade.feature(Features.COMPANIONS) as CompanionFeature
	if followed.species_of(followed.companion_of(0)) != "moss_toad":
		return "the chosen companion didn't follow its player into the glade"
	return ""


## Steps `world` once with player 0 standing and swapping to `swap` (or Command.NO_SWAP), recording
## the tick into `recorded` if given; returns how many swaps their instance raised.
func _swap_in(world: World, recorded: Replay, swap: int) -> int:
	var command: Command = Command.new()
	command.swap = swap
	var commands: Array[Command] = [command]
	world.step(commands)
	if recorded != null:
		recorded.record(world, commands)
	var chosen: int = 0
	for event: RefCounted in world.instances[world.instance_of(0)].events:
		chosen += 1 if event is CompanionChosen else 0
	return chosen


## The roster (#540) in the main scene: carrying a storm finch and a moss toad, it shows both at
## the top left, apart, in that order, the finch as the companion, and the quest list starts below
## it. A tap on the toad's square swaps to it in the local player's next command without starting
## the touch stick, and a left click on the finch's swaps to the finch; while the game hears no
## input (the menu is open) a tap swaps nothing. Swapped to the toad, the roster shows it as the
## companion.
func _check_roster(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree)
	var driver: GameDriver = FlowGame.held_driver(main)
	driver.world.set_carried([PackedStringArray(["storm_finch", "moss_toad"])])
	var roster: RosterHud = main.get_node("Hud/RosterHud") as RosterHud
	roster.show_state()
	# Laid out for a desktop screen: the headless one is tiny. The flow steps it by hand from here.
	roster.set_process(false)
	roster.lay_out_in(ROSTER_SCREEN)
	var result: String = _roster_shown(main, roster)
	if result.is_empty():
		result = _roster_swaps(main, roster, driver)
	main.queue_free()
	await tree.process_frame
	return result


## The roster shows the finch and the toad at the top left, apart, the finch as the companion, and
## the quest list starts below it.
func _roster_shown(main: Node, roster: RosterHud) -> String:
	var carried: PackedStringArray = ["storm_finch", "moss_toad"]
	if roster.shown != carried or roster.companion_place != 0:
		return "the roster doesn't show the carried monsters in order, the first as the companion"
	var corner: Rect2 = Rect2(Vector2.ZERO, ROSTER_SCREEN / 3.0)
	var first: Rect2 = roster.rect_of(0)
	if not corner.encloses(roster.rect_of(1)) or first.intersects(roster.rect_of(1)):
		return "the roster's squares %s and %s aren't apart in the top left corner %s" % [
			first,
			roster.rect_of(1),
			corner,
		]
	if RosterHud.initials_of("Storm Finch") != "SF":
		return "the storm finch's square doesn't show its initials"
	var quests: QuestListView = main.get_node("Hud/QuestList") as QuestListView
	quests._lay_out(1.0)
	# A position is kept in single precision.
	if quests.position.y + 0.01 < roster.bottom() or roster.bottom() <= first.end.y:
		return "the quest list at %s doesn't start below the roster's %f" % [
			quests.position,
			roster.bottom(),
		]
	return ""


## Taps and clicks on the roster's squares swap, but not while the game hears no input, and the
## swap made shows.
func _roster_swaps(main: Node, roster: RosterHud, driver: GameDriver) -> String:
	var stick: TouchStick = main.get_node("Hud/TouchStick") as TouchStick
	_tap_roster(roster, roster.rect_of(1).get_center(), false)
	var tapped: int = driver.input.command(driver.state).swap
	if tapped != 2 or stick.is_held():
		return "a tap on the toad's square didn't swap to it alone, or started the touch stick"
	_tap_roster(roster, roster.rect_of(0).get_center(), true)
	if driver.input.command(driver.state).swap != 1:
		return "a click on the finch's square didn't swap to it"
	driver.input.blocked = true
	_tap_roster(roster, roster.rect_of(1).get_center(), false)
	driver.input.blocked = false
	if driver.input.command(driver.state).swap != Command.NO_SWAP:
		return "a tap on the roster swapped while the game heard no input"
	var _chosen: int = _swap_in(driver.world, null, 2)
	roster.show_state()
	if roster.companion_place != 1:
		return "the roster didn't show the toad as the companion once swapped to it"
	return ""


## Touches the roster at `at` and lifts the finger, or left clicks there with the mouse (`click`).
static func _tap_roster(roster: RosterHud, at: Vector2, click: bool) -> void:
	_press_roster(roster, at, click, true)
	_press_roster(roster, at, click, false)


## Presses (`pressed`) or lets go at `at` on the roster's screen: a finger, or the mouse's left
## button (`click`).
static func _press_roster(roster: RosterHud, at: Vector2, click: bool, pressed: bool) -> void:
	if click:
		var button: InputEventMouseButton = InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = at
		button.pressed = pressed
		roster.get_viewport().push_input(button)
		return
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = at
	touch.pressed = pressed
	roster.get_viewport().push_input(touch)


## Purging (#212): the glade, left behind, raises nothing in the ticks it doesn't step (#386), stays
## loaded until nobody has been in it for an hour of play, and is purged the tick after; its next
## visit loads it at generation 1, from another seed, and entering it resets the count. The world
## goes through its save data and back with the tick the glade was left and its generation, and
## hashes the same.
func _check_purge() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	var first_seed: int = world.seed_for(InstanceBlueprints.GLADE)
	for direction: int in [0, 1, 0, 3]:
		_walk_in(world, direction)
	var left: int = world.left_at.get(InstanceBlueprints.GLADE, -1)
	if left < 0 or world.instance_of(0) != InstanceBlueprints.BASIC:
		return "walking into the glade and back didn't leave it behind"
	var glade_left: GameState = world.instances[InstanceBlueprints.GLADE]
	glade_left.events.append(RefCounted.new())
	world.step(_still())
	if not glade_left.events.is_empty():
		return "the glade, left behind, kept its events into a tick it didn't step (#386)"
	_idle_until(world, left + World.PURGE_TICKS - 1)
	if not world.instances.has(InstanceBlueprints.GLADE):
		return "the glade was purged before an hour had passed"
	world.step(_still())
	if world.instances.has(InstanceBlueprints.GLADE) or world.generation("glade") != 1:
		return "the glade wasn't purged an hour after it was left behind"
	_walk_in(world, 0)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var reseeded: bool = glade != null and glade.rng_seed == world.seed_for("glade")
	if not reseeded or glade.rng_seed == first_seed or world.left_at.has("glade"):
		return "the glade didn't come back at generation 1 from a new seed, or kept its count"
	return _check_left_again(world, left + World.PURGE_TICKS)


## Leaving the glade again, after it was purged at `purged`, starts a new count, and the world goes
## through its save data and back with both.
func _check_left_again(world: World, purged: int) -> String:
	_walk_in(world, 3)
	if world.left_at.get(InstanceBlueprints.GLADE, -1) <= purged:
		return "leaving the glade again didn't start a new count"
	var reloaded: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	var kept: bool = reloaded.left_at == world.left_at and reloaded.generations == world.generations
	if not reloaded.problem.is_empty() or not kept or reloaded.state_hash() != world.state_hash():
		return "the world didn't go through its save data with its purges: " + reloaded.problem
	return ""


## World flags (#529): with RisingSource, setting RISEN chooses the arena's region as the glade's
## variant. Set while the player is in the glade, it changes the hash but not the glade; through its
## save data and back the world keeps the flag and the glade's old variant. The tick after the
## player
## walks out, the glade is purged, and it comes back at generation 1 from the arena's region, for
## the world and its layout alike. Clearing the flag purges it again once nobody is in it, and
## setting a flag that is already set changes nothing.
func _check_flags() -> String:
	var world: World = World.new(RisingSource.new(), 3, InstanceBlueprints.BASIC)
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var before: int = world.state_hash()
	world.set_flag(RisingSource.RISEN)
	world.set_flag(RisingSource.RISEN)
	var once: bool = world.flags.size() == 1 and world.flags[0] == RisingSource.RISEN
	if not once or world.state_hash() == before:
		return "setting a flag didn't set it once, or isn't hashed"
	world.step(_still())
	if world.instances.get(InstanceBlueprints.GLADE) != glade or world.variant_of("glade") != "":
		return "a flag changed the glade while the player was in it"
	var reloaded: World = WorldData.to_world(WorldData.of(world), RisingSource.new())
	var kept: bool = reloaded.flags == world.flags and reloaded.variant_of("glade") == ""
	if not reloaded.problem.is_empty() or not kept or reloaded.state_hash() != world.state_hash():
		return "the world didn't go through its save data with its flag: " + reloaded.problem
	_walk_in(world, 3)
	if world.instances.has(InstanceBlueprints.GLADE) or world.generation("glade") != 1:
		return "the glade wasn't purged once the player left it after the flag"
	var risen: GameState = world.instance(InstanceBlueprints.GLADE)
	var arena: Region = InstanceBlueprints.region_of("glade", world.seed_for("glade"), "arena")
	var tiles: Array[Vector2i] = risen.region.sorted_tiles()
	if world.variant_of("glade") != "arena" or tiles != arena.sorted_tiles():
		return "the glade didn't come back from its variant, the arena's region"
	# The arena's region has no way back to the basic instance, which only a layout worked out from
	# the glade's new region notices.
	if world.layout_problem().is_empty():
		return "the world's layout still has the glade's old region"
	world.set_flag(RisingSource.RISEN, false)
	world.step(_still())
	if world.instances.has(InstanceBlueprints.GLADE) or world.generation("glade") != 2:
		return "clearing the flag didn't purge the glade, which nobody is in"
	if world.instance(InstanceBlueprints.GLADE) == null or world.variant_of("glade") != "":
		return "the glade didn't come back as itself once the flag was cleared"
	return ""


## A corrupted instance (#541): with the glade's corrupting flag set, the player walks into the
## corrupted glade. Its corrupting monster, felled inside a tick, emits its event, and the world
## sets that event's flag, which chooses the purified glade over the corrupted one; the glade stays
## corrupted while the player is in it, and the world goes through its save data and back with the
## flag and the corrupted glade. The tick the player walks out, it's purged, and it comes back as
## the plain glade.
func _check_corruption() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	world.set_flag(InstanceBlueprints.CORRUPTED_GLADE)
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	if glade == null or world.variant_of("glade") != InstanceBlueprints.CORRUPTED_GLADE:
		return "the player didn't walk into the corrupted glade"
	var felling: Felling = Felling.new()
	glade.features.append(felling)
	world.step(_still())
	glade.features.erase(felling)
	var purified_flag: String = World.EVENT_FLAG + InstanceBlueprints.GLADE_PURIFIED
	var emitted: bool = felling.felled > 0 and world.flags.has(purified_flag)
	if not emitted or InstanceBlueprints.variant("glade", world.flags) != "":
		return "felling the corrupting monster didn't set its event's flag for the plain glade"
	var changes: Array[WorldChanged] = _world_changes(world)
	if changes.size() != 1 or changes[0].event_name != InstanceBlueprints.GLADE_PURIFIED:
		return "purifying the glade wasn't raised as one world-changing moment"
	world.step(_still())
	if world.instances.get(InstanceBlueprints.GLADE) != glade:
		return "the glade was purified with the player in it"
	var reloaded: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	var kept: bool = reloaded.variant_of("glade") == InstanceBlueprints.CORRUPTED_GLADE
	if not kept or reloaded.state_hash() != world.state_hash():
		return "the world didn't go through its save data with its flags: " + reloaded.problem
	_walk_in(world, 3)
	if world.instances.has(InstanceBlueprints.GLADE) or world.generation("glade") != 1:
		return "the glade wasn't purged once the player left it"
	if world.instance(InstanceBlueprints.GLADE) == null or world.variant_of("glade") != "":
		return "the glade didn't come back purified, as the plain glade"
	return ""


## A story beat (#499): a rule raising the named event BEAT, twice a tick, changes the world once.
## The first tick sets its flag and raises one WorldChanged naming the event and its flag; the next
## ticks raise the event again, which changes nothing and raises nothing.
func _check_story_beat() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	world.instances[InstanceBlueprints.BASIC].features.append(Beat.new())
	world.step(_still())
	var flag: String = World.EVENT_FLAG + Beat.BEAT
	var changes: Array[WorldChanged] = _world_changes(world)
	var once: bool = changes.size() == 1 and changes[0].event_name == Beat.BEAT
	if not once or changes[0].flag != flag or " ".join(world.flags) != flag:
		return "a story beat didn't set its flag and raise one world-changing moment"
	world.step(_still())
	if not _world_changes(world).is_empty() or " ".join(world.flags) != flag:
		return "a story beat raised again changed the world again"
	return ""


## The world-changing moments (WorldChanged, #499) the world raised in its last tick, in order.
func _world_changes(world: World) -> Array[WorldChanged]:
	var changes: Array[WorldChanged] = []
	for event: RefCounted in world.events:
		if event is WorldChanged:
			changes.append(event as WorldChanged)
	return changes


## The starting instance is never purged (#212), however long the player stays in the glade.
func _check_start_kept() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.BASIC)
	for direction: int in [0, 1, 0]:
		_walk_in(world, direction)
	_idle_until(world, world.tick + World.PURGE_TICKS + 1)
	if not world.instances.has(InstanceBlueprints.BASIC) or world.generation("basic") != 0:
		return "the starting instance was purged"
	return ""


## Steps the world with player 0 standing still until its tick is `until`.
func _idle_until(world: World, until: int) -> void:
	while world.tick < until:
		world.step(_still())


## Walks player 0 one step in `direction`, through the world, until they stand still again, noting
## the instances they entered meanwhile.
func _walk_in(world: World, direction: int) -> void:
	world.step(_moving(direction))
	_note_entered(world)
	for _tick: int in MovementFeature.MOVE_TICKS + 1:
		world.step(_still())
		_note_entered(world)


## Notes the instances player 0 entered in the world's last tick.
func _note_entered(world: World) -> void:
	for event: RefCounted in world.events:
		if event is InstanceEntered and (event as InstanceEntered).slot == 0:
			_entered.append((event as InstanceEntered).instance)


func _moving(direction: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(direction)]
	return commands


## Region documents (#145): tile (0, 0) is the middle tile of the middle row, the legend's symbols
## become connectors, exits, named species and tile kinds (#116, by any one character, an emoji
## too) on their tiles, a kind's decoration turned by hand (#231) and its walkable trait overridden
## for one tile (#201) where the legend says so, both of which turn along with the region and move
## with a placed piece, and a grid without a single middle, a symbol the legend doesn't explain, a
## clause it doesn't know, a turn past five sixths or a place without an id (#339) is refused. A
## place's symbol can name its tile kind too (#349), which must be walkable. The glade's pieces
## have forest.
func _check_documents() -> String:
	var tiles: String = "# T\n\n## Tiles\n\n```\n%s\n```\n\n## Legend\n\n%s\n"
	var legend: String = "- `j`: joins another piece to the west\n"
	legend += "- `x`: exit to the east, to glade\n- `B`: a wild monster, always storm_finch\n"
	legend += "- `🌲`: forest\n"
	legend += "- `w`: water, walkable\n- `🪓`: stump, turned 3, not walkable, height 30"
	var grid: String = " 🪓 🌲\nj 1 x\n B w"
	var region: Region = RegionDocument.parse(tiles % [grid, legend])
	var expected: bool = region.starts.size() == 1 and region.starts[0] == Vector2i.ZERO
	expected = expected and region.connectors == [Vector3i(-1, 0, 3)]
	expected = expected and region.exits.size() == 1 and region.exits[0] == Vector3i(1, 0, 0)
	expected = expected and _species_on(region, Vector2i(-1, 1)) == "storm_finch"
	var forest: int = TileKinds.number_of("forest")
	expected = expected and region.terrain[Vector2i(1, -1)] == forest
	expected = expected and region.terrain[Vector2i(0, 1)] == Region.WATER
	expected = expected and region.terrain[STUMP] == TileKinds.number_of("stump")
	var plain: String = tiles % [
		grid,
		legend.replace(", not walkable", "").replace(", walkable", ""),
	]
	expected = expected and _turned_and_overridden(region, plain)
	if not region.problem.is_empty() or not expected:
		return "a region document didn't read as drawn: %s" % region.problem
	var refusals: Dictionary[String, String] = {
		tiles % [". .\n. .", ""]: "the tiles need an odd",
		tiles % ["1 z .", ""]: "the legend doesn't explain `z`",
		tiles % ["1 🌲 .", "- `🌲`: jungle"]: "the legend doesn't explain `🌲`",
		tiles % ["1 🪓 .", "- `🪓`: stump, turned 6"]: "tile (0, 0)'s turn 6",
		tiles % ["1 🪓 .", "- `🪓`: stump, flying"]: "the legend doesn't explain `🪓`",
		tiles % ["1 🪓 .", "- `🪓`: stump, turned 2, turned 4"]: "tile (0, 0) says its turn",
		tiles % ["1 🪓 .", "- `🪓`: stump, walkable, not walkable"]: "tile (0, 0) says its turn",
		tiles % ["1 🪓 .", "- `🪓`: stump, height 1001"]: "tile (0, 0)'s height 1001",
		tiles % ["1 🪓 .", "- `🪓`: stump, height 2, height 3"]: "tile (0, 0) says its turn",
		tiles % ["1 b .", "- `b`: a beach; stepping here reaches the place Beach"]: (
			"the legend doesn't explain `b`"
		),
		tiles % ["1 b .", "- `b`: boulder; stepping here reaches the place beach"]: (
			"trigger (0, 0) isn't on ground"
		),
	}
	for text: String in refusals:
		var problem: String = RegionDocument.parse(text).problem
		if not problem.begins_with(refusals[text]):
			return "expected a refusal starting %s, got: %s" % [refusals[text], problem]
	var thicket: String = FileAccess.get_file_as_string("res://regions/glade/thicket.md")
	if not RegionDocument.parse(thicket).terrain.values().has(forest):
		return "the glade's thicket has no forest"
	return _check_kind_and_place(tiles)


## The species `region`'s legend names for the wild monster spot `spot`, or "".
static func _species_on(region: Region, spot: Vector2i) -> String:
	var named: WildSpot = region.wild_spots.get(spot)
	return named.species if named != null else ""


## A legend symbol naming a tile kind and a place at once (#349) makes its tiles that kind and part
## of that place, a turn and all; one naming something else before the place leaves them ground.
func _check_kind_and_place(tiles: String) -> String:
	var legend: String = "- `g`: forest, turned 2; stepping here reaches the place grove\n"
	legend += "- `b`: the beach; stepping here reaches the place beach"
	var region: Region = RegionDocument.parse(tiles % ["g 1 b", legend])
	var grove: Vector2i = Vector2i(-1, 0)
	var expected: bool = region.problem.is_empty() and region.triggers.size() == 2
	expected = expected and region.terrain.get(grove, -1) == TileKinds.number_of("forest")
	expected = expected and region.decoration_turns == { grove: 2 }
	expected = expected and region.terrain.get(Vector2i(1, 0), -1) == Region.GROUND
	for trigger: TileTrigger in region.triggers:
		var place: String = "grove" if trigger.tile == grove else "beach"
		expected = expected and trigger.action == TileTrigger.REACH and trigger.place == place
	if not expected:
		return "a symbol naming a tile kind and a place didn't read as both: %s" % region.problem
	return ""


## Whether `region`, read from _check_documents' document, has its stump turned 3 and not walkable
## though stumps are, and its water walkable though water isn't, all of it turning with the region
## and moving with a placed piece; and whether the overrides are hashed: `plain`, the same document
## without them, hashes otherwise.
func _turned_and_overridden(region: Region, plain: String) -> bool:
	var expected: bool = region.decoration_turns == { STUMP: 3 }
	expected = expected and region.height_overrides == { STUMP: 30 }
	expected = expected and TileKinds.is_walkable(region.terrain[STUMP])
	expected = expected and not region.is_walkable(STUMP) and region.is_walkable(Vector2i.ZERO)
	expected = expected and region.is_walkable(WATER) and not TileKinds.is_walkable(Region.WATER)
	var turned: Region = region.turned(4)
	expected = expected and turned.decoration_turns == { Hex.turn(STUMP, 4): 1 }
	expected = expected and turned.height_overrides == { Hex.turn(STUMP, 4): 30 }
	expected = expected and not turned.is_walkable(Hex.turn(STUMP, 4))
	var placed: Region = Region.new()
	placed.place(region, Vector2i(5, -2))
	expected = expected and placed.decoration_turns == { STUMP + Vector2i(5, -2): 3 }
	expected = expected and placed.height_overrides == { STUMP + Vector2i(5, -2): 30 }
	var moved: Vector2i = Vector2i(5, -2)
	expected = expected and not placed.is_walkable(STUMP + moved)
	expected = expected and placed.is_walkable(WATER + moved)
	return expected and region.hash_values() != RegionDocument.parse(plain).hash_values()


## Every blueprint loads as a full instance for every seed, and its first player can walk to every
## exit. Tiles a scripted event opens later will count as open here once they exist (#143).
func _check_exits_reachable() -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		for seed_value: int in INSTANCE_SEEDS:
			var state: GameState = InstanceBlueprints.create(instance_name, seed_value)
			if state == null:
				return "%s didn't load for seed %d" % [instance_name, seed_value]
			var stranded: String = _unreachable_exit(state.region)
			if not stranded.is_empty():
				return "%s's exit %s can't be walked to for seed %d" % [
					instance_name,
					stranded,
					seed_value,
				]
	return ""


## Every region file and region piece (regions/ and its folders) has its walkable tiles in one
## connected part, its starts, connectors and exits among them (#205): a blocking tile (rock, water,
## a boulder) never cuts part of a piece off.
func _check_pieces_connected() -> String:
	for path: String in _region_files():
		var piece: Region = RegionDocument.parse(FileAccess.get_file_as_string(path))
		if not piece.problem.is_empty() or _disconnected(piece):
			return "%s has walkable tiles cut off from the rest: %s" % [path, piece.problem]
	return ""


## Every region file and region piece.
static func _region_files() -> Array[String]:
	var paths: Array[String] = []
	for folder: String in DirAccess.get_directories_at(InstanceBlueprints.REGIONS):
		for file: String in DirAccess.get_files_at(InstanceBlueprints.REGIONS + folder):
			paths.append(InstanceBlueprints.REGIONS + folder + "/" + file)
	for file: String in DirAccess.get_files_at(InstanceBlueprints.REGIONS):
		paths.append(InstanceBlueprints.REGIONS + file)
	return paths


## Every region file and piece, and every blueprint's arranged region (a crown can reach across a
## piece's edge), leaves the room its crowns need (#232); and a crown over something too tall is
## caught.
func _check_room() -> String:
	var look: Callable = Callable(TileLooks, "of")
	for path: String in _region_files():
		var problem: String = _room_problem(
			RegionDocument.parse(FileAccess.get_file_as_string(path)),
			look,
		)
		if not problem.is_empty():
			return "%s: %s" % [path, problem]
	for instance_name: String in InstanceBlueprints.NAMES:
		for seed_value: int in INSTANCE_SEEDS:
			var region: Region = InstanceBlueprints.region_of(instance_name, seed_value)
			var problem: String = _room_problem(region, look)
			if not problem.is_empty():
				return "%s at seed %d: %s" % [instance_name, seed_value, problem]
	return _check_room_caught()


## A made-up crown reaching one ring, leaving room for a stump's measured height beneath it: a
## stump next to it fits, a forest's trees don't, and the problem names both tiles; a forest set
## lower by hand in its piece (a height override, #232) fits.
func _check_room_caught() -> String:
	var crown: TileBlueprint = TileBlueprint.new()
	crown.id = "test_crown"
	crown.reach = 1
	crown.clearance = TileLooks.height_of(TileKinds.number_of("stump"))
	_crown = crown
	var look: Callable = _crown_look
	var region: Region = Region.disc(2)
	region.terrain[Vector2i.ZERO] = CROWN_KIND
	region.terrain[Hex.DIRECTIONS[0]] = TileKinds.number_of("stump")
	if not _room_problem(region, look).is_empty():
		return "a stump didn't fit under a crown that leaves room for it: " + _room_problem(
			region,
			look,
		)
	region.terrain[Hex.DIRECTIONS[3]] = TileKinds.number_of("forest")
	var problem: String = _room_problem(region, look)
	if not problem.contains("forest") or not problem.contains(str(Hex.DIRECTIONS[3])):
		return "a forest under a crown that leaves no room for it wasn't caught: " + problem
	region.height_overrides[Hex.DIRECTIONS[3]] = crown.clearance
	if not _room_problem(region, look).is_empty():
		return "a forest set low enough by hand didn't fit: " + _room_problem(region, look)
	return ""


## The blueprint of `kind` for _check_room_caught: its made-up crown, or the real one.
func _crown_look(kind: int) -> TileBlueprint:
	return _crown if kind == CROWN_KIND else TileLooks.of(kind)


## Why `region` doesn't leave a crown the room it needs, or "": every tile within a decoration's
## reach must be no taller than the clearance it leaves (#232). A tile is as tall as its tallest
## object, measured from the models, unless its piece sets its height by hand. `look` gives a
## kind's blueprint.
static func _room_problem(region: Region, look: Callable) -> String:
	for tile: Vector2i in region.sorted_tiles():
		var crown: TileBlueprint = look.call(region.terrain[tile])
		if crown == null or crown.reach == 0:
			continue
		for under: Vector2i in Hex.disc(crown.reach, tile):
			var below: TileBlueprint = null
			if under != tile and region.has_tile(under):
				below = look.call(region.terrain[under])
			var tall: int = 0
			if below != null:
				var measured: int = TileLooks.height_of(region.terrain[under])
				tall = region.height_overrides.get(under, measured)
			if below != null and tall > crown.clearance:
				return "%s on %s is taller (%d) than %s's crown on %s leaves room for (%d)" % [
					below.id,
					under,
					tall,
					crown.id,
					tile,
					crown.clearance,
				]
	return ""


## Whether some walkable tile, start, connector or exit of `region` can't be walked to from its
## first walkable tile.
func _disconnected(region: Region) -> bool:
	var walkable: Array[Vector2i] = []
	for tile: Vector2i in region.sorted_tiles():
		if region.is_walkable(tile):
			walkable.append(tile)
	if walkable.is_empty():
		return true
	var reached: Array[Vector2i] = region.reachable(walkable[0])
	var points: Array[Vector2i] = walkable.duplicate()
	points.append_array(region.starts)
	for side: Vector3i in region.connectors + region.exits:
		points.append(Vector2i(side.x, side.y))
	for tile: Vector2i in points:
		if not reached.has(tile):
			return true
	return false


## The first exit of `region` its first player can't walk to, as text, or "".
func _unreachable_exit(region: Region) -> String:
	var walkable: Array[Vector2i] = region.reachable(region.starts[0])
	for exit: Vector3i in region.exits:
		if not walkable.has(Vector2i(exit.x, exit.y)):
			return str(exit)
	return ""


## Every blueprint with exits can be reached from the starting instance by walking through exits,
## so no part of the web is cut off.
func _check_web_connected() -> String:
	var reached: Array[String] = [InstanceBlueprints.BASIC]
	var next: int = 0
	while next < reached.size():
		for target: String in InstanceBlueprints.region_of(reached[next], 0).exit_blueprints:
			if not reached.has(target):
				reached.append(target)
		next += 1
	for instance_name: String in InstanceBlueprints.NAMES:
		var has_exits: bool = not InstanceBlueprints.region_of(instance_name, 0).exits.is_empty()
		if has_exits and not reached.has(instance_name):
			return "%s has exits but can't be reached from the starting instance" % instance_name
	return ""


## The world (#148): the session starts in the basic instance, and the glade loads with nobody in
## it. Only the instance a player is in steps, every instance's seed is its own and the same every
## session, and the world's hash covers every loaded instance.
func _check_world() -> String:
	var world: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.BASIC)
	var glade: GameState = world.instance(InstanceBlueprints.GLADE)
	if not world.problem.is_empty() or glade == null or glade.player(0) != null:
		return "the world didn't start, or the glade didn't load empty: " + world.problem
	var seeds: Array[int] = [world.seed_for(InstanceBlueprints.BASIC), glade.rng_seed]
	var again: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.BASIC)
	if seeds[0] == seeds[1] or again.seed_for("glade") != seeds[1]:
		return "the instances' seeds aren't their own, or differ between sessions: %s" % [seeds]
	var hashed: int = world.state_hash()
	for _tick: int in 10:
		world.step(_still())
	var basic: GameState = world.instances[InstanceBlueprints.BASIC]
	if basic.tick != 10 or glade.tick != 0 or world.active().size() != 1:
		return "the world stepped the wrong instances: basic %d, glade %d" % [
			basic.tick,
			glade.tick,
		]
	var stepped: int = world.state_hash()
	glade.tick += 1
	if hashed == stepped or world.state_hash() == stepped:
		return "the world's hash doesn't cover every loaded instance"
	return ""


func _still() -> Array[Command]:
	var commands: Array[Command] = [Command.new(Command.NO_MOVE)]
	return commands


## The web lies in one world (#187): the glade sits so that walking out of the basic instance's east
## exit lands next to it on the glade's way back, and for every seed no two instances overlap.
func _check_layout() -> String:
	for seed_value: int in SEEDS:
		var problem: String = _layout_problem(seed_value)
		if not problem.is_empty():
			return "seed %d: %s" % [seed_value, problem]
	var world: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.BASIC)
	var basic: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.BASIC,
		world.seed_for("basic"),
	)
	var glade: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.GLADE,
		world.seed_for(InstanceBlueprints.GLADE),
	)
	var exit: Vector3i = basic.exits[0]
	var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
	var back: Vector2i = Vector2i(glade.exits[0].x, glade.exits[0].y)
	var landing: Vector2i = back + world.offset(InstanceBlueprints.GLADE)
	if world.offset(InstanceBlueprints.BASIC) != Vector2i.ZERO or landing != outside:
		return "walking out of the basic instance's east exit doesn't land on the glade's way back"
	return ""


## Why seed `seed_value`'s web can't be laid out as one world, or "".
func _layout_problem(seed_value: int) -> String:
	return World.new(BlueprintSource.new(), seed_value, InstanceBlueprints.BASIC).layout_problem()


## For every seed the glade's way back is on its west side, where the region ends.
func _check_glade_exit() -> String:
	for seed_value: int in SEEDS:
		var glade: Region = InstanceBlueprints.region_of(InstanceBlueprints.GLADE, seed_value)
		var outside: Array[Vector2i] = glade.outside_exits()
		var west: Vector3i = Vector3i(-2, 0, 3)
		var kept: bool = glade.exits.size() == 1 and glade.exits[0] == west
		if not kept or glade.has_tile(outside[0]) or not glade.problem.is_empty():
			return "seed %d's glade has its way back at %s: %s" % [
				seed_value,
				glade.exits,
				glade.problem,
			]
	return ""


## Exit lines that don't read right or don't lead off the edge are refused, and no piece may cover
## the tile outside an exit.
func _check_refused() -> String:
	var cases: Dictionary[String, String] = {
		"origin 0 0\n.\nexit 0 0 0": "an exit line reads",
		"origin 0 0\n.\nexit 0 0 9 basic": "exit side 9",
		"origin 0 0\n. .\nexit 0 0 0 basic": "exit (0, 0) doesn't open",
	}
	for text: String in cases:
		var problem: String = RegionFormat.parse(text).problem
		if not problem.begins_with(cases[text]):
			return "expected a refusal starting %s, got: %s" % [cases[text], problem]
	var with_exit: Region = RegionFormat.parse("origin 0 0\n.\nexit 0 0 0 basic")
	if with_exit.fits(RegionFormat.parse("origin 0 0\n."), Vector2i(1, 0)):
		return "a piece fit onto the tile outside an exit"
	return ""


## A rule that raises the story beat BEAT twice every tick (#499), as two rules seeing it might.
class Beat:
	extends Feature

	const BEAT: String = "story_beat"

	func step(state: GameState, _commands: Array[Command]) -> void:
		state.events.append(EventEmitted.new(BEAT))
		state.events.append(EventEmitted.new(BEAT))


## A rule that fells every standing storm finch in its instance inside the tick, as a special would
## (#541), counting them in `felled`.
class Felling:
	extends Feature

	var felled: int = 0

	func step(state: GameState, _commands: Array[Command]) -> void:
		var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
		for monster: int in wild.monsters.duplicate():
			if wild.species_of(monster) == "storm_finch":
				wild.wound(state, monster, wild.hp_of(monster), true)
				felled += 1


## The blueprints, with a glade that RISEN turns into a variant (#529): the arena's region, as no
## blueprint has a variant yet.
class RisingSource:
	extends BlueprintSource

	const RISEN: String = "glade_risen"

	func variant(instance_name: String, flags: Array[String]) -> String:
		var risen: bool = instance_name == InstanceBlueprints.GLADE and flags.has(RISEN)
		return InstanceBlueprints.ARENA if risen else ""
