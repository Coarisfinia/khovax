extends RefCounted
## World flow (#120, #139): the instances hang together through exits in their region pieces.
## Every exit leads to a blueprint that exists and has the way back on the opposite side; the
## playground has no exits, so no way leads to it (#712); the glade keeps its layout, so its ways
## out stay on its start piece for every seed, and arranging its pieces never covers the tile
## outside them. Broken exit lines are
## refused. Pieces join and exits lead out across several tiles, never one (#689). The web is
## validated as a whole (#143): every blueprint loads as a full instance, every variant of the
## starting one with a start for every player (#742), every
## exit can be walked to from the players' starts for every seed, and every blueprint with exits
## can be reached from the starting instance. In every region file and region piece, the walkable
## tiles hang together, so a blocking tile never cuts a part off, and every tile under a crown
## (a decoration reaching over its neighbours, #232) fits beneath it. The world holds several loaded
## instances and
## steps the ones a player is in (#148), and purges one left behind for an hour of play (#212).
## Each player's companion (#338) joins them, roams within its reach and follows them through exits.
## A player swaps it for another monster they carry (#55), by a tap or a click on the roster at the
## top left of the screen, which shows the monsters they carry and which is their companion (#540).
## One that faints stays fainted through exits, saves and session starts until revived (#655), as
## a revive item does (#656), which the local player uses by its button or its key while their
## profile holds one, and which their profile spends.
## The world raises that a player entered an instance (#370) when they start in it and whenever
## they walk through an exit into another, and only then. A rule can change a tile of a loaded
## instance in place (#530), which the world keeps through its save data. A world flag chooses a
## blueprint's variant, and setting it purges the instance once nobody is in it (#529). A named
## event sets its own flag, and the corrupted glade's corrupting monster emits one when it falls,
## which purifies the glade once nobody is in it (#541). The first time a named event sets its
## flag, the world raises a world-changing moment, once (#499). A fresh world starts with the
## factions' territory as flags, which its save data keeps (#637).

const SEEDS: int = 40
## The damage the companion walks through the exit with, to see it arrive as hurt (#716).
const FOLLOWER_DAMAGE: int = 3
## Seeds every blueprint is loaded with as a full instance: fewer, since that includes the load
## test's big region.
const INSTANCE_SEEDS: int = 6
## How many tiles wide every join between region pieces and every exit is at least (#689).
const SEAM_WIDTH: int = 3
## Where _check_documents' region document has its stump, turned and set lower (#232) by hand.
const STUMP: Vector2i = Vector2i(0, -1)
## Where it has its water, made walkable by hand.
const WATER: Vector2i = Vector2i(0, 1)
## The legend lines every test region document starts with: player 1's start and ground (#711).
const BASE_LEGEND: String = "- `🔴`: where player 1 starts\n- `🟫`: ground\n"
## A made-up tile kind number for _check_room_caught's crown: no blueprint has it.
const CROWN_KIND: int = 250
## The feature id _check_store_kept keeps its world store entry under: one no feature has.
const STORE_FEATURE: int = 9_999
## The screen _check_roster lays the roster out for.
const ROSTER_SCREEN: Vector2 = Vector2(1280.0, 720.0)
## Where _check_roster's profile is saved, apart from the player's own: it spends a revive item.
const ROSTER_PROFILE: String = "user://test_world_profile.json"

## The made-up crown _check_room_caught gives CROWN_KIND.
var _crown: TileBlueprint
## The short ids of the first and second monster a party FlowSteps.party makes carries.
var _first: String = ShortId.stand_in(1)
var _second: String = ShortId.stand_in(2)
## The instances player 0 entered while _walk_in walked them, in order (#370).
var _entered: Array[String] = []


