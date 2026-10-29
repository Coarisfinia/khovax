class_name GameDriver
extends Session
## Runs the simulation at its fixed tick rate, in lockstep (#38). Real time only decides when ticks
## happen, never what they do: before each tick it polls its command sources (the local player,
## later network peers or a replay), and runs the tick once every player's command for it is known.
## It processes before everything else (process_priority in main.tscn), so the state is current when
## views draw. A session plays one world (#148, #158): every instance a player is in steps, and the
## views follow this machine's player into whichever instance they walk. A session is the span from
## loading the game to quitting it, which replays and lockstep co-op work in; it's technical and
## never shown to the player. The slices see it as a Session, whose ticks it announces.

## Ticks one frame may run; more real time than this is dropped.
const MAX_TICKS_PER_FRAME: int = 5
## How many recent ticks' state hashes the driver keeps, to compare with other players' later.
const HASH_HISTORY: int = 100
## The value of `fixed_seed` that means "roll a seed".
const ROLLED_SEED: int = -1

## The seed a fresh world starts from instead of rolling one, or ROLLED_SEED (#213): the `--seed`
## launch option (LaunchOptions, #237), which the e2e runner requires so every flow boots on the
## same world, or the test builds' own (TestMode), set before the main scene loads.
static var fixed_seed: int = ROLLED_SEED
## The instance blueprint a fresh world starts in instead of `instance`, or "": the `--instance`
## launch option (#237).
static var start_instance: String = ""
## Whether this machine's player is invincible in a fresh world (HealthFeature.make_invincible):
## the `--invincible` launch option (#1142).
static var invincible: bool = false

## The instance the session starts in, by its blueprint's name: the one the realms mark as the
## start (#865) unless set.
@export var instance: String = ""
## Hands over the saved world to resume at boot, and saves this one (#119); none in tests that
## build a driver alone.
@export var keeper: WorldKeeper
## Ties the player's quests to the session (#817), which catches them up with the world as a
## session starts; none in tests that build a driver alone.
@export var quest_tie: QuestTie
## Players in the session, in slots 0 and up. Each slot needs a command source, or ticks wait.
@export_range(1, GameState.MAX_PLAYERS) var players: int = 1
## Ticks between sampling a command and the tick it applies to: time for a network to deliver it.
@export_range(0, 20) var input_delay: int = 0

## Where every slot's commands come from; the local player's by default. Tests replace them.
var sources: Array[CommandSource] = []
var schedule: CommandSchedule
## The state hash after each of the last HASH_HISTORY ticks, by tick: the basis for spotting a
## desync between players later.
var hashes: Dictionary[int, int] = {}
## Every tick of this session so far, to play back (#35).
var recording: Replay
var _accumulated: float = 0.0


func _ready() -> void:
	if not start_instance.is_empty():
		instance = start_instance
	if instance.is_empty():
		instance = Realms.start()
	var saved: World = keeper.saved_world(BlueprintSource.new()) if keeper != null else null
	var problem: String = resume(saved) if saved != null else ""
	if not problem.is_empty():
		push_warning("the saved world can't be resumed, so a fresh one starts: " + problem)
	if saved == null or not problem.is_empty():
		start(new_seed())
	if input != null:
		sources.append(LocalSource.new(input as LocalInput, self))
	if _profile() != null:
		var _connected: int = _profile().party_changed.connect(_catch_up_party)


func _process(delta: float) -> void:
	advance(delta)


## The seed of a fresh world: `fixed_seed` if one is set, otherwise rolled here, once, with Godot's
## randomness. The seed is where a world begins, like a replay's, so rolling it lies outside the
## simulation; everything after follows from it. randi() gives 32 bits, never negative.
static func new_seed() -> int:
	if fixed_seed != ROLLED_SEED:
		return fixed_seed
	return randi()


## Starts a fresh session, in the starting instance, from `seed_value`: the APK test (#61) starts
## its own with a fixed seed. The command sources stay. This machine's player is invincible in it
## while `invincible` is set.
func start(seed_value: int) -> void:
	world = World.new(BlueprintSource.new(), seed_value, instance, players)
	# No world for an unknown or invalid instance, which InstanceBlueprints.create reports.
	if not world.problem.is_empty():
		world = null
	if world != null:
		recording = Replay.new(instance, seed_value)
		if invincible:
			HealthFeature.make_invincible(world, input.slot if input != null else 0)
			# The seed alone doesn't make the player invincible, so the recording starts from the
			# world that does, like a resumed one's.
			recording.start_world = WorldData.of(world)
		recording.begin(world)
	_begin_session()


