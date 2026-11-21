extends RefCounted
## Scene runner flow (#2415): deterministic scenes defined as JSONC content data (loaded from
## resource packs), starting on an EventEmitted (legend emitting event, escape, quest event),
## running wait/move/strike/emit steps inside the simulation while SceneHoldFeature holds every
## player and pauses wild attacks and hunts, with state hashing and save/reload mid-scene.

const SEED: int = 11
const EAST: int = 0
const WEST: int = 3
const NPC_ID: String = "teska_na_amvrel"
const AMBUSHER_SPECIES: String = "ombulumo"
const PREY_SPECIES: String = "ombulumo"


func run(_tree: SceneTree) -> String:
	var checks: Array[Callable] = [
		_check_content_parsing,
		_check_content_refusals,
		_check_pack_scenes_section,
		_check_feature_order,
		_check_steps_and_hold,
		_check_escape_triggers_scene,
		_check_determinism_and_save_reload,
		_check_corrupt_saves_refused,
	]
	for check: Callable in checks:
		var result: String = check.call()
		if not result.is_empty():
			return result
	return ""


## Valid JSONC scene definitions parse cleanly and filter by instance.
static func _check_content_parsing() -> String:
	var valid: String = """// A deterministic ambush scene
{
	"id": "ambush",
	"instance": "lumwen_hoal",
	"on": "boss_fled",
	"once": true,
	"steps": [
		{ "kind": "wait", "ticks": 3 },
		{ "kind": "move", "actor": "ambusher", "to": [2, 0], "pace": 4 },
		{ "kind": "strike", "actor": "ambusher", "target": "prey", "amount": 50 },
		{ "kind": "strike", "actor": "ambusher", "target": "prey", "amount": 10, "lethal": true },
		{ "kind": "emit", "event": "ambush_done" }
	]
}"""
	var content: SceneContent = SceneContent.new()
	var problem: String = content.add("ambush", valid)
	if not problem.is_empty():
		return "valid scene was refused: " + problem
	if not content.has_for("lumwen_hoal") or content.has_for("senwel_sael"):
		return "SceneContent.has_for didn't filter by instance"
	var parsed: SceneScript = content.for_instance("lumwen_hoal").get("ambush")
	if parsed == null or parsed.steps.size() != 5 or parsed.on != "boss_fled":
		return "parsed scene didn't keep its fields"
	if parsed.steps[1].to != Vector2i(2, 0) or parsed.steps[1].pace != 4:
		return "parsed move step didn't keep coordinates and pace"
	if parsed.steps[2].lethal or not parsed.steps[3].lethal:
		return "parsed strike step didn't keep default/explicit lethal"
	return ""


## Malformed scene JSONC definitions are refused.
static func _check_content_refusals() -> String:
	var head: String = "{\"id\": \"a\", \"on\": \"ev\", \"steps\": ["
	var bad_cases: Dictionary[String, String] = {
		"not an object": "[]",
		"unknown field": (
			"{\"id\": \"a\", \"on\": \"ev\", \"extra\": 1,"
			+ " \"steps\": [{\"kind\": \"wait\", \"ticks\": 1}]}"
		),
		"id mismatch": (
			"{\"id\": \"b\", \"on\": \"ev\", \"steps\": [{\"kind\": \"wait\", \"ticks\": 1}]}"
		),
		"bad on": (
			"{\"id\": \"a\", \"on\": \"Bad\", \"steps\": [{\"kind\": \"wait\", \"ticks\": 1}]}"
		),
		"empty steps": head + "]}",
		"unknown step kind": head + "{\"kind\": \"jump\"}]}",
		"zero wait ticks": head + "{\"kind\": \"wait\", \"ticks\": 0}]}",
		"bad move coords": head + "{\"kind\": \"move\", \"actor\": \"e\", \"to\": [1]}]}",
		"zero move pace": (
			head + "{\"kind\": \"move\", \"actor\": \"e\", \"to\": [1, 0], \"pace\": 0}]}"
		),
		"zero strike amount": (
			head + "{\"kind\": \"strike\", \"actor\": \"e\", \"target\": \"d\", \"amount\": 0}]}"
		),
		"non-bool lethal": (
			head
			+ "{\"kind\": \"strike\", \"actor\": \"e\", \"target\": \"d\","
			+ " \"amount\": 5, \"lethal\": 1}]}"
		),
		"bad emit event": head + "{\"kind\": \"emit\", \"event\": \"Bad!\"}]}",
	}
	for label: String in bad_cases:
		if not _refuses_scene(bad_cases[label]):
			return "invalid scene (%s) wasn't refused" % label
	return ""