func run(tree: SceneTree) -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var problem: String = InstanceBlueprints.exit_problem(instance_name)
		if not problem.is_empty():
			return problem
	# Without a way back, no exit can lead to it either: exit_problem refuses that.
	if not InstanceBlueprints.region_of(InstanceBlueprints.BASIC, 0).exits.is_empty():
		return "the playground, which only the tests play, has an exit"
	var steps: Array[Callable] = [
		_check_glade_exit,
		_check_wide_seams,
		_check_refused,
		_check_exits_reachable,
		_check_start_variants,
		_check_pieces_connected,
		_check_room,
		_check_web_connected,
		_check_world,
		_check_documents,
		_check_walk_through,
		_check_companions,
		_check_swaps,
		_check_fainted_kept,
		_check_two_of_one_species,
		_check_store_kept,
		_check_purge,
		_check_flags,
		_check_corruption,
		_check_story_beat,
		_check_territory,
		_check_start_kept,
		_check_start_corrupted,
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


## Walking through exits (#154): from the forest's start, onto its exit on (-2, 5) and on southeast
## into the glade, arriving on the glade's way back; then northwest again, back onto the forest's
## exit, while the glade stays loaded for the next visit. The exit is three tiles wide (#689): one
## step east along it and southeast again, the player lands on the glade's tile right across from
## that one. The player enters the forest on the first tick, then the glade, the forest and the
## glade again, and nothing else.
func _check_walk_through() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	_entered.clear()
	for direction: int in FlowSteps.INTO_GLADE:
		_walk_in(world, direction)
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var arrived: Entity = world.player(0)
	if glade == null or world.instance_of(0) != InstanceBlueprints.GLADE:
		return "walking southeast out of the forest didn't lead into the glade"
	var left_forest: bool = world.instances[InstanceBlueprints.FOREST].player(0) == null
	if arrived.tile != FlowSteps.GLADE_ARRIVAL or not left_forest:
		return "the player arrived on %s, not the glade's way back" % arrived.tile
	_walk_in(world, FlowSteps.OUT_OF_GLADE)
	var back: Entity = world.player(0)
	if world.instance_of(0) != InstanceBlueprints.FOREST or back.tile != FlowSteps.FOREST_EXIT:
		return "walking northwest out of the glade didn't lead back onto the forest's exit"
	if world.instances[InstanceBlueprints.GLADE] != glade:
		return "coming back loaded a new glade instead of the same one"
	for direction: int in [0, 5]:
		_walk_in(world, direction)
	var across: Vector2i = FlowSteps.GLADE_ARRIVAL + Hex.DIRECTIONS[0]
	if world.instance_of(0) != InstanceBlueprints.GLADE or world.player(0).tile != across:
		return "walking out of the wide exit's second tile didn't land across from it in the glade"
	var forest: String = InstanceBlueprints.FOREST
	var expected: Array[String] = [
		forest,
		InstanceBlueprints.GLADE,
		forest,
		InstanceBlueprints.GLADE,
	]
	if _entered != expected:
		return "walking there and back entered %s, not %s" % [_entered, expected]
	return ""


## Companions (#338): the player who brings one is joined by it on the first tick, beside them; the
## other player, who brings none, isn't. A weak species' reach is shorter than a strong one's.
## Standing, the player watches it roam within its reach; walking off, they're never more than a
## step out of it, and only players color the trail. The player walks through it, and it follows
## them out through the exit into the glade, while the one in the forest goes.
func _check_companions() -> String:
	# A seed whose companion's first roll keeps it beside its player: it may step on the first tick.
	var world: World = World.new(
		BlueprintSource.new(),
		0,
		InstanceBlueprints.FOREST,
		2,
	)
	CompanionParty.bring(world, FlowSteps.parties([["storm_finch"]]))
	world.step(_still())
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var companions: CompanionFeature = forest.feature(Features.COMPANIONS) as CompanionFeature
	var companion: Entity = forest.entity(companions.companion_of(0))
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
	var trails: TrailFeature = forest.feature(Features.TRAIL) as TrailFeature
	for tile: Vector2i in trails.shared.tiles:
		if trails.shared.tiles[tile] == companion.id:
			return "the companion colored %s on the trail" % tile
	return _check_companion_passed(world, companion)


## Standing southeast of its player, the companion lets them walk through. Hurt, it follows them out
## through the exit into the glade (#716): the world moves it along with them, beside them, as hurt
## as it left (a companion made anew would be unhurt), and nothing of it stays in the forest.
func _check_companion_passed(world: World, companion: Entity) -> String:
	var start: Vector2i = world.player(0).tile
	companion.tile = start + Hex.DIRECTIONS[5]
	world.step(_moving(5))
	if world.player(0).tile != start + Hex.DIRECTIONS[5]:
		return "the companion stopped its own player"
	_idle_until(world, world.tick + MovementFeature.MOVE_TICKS)
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var hurt: HealthFeature = forest.feature(Features.HEALTH) as HealthFeature
	hurt.carry_in(forest, companion, { "damage": FOLLOWER_DAMAGE })
	var hp: int = hurt.hp_of(forest, companion.id)
	# The rest of the walk into the glade: onto the forest's exit and through it.
	for direction: int in FlowSteps.INTO_GLADE.slice(1):
		_walk_in(world, direction)
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var followed: CompanionFeature = glade.feature(Features.COMPANIONS) as CompanionFeature
	var left: CompanionFeature = forest.feature(Features.COMPANIONS) as CompanionFeature
	if world.instance_of(0) != InstanceBlueprints.GLADE or followed.companion_of(0) == 0:
		return "the companion didn't follow its player into the glade"
	if left.companion_of(0) != 0 or forest.entity(companion.id) != null:
		return "the companion stayed in the forest its player left"
	var health: HealthFeature = glade.feature(Features.HEALTH) as HealthFeature
	if health.hp_of(glade, followed.companion_of(0)) != hp:
		return "the companion arrived in the glade with other HP than it left with: made anew"
	var beside: Entity = glade.entity(followed.companion_of(0))
	if Hex.distance(beside.tile, world.player(0).tile) > followed.reach_of_companion(beside.id):
		return "the companion arrived out of its reach of its player"
	return ""


## Manual swaps (#55): a player carrying a storm finch and a moss toad is joined by the finch.
## Swapping to the companion they have or to a place they carry nothing in does nothing; swapping
## to the toad raises that they chose it, and the next tick the toad has taken the finch's place.
## A recorded session with the swaps plays back the same, and the choice goes through the world's
## save data and back. With swapping switched off, a swap does nothing. The toad follows its player
## into the glade.
func _check_swaps() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	CompanionParty.bring(world, FlowSteps.parties([["storm_finch", "moss_toad"]]))
	var recorded: Replay = Replay.new(InstanceBlueprints.FOREST, 3)
	recorded.begin(world)
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var companions: CompanionFeature = forest.feature(Features.COMPANIONS) as CompanionFeature
	var joined: bool = _swap_in(world, recorded, Command.NO_SWAP) == 0
	if not joined or companions.species_of(companions.companion_of(0)) != "storm_finch":
		return "a player carrying two monsters wasn't joined by the first"
	if _swap_in(world, recorded, 1) + _swap_in(world, recorded, 3) != 0:
		return "swapping to the companion they have, or to an empty place, raised a swap"
	if _swap_in(world, recorded, 2) != 1 or CompanionParty.companion_in(world, 0) != _second:
		return "swapping to the second carried monster didn't make it the companion"
	var finch: int = companions.companion_of(0)
	var _settled: int = _swap_in(world, recorded, Command.NO_SWAP)
	var toad: int = companions.companion_of(0)
	if companions.species_of(toad) != "moss_toad" or forest.entity(finch) != null:
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
	var kept: bool = restored.stores[0].same_as(world.stores[0])
	if not restored.problem.is_empty() or not kept:
		return "the chosen companion didn't go through the save data and back: " + restored.problem
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	forest.set_enabled(Features.COMPANION_SWAPS, false)
	if _swap_in(world, null, 1) != 0 or CompanionParty.companion_in(world, 0) != _second:
		return "a player swapped with swapping switched off"
	forest.set_enabled(Features.COMPANION_SWAPS, true)
	for direction: int in FlowSteps.INTO_GLADE:
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


## Steps `world` once with player 0 standing and using a revive item (#656); returns the short ids
## their instance raised as revived.
func _revive_in(world: World) -> Array[String]:
	var command: Command = Command.new()
	command.revive = true
	var commands: Array[Command] = [command]
	world.step(commands)
	var revived: Array[String] = []
	for event: RefCounted in world.instances[world.instance_of(0)].events:
		if event is MonsterRevived:
			revived.append((event as MonsterRevived).short_id)
	return revived


## A player's world store (#724): an entry a feature keeps there, ints and ids in lists and tables,
## is handed to the instance the player walks into, and what a rule changes in it there is taken
## back into the world after the tick and handed to the instance they left. It goes through the
## world's save data and back the same, hashing the same; one holding something other than ints and
## ids is refused.
func _check_store_kept() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	var kept: Dictionary = {
		"count": 3,
		"ids": ["storm_finch", "moss_toad"],
		"table": { "k": [1] },
	}
	world.set_entry(0, STORE_FEATURE, kept)
	for direction: int in FlowSteps.INTO_GLADE:
		_walk_in(world, direction)
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	if world.instance_of(0) != InstanceBlueprints.GLADE or glade.stored(0, STORE_FEATURE) != kept:
		return "the store entry didn't come along into the glade"
	# Changed by hand in the glade, as a feature there would.
	glade.store(0, STORE_FEATURE)["count"] = 4
	world.step(_still())
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	if world.stored(
		0,
		STORE_FEATURE,
	)["count"] != 4 or forest.stored(0, STORE_FEATURE)["count"] != 4:
		return "the store entry changed in the glade wasn't taken into the world and handed on"
	var data: Dictionary = WorldData.of(world)
	var restored: World = WorldData.to_world(data, BlueprintSource.new())
	var same: bool = restored.stores[0].same_as(world.stores[0])
	if not restored.problem.is_empty() or not same or restored.state_hash() != world.state_hash():
		return "the store entry didn't go through the save data and back: " + restored.problem
	data["stores"][0]["entries"][0]["values"]["count"] = 0.5
	if WorldData.to_world(data, BlueprintSource.new()).problem.is_empty():
		return "a store entry holding a fraction was read back"
	return ""


## A fainted monster stays fainted (#655): the storm finch faints beside its player in the forest,
## the toad is chosen in its place, and the world keeps the finch fainted. Through the exit into the
## glade, the toad joins its player there and a swap back to the finch does nothing;
## the finch stays fainted through the world's save data and back, and through a session's start
## that brings the same monsters, as the restored world goes on. Revived in the glade
## (CompanionParty.revive), it can be swapped to again and joins its player, and the world takes
## it into the forest too. A fainted one its player no longer carries is forgotten.
func _check_fainted_kept() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	var party: Array[CarriedMonsters] = FlowSteps.parties([["storm_finch", "moss_toad"]])
	CompanionParty.bring(world, party)
	var _joined: int = _swap_in(world, null, Command.NO_SWAP)
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var companions: CompanionFeature = forest.feature(Features.COMPANIONS) as CompanionFeature
	# Fainted by hand: the domination flow makes one faint under a wild monster's strikes.
	companions.send_home(forest, companions.companion_of(0))
	var _relieved: int = _swap_in(world, null, Command.NO_SWAP)
	if CompanionParty.fainted_in(
		world,
		0,
	) != PackedStringArray([_first]) or CompanionParty.companion_in(world, 0) != _second:
		return "the world didn't keep the fainted finch, or didn't choose the toad in its place"
	for direction: int in FlowSteps.INTO_GLADE:
		_walk_in(world, direction)
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var there: CompanionFeature = glade.feature(Features.COMPANIONS) as CompanionFeature
	var toad_joined: bool = there.species_of(there.companion_of(0)) == "moss_toad"
	if not toad_joined or not CompanionParty.has_fainted(
		glade,
		0,
		_first,
	) or _swap_in(world, null, 1) != 0:
		return "through the exit, the finch didn't stay fainted, or the toad didn't join"
	return _check_fainted_restored(world, party)


## `world`, with the finch fainted, goes through its save data and a session's start bringing
## `party`, and the restored world goes on with the finch fainted; then it's revived there.
func _check_fainted_restored(world: World, party: Array[CarriedMonsters]) -> String:
	var restored: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	if not restored.problem.is_empty():
		return "the world with a fainted finch didn't go through its save data: " + restored.problem
	CompanionParty.bring(restored, party, true)
	var _stood: int = _swap_in(restored, null, Command.NO_SWAP)
	var kept: GameState = restored.instances[InstanceBlueprints.GLADE]
	var same: bool = restored.stores[0].same_as(world.stores[0])
	if not same or not CompanionParty.has_fainted(kept, 0, _first):
		return "the fainted finch didn't stay fainted through the save and a session's start"
	return _check_revived(restored)


## Revived by a revive item (#656), raising MonsterRevived once, the finch can be swapped to again
## and joins its player in the glade; another revive item, with none fainted, revives nothing. A
## fainted one no longer carried is forgotten.
func _check_revived(world: World) -> String:
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	var finch: Array[String] = [_first]
	if _revive_in(world) != finch:
		return "a revive item didn't bring back the fainted finch, once"
	if _swap_in(world, null, 1) != 1 or not CompanionParty.fainted_in(world, 0).is_empty():
		return "the revived finch couldn't be swapped to, or the world kept it fainted"
	if not _revive_in(world).is_empty():
		return "a revive item revived something with nothing fainted"
	var _joined: int = _swap_in(world, null, Command.NO_SWAP)
	var there: CompanionFeature = glade.feature(Features.COMPANIONS) as CompanionFeature
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var finch_joined: bool = there.species_of(there.companion_of(0)) == "storm_finch"
	if not finch_joined or CompanionParty.has_fainted(forest, 0, _first):
		return "the revived finch didn't join its player, or stayed fainted in the forest"
	var toad_down: Dictionary = world.stored(0, Features.COMPANIONS).duplicate(true)
	toad_down["fainted"] = [_second]
	world.set_entry(0, Features.COMPANIONS, toad_down)
	CompanionParty.bring(world, FlowSteps.parties([["storm_finch"]]))
	if not CompanionParty.fainted_in(world, 0).is_empty():
		return "a fainted monster no longer carried wasn't forgotten"
	return ""


## Two carried monsters of one species are two monsters (#700): a player carrying two storm finches
## is joined by the first; once it faints, only it is fainted, and the second is chosen in its place
## and joins them. Swapping back to the first does nothing, and the world's save data keeps them
## apart.
func _check_two_of_one_species() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	CompanionParty.bring(world, FlowSteps.parties([["storm_finch", "storm_finch"]]))
	var _joined: int = _swap_in(world, null, Command.NO_SWAP)
	var forest: GameState = world.instances[InstanceBlueprints.FOREST]
	var companions: CompanionFeature = forest.feature(Features.COMPANIONS) as CompanionFeature
	if companions.short_id_of(companions.companion_of(0)) != _first:
		return "a player carrying two storm finches wasn't joined by the first"
	companions.send_home(forest, companions.companion_of(0))
	var _relieved: int = _swap_in(world, null, Command.NO_SWAP)
	var second: int = companions.companion_of(0)
	if CompanionParty.fainted_in(world, 0) != PackedStringArray([_first]) or second == 0:
		return "the first finch fainting didn't leave the second standing and beside its player"
	var same_kind: bool = companions.species_of(second) == "storm_finch"
	if not same_kind or companions.short_id_of(second) != _second or _swap_in(world, null, 1) != 0:
		return "the second finch didn't take the first's place, or the fainted one was swapped to"
	var restored: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	if not restored.problem.is_empty() or not restored.stores[0].same_as(world.stores[0]):
		return "two finches didn't go through the save data and back apart: " + restored.problem
	return ""


## The roster (#540) in the main scene: carrying a storm finch and a moss toad, it shows both at
## the top left, apart, in that order, the finch as the companion, and the quest list starts below
## it. A tap on the toad's square swaps to it in the local player's next command without starting
## the touch stick, and a left click on the finch's swaps to the finch; while the game hears no
## input (the menu is open) a tap swaps nothing. Swapped to the toad, the roster shows it as the
## companion, and once it faints, as fainted (#597).
func _check_roster(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree, ROSTER_PROFILE)
	var driver: GameDriver = FlowGame.held_driver(main)
	CompanionParty.bring(driver.world, FlowSteps.parties([["storm_finch", "moss_toad"]]))
	var roster: RosterHud = main.get_node("Hud/RosterHud") as RosterHud
	roster.show_state()
	# Laid out for a desktop screen: the headless one is tiny. The flow steps it by hand from here.
	roster.set_process(false)
	roster.lay_out_in(ROSTER_SCREEN)
	var result: String = _roster_shown(main, roster)
	if result.is_empty():
		result = _roster_swaps(main, roster, driver)
	if result.is_empty():
		result = _check_revive_item(main, driver)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(ROSTER_PROFILE)
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
	if RosterHud.initials_of("Tikazzir") != "T":
		return "the Tikazzir's square doesn't show its initial"
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
	return _roster_fainted(roster, driver)


## The toad, once it joined and fainted (#597), shows on the roster as fainted, the finch not.
func _roster_fainted(roster: RosterHud, driver: GameDriver) -> String:
	var _joined: int = _swap_in(driver.world, null, Command.NO_SWAP)
	var companions: CompanionFeature = driver.state.feature(Features.COMPANIONS) as CompanionFeature
	if companions.companion_of(0) == 0:
		return "the toad didn't join its player once swapped to"
	# Fainted by hand: the domination flow makes one faint under a wild monster's strikes.
	companions.send_home(driver.state, companions.companion_of(0))
	roster.show_state()
	var expected: Array[bool] = [false, true]
	if roster.fainted != expected:
		return "the roster shows %s fainted, not just the toad" % [roster.fainted]
	return ""


## The revive item (#656), with the toad fainted: its button shows its icon and 0, faded, while the
## profile holds none, and its key uses none. With one held, the button shows 1, usable, and the key
## uses it in the next command, which brings the toad back; the profile spends it, and the button
## shows 0 again. A controller's d-pad down uses one too.
func _check_revive_item(main: Node, driver: GameDriver) -> String:
	var button: ReviveButton = main.get_node("Hud/ReviveButton") as ReviveButton
	var holder: ProfileHolder = FlowGame.holder(main)
	if button.icon == null or button.corner_text() != "0" or button.usable():
		return "the revive item's button doesn't show its icon and 0, faded, with none held"
	if _revive_pressed(driver).revive:
		return "the revive key used a revive item the profile doesn't hold"
	holder.keeper.profile.materials[ReviveItem.ID] = 1
	if button.corner_text() != "1" or not button.usable():
		return "the revive item's button doesn't show 1, usable, with one held and the toad fainted"
	var commands: Array[Command] = [_revive_pressed(driver)]
	driver.world.step(commands)
	driver.ticked.emit(driver.state.tick, driver.state.events)
	(main.get_node("EventBus") as EventBus).flush()
	if not CompanionParty.fainted_in(driver.world, 0).is_empty():
		return "the revive key didn't bring the fainted toad back"
	if ReviveItem.held(holder) != 0 or button.corner_text() != "0" or button.usable():
		return "the profile didn't spend the revive item used, or its button didn't show 0"
	var pad: bool = false
	for event: InputEvent in InputMap.action_get_events(&"revive_monster"):
		var pressed: InputEventJoypadButton = event as InputEventJoypadButton
		pad = pad or (pressed != null and pressed.button_index == JOY_BUTTON_DPAD_DOWN)
	return "" if pad else "a controller's d-pad down doesn't use a revive item"


## The local player's next command after a press of the revive key (#656).
static func _revive_pressed(driver: GameDriver) -> Command:
	Input.action_press(&"revive_monster")
	driver.input._process(0.0)
	Input.action_release(&"revive_monster")
	return driver.input.command(driver.state)


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
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	var first_seed: int = world.seed_for(InstanceBlueprints.GLADE)
	for direction: int in FlowSteps.INTO_GLADE + [FlowSteps.OUT_OF_GLADE]:
		_walk_in(world, direction)
	var left: int = world.left_at.get(InstanceBlueprints.GLADE, -1)
	if left < 0 or world.instance_of(0) != InstanceBlueprints.FOREST:
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
	_walk_in(world, FlowSteps.INTO_GLADE[-1])
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var reseeded: bool = glade != null and glade.rng_seed == world.seed_for("glade")
	if not reseeded or glade.rng_seed == first_seed or world.left_at.has("glade"):
		return "the glade didn't come back at generation 1 from a new seed, or kept its count"
	return _check_left_again(world, left + World.PURGE_TICKS)


## Leaving the glade again, after it was purged at `purged`, starts a new count, and the world goes
## through its save data and back with both.
func _check_left_again(world: World, purged: int) -> String:
	_walk_in(world, FlowSteps.OUT_OF_GLADE)
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
	var world: World = World.new(RisingSource.new(), 3, InstanceBlueprints.FOREST)
	for direction: int in FlowSteps.INTO_GLADE:
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
	_walk_in(world, FlowSteps.OUT_OF_GLADE)
	if world.instances.has(InstanceBlueprints.GLADE) or world.generation("glade") != 1:
		return "the glade wasn't purged once the player left it after the flag"
	var risen: GameState = world.instance(InstanceBlueprints.GLADE)
	var arena: Region = InstanceBlueprints.region_of("glade", world.seed_for("glade"), "arena")
	var tiles: Array[Vector2i] = risen.region.sorted_tiles()
	if world.variant_of("glade") != "arena" or tiles != arena.sorted_tiles():
		return "the glade didn't come back from its variant, the arena's region"
	# The arena's region has no way back to the forest, which only a layout worked out from
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
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	world.set_flag(InstanceBlueprints.CORRUPTED_GLADE)
	for direction: int in FlowSteps.INTO_GLADE:
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
	_walk_in(world, FlowSteps.OUT_OF_GLADE)
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
	var flags: Array[String] = world.flags.duplicate()
	world.step(_still())
	var flag: String = World.EVENT_FLAG + Beat.BEAT
	flags.append(flag)
	flags.sort()
	var changes: Array[WorldChanged] = _world_changes(world)
	var once: bool = changes.size() == 1 and changes[0].event_name == Beat.BEAT
	if not once or changes[0].flag != flag or world.flags != flags:
		return "a story beat didn't set its flag and raise one world-changing moment"
	world.step(_still())
	if not _world_changes(world).is_empty() or world.flags != flags:
		return "a story beat raised again changed the world again"
	return ""


## Faction territory (#637): a fresh world starts with the factions' territory as flags, so the
## Cartographer's Guild holds the glade, where the player starts (#712), and nobody the forest;
## a world loading from a source without territory (RisingSource) starts with no flags; through its
## save data and back the world keeps who holds what.
func _check_territory() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.GLADE)
	var guild: String = "cartographers_guild"
	var flag: String = Territory.flag(InstanceBlueprints.GLADE, guild)
	if (" ".join(world.flags) != flag
			or Territory.holder(world.flags, InstanceBlueprints.GLADE) != guild):
		return "a fresh world doesn't start with the guild holding the glade: %s" % [world.flags]
	if not Territory.holder(world.flags, InstanceBlueprints.FOREST).is_empty():
		return "a fresh world has a holder for the forest"
	if not World.new(RisingSource.new(), 3, InstanceBlueprints.GLADE).flags.is_empty():
		return "a world from a source without territory starts with flags"
	var reloaded: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	if Territory.holder(reloaded.flags, InstanceBlueprints.GLADE) != guild:
		return "the world didn't keep who holds the glade through its save data"
	return ""