## Resumes the saved world `saved` where it was left (#119), as WorldKeeper loaded it; returns why
## it can't, or "", and changes nothing then. Its players must be exactly the session's slots, so
## every player in it gets commands. Its recording starts from the saved world.
func resume(saved: World) -> String:
	for slot: int in GameState.MAX_PLAYERS:
		if (saved.player(slot) != null) != (slot < players):
			return "the saved world's players aren't the session's %d" % players
	world = saved
	recording = Replay.new(saved.start_name, saved.world_seed)
	recording.start_world = WorldData.of(saved)
	recording.begin(saved)
	_begin_session()
	return ""


## A new session's schedule, from the world's tick on, with no hashes and no time due yet, its world
## handed to the keeper to save, the player's outbox drawing its next ids above the ones the world
## holds (#942), and the player's quests caught up with the events that already
## changed the world (#756), and the world with the player's gear and party (#818): a new world,
## or one saved before a change of them, gets requests for what's equipped and who's carried. A
## monster dominated since the save comes along that way; a companion chosen before it (#55) stays
## theirs while they still carry it.
func _begin_session() -> void:
	schedule = CommandSchedule.new(players, input_delay, world.tick if world != null else 0)
	hashes.clear()
	_accumulated = 0.0
	if keeper != null:
		keeper.world = world
	var slot: int = input.slot if input != null else 0
	# Before anything posts a request: its id goes above every one the world holds (#942).
	if _profile() != null and world != null:
		_profile().catch_up_outbox(OutboxReceipts.highest(world.stores[slot]))
	# The quests meet the world as it is: events raised before they came still count (#756).
	if quest_tie != null and world != null:
		quest_tie.catch_up(world.flags)
	if _profile() != null and world != null:
		_profile().catch_up_gear(world.stores[slot])
	_catch_up_party()


## Catches the world up with who this machine's player carries and how each leans (#818, #1358):
## as a session starts, and at once when the party or a carried monster's taken nodes or species
## change during it (#1459, #1478, #1485), so the run goes in their next commands instead of
## waiting for the next session.
func _catch_up_party() -> void:
	var held: ProfileHolder = _profile()
	if held != null and world != null:
		held.catch_up_party(world.stored(input.slot if input != null else 0, CompanionFeature.ID))


## The session's holder as the profile slice's ProfileHolder (#1663), whose outbox, gear and party
## the driver catches the world up with; null without one.
func _profile() -> ProfileHolder:
	return holder as ProfileHolder


## Holds the ticks while a menu is open (`on`, #302), or lets them run again: real time stops
## reaching the driver, so the world, its replay and its hashes stay as if no time passed. In co-op
## it never holds them: lockstep keeps every player's world running together (#38).
func pause(on: bool) -> void:
	if players == 1:
		set_process(not on)


## Runs as many whole ticks as `delta` adds up to, at most MAX_TICKS_PER_FRAME. Called every
## frame; tests call it with fixed steps.
func advance(delta: float) -> void:
	if world == null:
		return
	_accumulated += delta
	var tick_seconds: float = 1.0 / Simulation.TICKS_PER_SECOND
	var ticks: int = 0
	while _accumulated >= tick_seconds and ticks < MAX_TICKS_PER_FRAME and _step():
		_accumulated -= tick_seconds
		ticks += 1
	# After a long frame (a hitch, a backgrounded tab), the rest of the time is dropped rather than
	# caught up, which would freeze the game in a growing backlog. Waiting for a late player's
	# command works the same way: the game holds, at most one tick's time stays due, and once the
	# command arrives that tick runs and the normal pace resumes, without a burst of catching up.
	# This only shifts when ticks run; what they do still depends on the commands alone.
	_accumulated = minf(_accumulated, tick_seconds)


## Runs the next tick if every player's command for it is known; returns whether it ran.
func _step() -> bool:
	var tick: int = world.tick + 1
	for source: CommandSource in sources:
		source.poll(schedule, tick, state)
	if not schedule.is_complete(tick):
		return false
	var commands: Array[Command] = schedule.take(tick)
	var before: GameState = state
	world.step(commands)
	last_commands = commands
	recording.record(world, commands)
	hashes[tick] = world.state_hash()
	var _forgot: bool = hashes.erase(tick - HASH_HISTORY)
	# A copy of the local player's instance's events (the simulation clears its list when the next
	# tick starts): the instance they were in, and the one they walked into if they left it.
	var events: Array[RefCounted] = []
	if before != null:
		events.assign(before.events)
	if state != null and state != before:
		events.append_array(state.events)
	# The world's own: who came into another instance (#370).
	events.append_array(world.events)
	announce(world.tick, events)
	return true


## The blueprint name of the instance this machine's player is in, or of the starting one before
## they're placed; "" without a world.
func local_instance_name() -> String:
	if world == null:
		return ""
	var slot: int = input.slot if input != null else 0
	var where: String = world.instance_of(slot)
	return where if not where.is_empty() else instance


## How far real time is into the next tick, from 0 to 1: views draw between ticks with it.
func tick_fraction() -> float:
	return clampf(_accumulated * Simulation.TICKS_PER_SECOND, 0.0, 1.0)