static func _refuses_scene(text: String) -> bool:
	return not SceneContent.new().add("a", text).is_empty()


## ResourcePack allows omitting `scenes`, accepts valid `.jsonc` entries, and refuses bad ones.
static func _check_pack_scenes_section() -> String:
	var base: String = (
		"{\"id\": \"p\", \"name\": \"n\", \"version\": \"1.0.0\", \"game_version\": \"0.1.0\","
		+ " \"textures\": {}, \"models\": {}, \"audio\": {}, \"regions\": {},"
		+ " \"region_pieces\": {}, \"realms\": {}, \"quests\": {}, \"species\": {},"
		+ " \"translations\": {}, \"tiles\": {}, \"loot_tables\": {}, \"materials\": {},"
		+ " \"harvest_tables\": {}, \"tonics\": {}, \"runes\": {}%s}"
	)
	var without_scenes: ResourcePack = ResourcePack.parse(base % "", "res://")
	if not without_scenes.problem.is_empty():
		return "pack without optional scenes section was refused: " + without_scenes.problem
	var with_scenes: ResourcePack = ResourcePack.parse(
		base % ", \"scenes\": {\"intro\": \"scenes/intro.jsonc\"}",
		"res://",
	)
	if not with_scenes.problem.is_empty():
		return "pack with valid scenes section was refused: " + with_scenes.problem
	if with_scenes.files_of("scenes").get("intro", "") != "scenes/intro.jsonc":
		return "pack didn't expose its scenes section"
	var bad_ext: ResourcePack = ResourcePack.parse(
		base % ", \"scenes\": {\"intro\": \"scenes/intro.md\"}",
		"res://",
	)
	if bad_ext.problem.is_empty():
		return "pack with non-jsonc scene file wasn't refused"
	return ""


## FeatureFactories places SceneHoldFeature and SceneFeature in a valid order with all standard
## rules and region features.
static func _check_feature_order() -> String:
	var region: Region = _arena_region()
	var setup: FeatureSetup = FeatureSetup.new()
	setup.instance = FlowSteps.BASIC
	setup.region = region
	var listed: Array[String] = InstanceBlueprints.blueprint(FlowSteps.BASIC).features.duplicate()
	listed.append_array(RegionFeatures.of(region))
	listed.append(SceneHoldFeature.ID)
	listed.append(SceneFeature.ID)
	var ordered: Array[Feature] = FeatureFactories.build(listed, setup)
	var problem: String = GameState.order_problem(ordered)
	if not problem.is_empty():
		return "scene features failed order check: " + problem
	return ""


## Runs wait, move (hidden wild monster + NPC), non-lethal strike, lethal strike, and emit while
## verifying co-op player hold, shielding, wild attack & hunt pause, and `once` protection.
static func _check_steps_and_hold() -> String:
	var state: GameState = _scene_state(_ambush_scene(), 2)
	var scenes: SceneFeature = state.feature(SceneFeature.ID) as SceneFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var ambusher_id: int = _wild_by_target(wild, "ambusher")
	var prey_id: int = _wild_by_target(wild, "prey")
	if ambusher_id == 0 or prey_id == 0 or not hiding.is_hidden(ambusher_id):
		return "arena setup missing hidden ambusher or prey"
	var trigger_cmd: Array[Command] = [
		_quest_event_cmd(1, "ambush_start"),
		Command.new(),
	]
	Simulation.step(state, trigger_cmd)
	if not scenes.is_running() or scenes.active_id != "ambush":
		return "EventEmitted didn't start the scene"
	var run_problem: String = _run_ambush_to_end(state, ambusher_id, prey_id)
	if not run_problem.is_empty():
		return run_problem
	return _check_release_and_once(state, ambusher_id, prey_id)