## The world-changing moments (WorldChanged, #499) the world raised in its last tick, in order.
func _world_changes(world: World) -> Array[WorldChanged]:
	var changes: Array[WorldChanged] = []
	for event: RefCounted in world.events:
		if event is WorldChanged:
			changes.append(event as WorldChanged)
	return changes


## The starting instance, here the forest, isn't purged for being left behind (#212), however long
## the player stays in the glade.
func _check_start_kept() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.FOREST)
	for direction: int in FlowSteps.INTO_GLADE:
		_walk_in(world, direction)
	_idle_until(world, world.tick + World.PURGE_TICKS + 1)
	if not world.instances.has(InstanceBlueprints.FOREST) or world.generation("forest") != 0:
		return "the starting instance was purged"
	return ""


## The starting instance changes with the story too (#727): with the player out in the forest,
## setting the glade's corrupting flag purges the glade, where the world starts, and loads it again
## at once from the corrupted glade (_check_start_variants sees it has starts); the world goes
## through its save data and back with it, and walking back in leads into the corrupted glade.
func _check_start_corrupted() -> String:
	var world: World = World.new(BlueprintSource.new(), 3, InstanceBlueprints.GLADE)
	FlowSteps.drop_beach_toad(world.instances[InstanceBlueprints.GLADE])
	for direction: int in FlowSteps.INTO_FOREST:
		_walk_in(world, direction)
	if world.instance_of(0) != InstanceBlueprints.FOREST:
		return "the player didn't walk out of the glade into the forest"
	var plain: GameState = world.instances[InstanceBlueprints.GLADE]
	world.set_flag(InstanceBlueprints.CORRUPTED_GLADE)
	world.step(_still())
	var glade: GameState = world.instances.get(InstanceBlueprints.GLADE)
	var variant: String = world.variant_of(InstanceBlueprints.GLADE)
	var corrupted: bool = variant == InstanceBlueprints.CORRUPTED_GLADE
	if (glade == null
			or glade == plain
			or not corrupted
			or world.generation(InstanceBlueprints.GLADE) != 1):
		return "the starting glade wasn't purged and loaded again corrupted"
	var reloaded: World = WorldData.to_world(WorldData.of(world), BlueprintSource.new())
	if (reloaded.state_hash() != world.state_hash()
			or reloaded.generation(InstanceBlueprints.GLADE) != 1):
		return "the purged start didn't go through the save data: " + reloaded.problem
	_walk_in(world, FlowSteps.OUT_OF_FOREST)
	var back: bool = world.instance_of(0) == InstanceBlueprints.GLADE
	if not back or world.instances[InstanceBlueprints.GLADE] != glade:
		return "walking back didn't lead into the corrupted glade"
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
## clause it doesn't know, a turn past five sixths, a place without an id (#339) or a quest target
## without one, or marking two monsters (#625), is refused. A
## place's symbol can name its tile kind too (#349), which must be walkable. The glade's pieces
## have forest.
func _check_documents() -> String:
	var tiles: String = "# T\n\n## Tiles\n\n```\n%s\n```\n\n## Legend\n\n%s\n"
	var legend: String = BASE_LEGEND + "- `🔗`: joins another piece to the west\n"
	legend += "- `🚪`: exit to the east, to glade\n- `🐦`: a wild monster, always storm_finch\n"
	legend += "- `🌲`: forest\n"
	legend += "- `💧`: water, walkable\n- `🪓`: stump, turned 3, not walkable, height 30"
	var grid: String = " 🪓🌲\n🔗🔴🚪\n 🐦💧"
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
	return _check_refusals(tiles)


## A grid without a single middle, a narrow or unexplained symbol, a clause the legend doesn't know,
## a turn past five sixths, a place or a quest target without an id is refused; the glade's thicket
## has forest.
func _check_refusals(tiles: String) -> String:
	var base: String = BASE_LEGEND
	var refusals: Dictionary[String, String] = {
		tiles % ["🟫🟫\n🟫🟫", base]: "the tiles need an odd",
		tiles % ["🔴z🟫", base + "- `z`: forest"]: "a tile is one wide emoji, never `z`",
		tiles % ["🔴🌵🟫", base]: "the legend doesn't explain `🌵`",
		tiles % ["🔴❤️🟫", base]: "a tile is one wide emoji, never",
		tiles % ["🔴🌲🟫", base + "- `🌲`: jungle"]: "the legend doesn't explain `🌲`",
		tiles % ["🔴🪓🟫", base + "- `🪓`: stump, turned 6"]: "tile (0, 0)'s turn 6",
		tiles % ["🔴🪓🟫", base + "- `🪓`: stump, flying"]: "the legend doesn't explain `🪓`",
		tiles % ["🔴🪓🟫", base + "- `🪓`: stump, turned 2, turned 4"]: "tile (0, 0) says its turn",
		tiles % ["🔴🪓🟫", base + "- `🪓`: stump, walkable, not walkable"]: (
			"tile (0, 0) says its turn"
		),
		tiles % ["🔴🪓🟫", base + "- `🪓`: stump, height 1001"]: "tile (0, 0)'s height 1001",
		tiles % ["🔴🪓🟫", base + "- `🪓`: stump, height 2, height 3"]: "tile (0, 0) says its turn",
		tiles % ["🔴🐚🟫", base + "- `🐚`: a beach; stepping here reaches the place Beach"]: (
			"the legend doesn't explain `🐚`"
		),
		tiles % ["🔴🪨🟫", base + "- `🪨`: boulder; stepping here reaches the place beach"]: (
			"trigger (0, 0) isn't on ground"
		),
		tiles % ["🔴🐸🟫", base + "- `🐸`: a wild monster, always moss_toad, the quest target Old"]: (
			"a species line reads"
		),
		tiles % ["🐸🔴🐸", base + "- `🐸`: a wild monster, always moss_toad, the quest target old"]: (
			"species (1, 0): the quest target old is one monster"
		),
	}
	for text: String in refusals:
		var problem: String = RegionDocument.parse(text).problem
		if not problem.begins_with(refusals[text]):
			return "expected a refusal starting %s, got: %s" % [refusals[text], problem]
	var thicket: String = FileAccess.get_file_as_string("res://regions/glade/thicket.md")
	var forest: int = TileKinds.number_of("forest")
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
	var legend: String = "- `🌲`: forest, turned 2; stepping here reaches the place grove\n"
	legend += "- `🐚`: the beach; stepping here reaches the place beach\n"
	legend += "- `🔴`: where player 1 starts"
	var region: Region = RegionDocument.parse(tiles % ["🌲🔴🐚", legend])
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