static func _run_ambush_to_end(state: GameState, ambusher_id: int, prey_id: int) -> String:
	var scenes: SceneFeature = state.feature(SceneFeature.ID) as SceneFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var p0_held: Vector2i = state.player(0).tile
	var p1_held: Vector2i = state.player(1).tile
	var flags: Dictionary[String, bool] = {}
	for _tick: int in 200:
		if not scenes.is_running():
			break
		Simulation.step(state, FlowSteps.commands([EAST, WEST]))
		var hold_err: String = _check_hold_tick(state, p0_held, p1_held, flags)
		if not hold_err.is_empty():
			return hold_err
		_record_scene_events(state.events, ambusher_id, flags)
		if scenes.step_index == 3 and health.hp_of(
			state,
			prey_id,
		) == 1 and wild.monsters.has(prey_id):
			flags["non_lethal"] = true
	if scenes.is_running():
		return "scene didn't finish within 200 ticks"
	if not flags.get("held", false) or not flags.get("revealed", false):
		return "scene didn't hold players or reveal hidden ambusher"
	if not flags.get("non_lethal", false) or not flags.get("done", false):
		return "non-lethal strike or emit step didn't take effect"
	return ""


static func _check_hold_tick(
	state: GameState,
	p0_held: Vector2i,
	p1_held: Vector2i,
	flags: Dictionary[String, bool],
) -> String:
	var hold: SceneHoldFeature = state.feature(SceneHoldFeature.ID) as SceneHoldFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if hold.paused:
		flags["held"] = true
		if not health.is_shielded(state.player(0).id) or not health.is_shielded(state.player(1).id):
			return "held players weren't shielded during scene"
		if state.feature(WildAttackFeature.ID).enabled or state.feature(HuntFeature.ID).enabled:
			return "wild attacks or hunts weren't paused during scene"
	if state.player(0).tile != p0_held or state.player(1).tile != p1_held:
		return "a held player moved during the scene"
	return ""


static func _record_scene_events(
	events: Array[RefCounted],
	ambusher_id: int,
	flags: Dictionary[String, bool],
) -> void:
	for ev: RefCounted in events:
		if ev is MonsterJumpedOut and (ev as MonsterJumpedOut).monster_id == ambusher_id:
			flags["revealed"] = true
		if ev is EventEmitted and (ev as EventEmitted).event_name == "ambush_done":
			flags["done"] = true


static func _check_release_and_once(state: GameState, ambusher_id: int, prey_id: int) -> String:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var npcs: NpcFeature = state.feature(NpcFeature.ID) as NpcFeature
	if state.entity(ambusher_id).tile != Vector2i(1, 0) or not wild.is_fainted(prey_id):
		return "ambusher position or lethal strike outcome wrong"
	if state.entity(npcs.npcs[0]).tile != Vector2i(-1, 0):
		return "NPC didn't reach move target (-1, 0)"
	var before_release: Vector2i = state.player(1).tile
	Simulation.step(state, FlowSteps.commands([EAST, WEST]))
	var hold: SceneHoldFeature = state.feature(SceneHoldFeature.ID) as SceneHoldFeature
	var health: HealthFeature = state.feature(HealthFeature.ID) as HealthFeature
	if (hold.paused
			or health.is_shielded(state.player(0).id)
			or health.is_shielded(state.player(1).id)):
		return "SceneHoldFeature didn't release players after scene finished"
	if not state.feature(WildAttackFeature.ID).enabled or not state.feature(HuntFeature.ID).enabled:
		return "wild attacks or hunts weren't re-enabled after scene finished"
	if state.player(1).tile == before_release:
		return "player 1 couldn't move after scene released them"
	var replay_cmd: Array[Command] = [_quest_event_cmd(2, "ambush_start")]
	Simulation.step(state, replay_cmd)
	if (state.feature(SceneFeature.ID) as SceneFeature).is_running():
		return "once scene replayed after finishing"
	return ""