## Every variant of the starting blueprint, its own region included, loads with a start for every
## player for every seed (#742): a flag's variant change purges the starting instance and loads it
## again at once (#727), with nothing to fall back on if it can't load.
func _check_start_variants() -> String:
	var variants: Array[String] = [""]
	var chosen: Dictionary = InstanceBlueprints.VARIANTS.get(InstanceBlueprints.GLADE, { })
	for flag: Variant in chosen:
		if not variants.has(str(chosen[flag])):
			variants.append(str(chosen[flag]))
	for variant: String in variants:
		for seed_value: int in INSTANCE_SEEDS:
			var state: GameState = InstanceBlueprints.create(
				InstanceBlueprints.GLADE,
				seed_value,
				GameState.MAX_PLAYERS,
				variant,
			)
			if state == null:
				return "the starting glade's variant '%s' doesn't load %d players, seed %d" % [
					variant,
					GameState.MAX_PLAYERS,
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
	var reached: Array[String] = [InstanceBlueprints.GLADE]
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


## The world (#148): the session starts in the glade (#712), and the forest loads with nobody in
## it. Only the instance a player is in steps, every instance's seed is its own and the same every
## session, and the world's hash covers every loaded instance.
func _check_world() -> String:
	var world: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.GLADE)
	var forest: GameState = world.instance(InstanceBlueprints.FOREST)
	if not world.problem.is_empty() or forest == null or forest.player(0) != null:
		return "the world didn't start, or the forest didn't load empty: " + world.problem
	var seeds: Array[int] = [world.seed_for(InstanceBlueprints.GLADE), forest.rng_seed]
	var again: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.GLADE)
	if seeds[0] == seeds[1] or again.seed_for("forest") != seeds[1]:
		return "the instances' seeds aren't their own, or differ between sessions: %s" % [seeds]
	var hashed: int = world.state_hash()
	for _tick: int in 10:
		world.step(_still())
	var glade: GameState = world.instances[InstanceBlueprints.GLADE]
	if glade.tick != 10 or forest.tick != 0 or world.active().size() != 1:
		return "the world stepped the wrong instances: glade %d, forest %d" % [
			glade.tick,
			forest.tick,
		]
	var stepped: int = world.state_hash()
	forest.tick += 1
	if hashed == stepped or world.state_hash() == stepped:
		return "the world's hash doesn't cover every loaded instance"
	return ""


func _still() -> Array[Command]:
	var commands: Array[Command] = [Command.new(Command.NO_MOVE)]
	return commands


## The web lies in one world (#187): the forest sits so that walking out of the glade's north exit
## lands next to it on the forest's way back, and for every seed no two instances overlap.
func _check_layout() -> String:
	for seed_value: int in SEEDS:
		var problem: String = _layout_problem(seed_value)
		if not problem.is_empty():
			return "seed %d: %s" % [seed_value, problem]
	var world: World = World.new(BlueprintSource.new(), 7, InstanceBlueprints.GLADE)
	var glade: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.GLADE,
		world.seed_for(InstanceBlueprints.GLADE),
	)
	var forest: Region = InstanceBlueprints.region_of(
		InstanceBlueprints.FOREST,
		world.seed_for(InstanceBlueprints.FOREST),
	)
	var exit: Vector3i = glade.exits[glade.exit_blueprints.find(InstanceBlueprints.FOREST)]
	var outside: Vector2i = Vector2i(exit.x, exit.y) + Hex.DIRECTIONS[exit.z]
	var way: Vector3i = forest.exits[forest.exit_blueprints.find(InstanceBlueprints.GLADE)]
	var back: Vector2i = Vector2i(way.x, way.y)
	var landing: Vector2i = back + world.offset(InstanceBlueprints.FOREST)
	if world.offset(InstanceBlueprints.GLADE) != Vector2i.ZERO or landing != outside:
		return "walking out of the glade's north exit doesn't land on the forest's way back"
	return ""