## A wild monster escaping at its health line (EscapeFeature) raises its EventEmitted and starts
## a scene listening for that event.
static func _check_escape_triggers_scene() -> String:
	var legend: String = (
		"- `🐺`: a wild monster, always ombulumo, escaping at 50%, emitting boss_fled\n"
	)
	var region: Region = FlowSteps.region("🔴🟫🐺", legend)
	if not region.problem.is_empty():
		return "escape scene region failed: " + region.problem
	var scene: SceneScript = SceneScript.new()
	scene.id = "after_escape"
	scene.on = "boss_fled"
	scene.steps = [SceneStep.make_wait(2), SceneStep.make_emit("escape_seen")]
	var species_hps: Dictionary[String, int] = { AMBUSHER_SPECIES: 100 }
	var ordered: Array[Feature] = [
		SceneHoldFeature.new(),
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(species_hps),
		WildMonsterFeature.new(),
		EscapeFeature.new(),
		SceneFeature.new({ scene.id: scene }),
	]
	var state: GameState = GameState.new(region, SEED, ordered)
	var _p0: Entity = state.add_entity(0, region.starts[0])
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	wild.wound(state, wild.monsters[0], 999, true)
	Simulation.step(state, [])
	var scenes: SceneFeature = state.feature(SceneFeature.ID) as SceneFeature
	if not scenes.is_running() or scenes.active_id != "after_escape":
		return "EscapeFeature's EventEmitted didn't start the scene"
	return ""


## Same inputs yield identical hashes tick-by-tick; saving mid-scene and reloading matches the
## exact state hash and finishes cleanly without replaying earlier steps.
static func _check_determinism_and_save_reload() -> String:
	var script: SceneScript = _ambush_scene()
	var run_a: GameState = _scene_state(script, 1)
	var run_b: GameState = _scene_state(script, 1)
	var saved_data: Dictionary = {}
	var saved_hash: int = 0
	var hashes_seen: Dictionary[int, bool] = {}
	var trigger: Array[Command] = [_quest_event_cmd(1, "ambush_start")]
	for tick: int in 40:
		var cmds: Array[Command] = trigger if tick == 0 else FlowSteps.command(EAST)
		Simulation.step(run_a, cmds)
		Simulation.step(run_b, cmds)
		if run_a.state_hash() != run_b.state_hash():
			return "scene diverged between identical runs at tick %d" % tick
		hashes_seen[run_a.state_hash()] = true
		if tick == 6:
			saved_data = run_a.to_data()
			saved_hash = run_a.own_hash()
	if hashes_seen.size() < 4 or saved_data.is_empty():
		return "state hash didn't reflect scene progression"
	return _verify_mid_scene_reload(script, saved_data, saved_hash, run_a.own_hash())


static func _verify_mid_scene_reload(
	script: SceneScript,
	saved_data: Dictionary,
	saved_hash: int,
	final_hash: int,
) -> String:
	var reloaded: GameState = _scene_state(script, 0)
	var reader: DataReader = DataReader.new(saved_data)
	reloaded.load_data(reader)
	if reader.failed():
		return "mid-scene reload failed: " + reader.problem
	if reloaded.own_hash() != saved_hash:
		return "reloaded mid-scene hash didn't match saved hash"
	var reloaded_scenes: SceneFeature = reloaded.feature(SceneFeature.ID) as SceneFeature
	if not reloaded_scenes.is_running() or reloaded_scenes.step_index < 1:
		return "reloaded scene didn't resume at its saved step"
	for _tick: int in range(7, 40):
		Simulation.step(reloaded, FlowSteps.command(EAST))
	if reloaded.own_hash() != final_hash:
		return "reloaded scene didn't finish at the exact same final state hash"
	return ""


## Corrupt save data is refused cleanly by SceneFeature.load_values.
static func _check_corrupt_saves_refused() -> String:
	var state: GameState = _scene_state(_ambush_scene(), 1)
	var scenes: SceneFeature = state.feature(SceneFeature.ID) as SceneFeature
	var bad_idle: DataReader = DataReader.new({
		"active": "", "step": 1, "ticks": 0, "completed": [],
	})
	scenes.load_values(state, bad_idle)
	if not bad_idle.failed():
		return "idle scene save with non-zero step wasn't refused"
	var bad_active: DataReader = DataReader.new({
		"active": "missing_scene", "step": 0, "ticks": 0, "completed": [],
	})
	scenes.load_values(state, bad_active)
	if not bad_active.failed():
		return "save naming unknown active scene wasn't refused"
	return ""


static func _arena_region() -> Region:
	var legend: String = (
		"- `🔵`: where player 2 starts\n"
		+ "- `🧙`: a person to talk to, " + NPC_ID + "\n"
		+ "- `🌿`: a wild monster, always " + AMBUSHER_SPECIES
		+ ", the quest target ambusher, on shrubs\n"
		+ "- `🐺`: a wild monster, always " + PREY_SPECIES + ", the quest target prey\n"
	)
	return FlowSteps.region("🔴🟫🧙🟫🐺🟫🌿🟫🔵", legend)


static func _ambush_scene() -> SceneScript:
	var script: SceneScript = SceneScript.new()
	script.id = "ambush"
	script.on = "ambush_start"
	script.once = true
	script.steps = [
		SceneStep.make_wait(3),
		SceneStep.make_move("ambusher", Vector2i(1, 0), 2),
		SceneStep.make_strike("ambusher", "prey", 9999, false),
		SceneStep.make_strike("ambusher", "prey", 10, true),
		SceneStep.make_move(NPC_ID, Vector2i(-1, 0)),
		SceneStep.make_emit("ambush_done"),
	]
	return script


static func _scene_state(script: SceneScript, players: int) -> GameState:
	var region: Region = _arena_region()
	var species_hps: Dictionary[String, int] = { AMBUSHER_SPECIES: 100 }
	var species_strengths: Dictionary[String, int] = { AMBUSHER_SPECIES: 10 }
	var quest_events: Dictionary[int, String] = {
		CommandCodes.of("ambush_start"): "ambush_start",
	}
	var ordered: Array[Feature] = [
		DialogHoldFeature.new(),
		SceneHoldFeature.new(),
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(species_hps),
		WildMonsterFeature.new([], [], species_strengths),
		ScheduleFeature.new(),
		DominationFeature.new(),
		WildAttackFeature.new(),
		HuntFeature.new(),
		HidingFeature.new(),
		NpcFeature.new(),
		DialogFeature.new(),
		QuestEventFeature.new(quest_events),
		SceneFeature.new({ script.id: script }),
	]
	var state: GameState = GameState.new(region, SEED, ordered)
	for slot: int in players:
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	return state


static func _quest_event_cmd(request_id: int, event_name: String) -> Command:
	var cmd: Command = Command.new()
	cmd.request = request_id
	cmd.request_kind = OutboxEntry.QUEST_EVENT
	cmd.request_data = CommandCodes.of(event_name)
	return cmd


static func _wild_by_target(wild: WildMonsterFeature, target_name: String) -> int:
	for monster_id: int in wild.monsters:
		if wild.target_of(monster_id) == target_name:
			return monster_id
	return 0