## Why seed `seed_value`'s web can't be laid out as one world, or "".
func _layout_problem(seed_value: int) -> String:
	return World.new(BlueprintSource.new(), seed_value, InstanceBlueprints.GLADE).layout_problem()


## For every seed the glade's way to the forest is on its start piece's north edge, three tiles wide
## (#689), where the region ends, and no exit of it leads out onto a tile of its own.
func _check_glade_exit() -> String:
	var north: Array[Vector3i] = [Vector3i(1, -5, 2), Vector3i(2, -5, 2), Vector3i(3, -5, 2)]
	for seed_value: int in SEEDS:
		var glade: Region = InstanceBlueprints.region_of(InstanceBlueprints.GLADE, seed_value)
		var way: Array[Vector3i] = []
		for i: int in glade.exits.size():
			if glade.exit_blueprints[i] == InstanceBlueprints.FOREST:
				way.append(glade.exits[i])
		var covered: bool = false
		for outside: Vector2i in glade.outside_exits():
			covered = covered or glade.has_tile(outside)
		if way != north or covered or not glade.problem.is_empty():
			return "seed %d's glade has its way to the forest at %s: %s" % [
				seed_value,
				glade.exits,
				glade.problem,
			]
	return ""


## Joins and exits are wide (#689): in every blueprint's arranged region, for every seed, two pieces
## that meet touch along at least SEAM_WIDTH walkable tiles of each, and every exit to another
## instance is at least SEAM_WIDTH tiles wide.
func _check_wide_seams() -> String:
	for instance_name: String in InstanceBlueprints.NAMES:
		var exits: Region = InstanceBlueprints.region_of(instance_name, 0)
		for target: String in exits.exit_blueprints:
			if exits.exit_blueprints.count(target) < SEAM_WIDTH:
				return "%s's exit to %s is narrower than %d tiles" % [
					instance_name,
					target,
					SEAM_WIDTH,
				]
		for seed_value: int in INSTANCE_SEEDS:
			var region: Region = InstanceBlueprints.region_of(instance_name, seed_value)
			var narrow: String = _narrow_seam(region)
			if not narrow.is_empty():
				return "%s at seed %d: %s" % [instance_name, seed_value, narrow]
	return ""


## The first two pieces of `region` that meet along fewer than SEAM_WIDTH walkable tiles of the
## first, as text, or "".
static func _narrow_seam(region: Region) -> String:
	var touching: Dictionary[String, int] = {}
	for tile: Vector2i in region.sorted_tiles():
		var piece: String = region.piece_of.get(tile, "")
		var met: Array[String] = []
		for direction: Vector2i in Hex.DIRECTIONS:
			var other: String = region.piece_of.get(tile + direction, piece)
			var walks: bool = region.is_walkable(tile) and region.is_walkable(tile + direction)
			if other != piece and walks and not met.has(other):
				met.append(other)
		for other: String in met:
			touching[piece + " and " + other] = touching.get(piece + " and " + other, 0) + 1
	for pair: String in touching:
		if touching[pair] < SEAM_WIDTH:
			return "%s meet along %d tiles" % [pair, touching[pair]]
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
## blueprint has a variant yet. A world starts with no flags from it, not even the factions'
## territory (#637), so RISEN is its only one.
class RisingSource:
	extends BlueprintSource

	const RISEN: String = "glade_risen"

	func starting_flags() -> Array[String]:
		return []

	func variant(instance_name: String, flags: Array[String]) -> String:
		var risen: bool = instance_name == InstanceBlueprints.GLADE and flags.has(RISEN)
		return InstanceBlueprints.ARENA if risen else ""
