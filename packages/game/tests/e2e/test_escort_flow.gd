extends RefCounted
## Escort flow (#1588, #1553): a guide, a person whose seal the region places too, follows the
## player who talked to them, walking after them through the corridor while the player walks
## through them, and opens their seal once led near it: its boulders turn to ground and the guide
## raises `<their id>_opened`, so the player walks on through. A world saved mid-escort comes back
## the same. A player who leaves through the exit first leaves the guide to go ahead: alone, the
## guide
## is at the seal and opens it in that same tick; with another player still there, they walk there
## and open it. Either way the rules raise that the guide went ahead for the player who left. A seal
## on a tile anyone walks, or one whose person the region piece doesn't place, is refused.

const SEED: int = 5
const GUIDE: String = "teska_na_amvrel"
## A corridor running east: the exit west of player 1's start, the guide east of it, player 2 (when
## there's one) further on, and the guide's seal, a boulder, with ground behind it.
const CORRIDOR: String = "🚪🔴🧙🟫🔵🟫🟫🟫🪨🟫"
const LEGEND: String = """- `🔵`: where player 2 starts
- `🚪`: exit to the west
- `🧙`: a person to talk to, teska_na_amvrel
- `🪨`: boulder; sealed until teska_na_amvrel opens it
"""
const EAST: int = 0
const WEST: int = 3
## Each tile of the corridor, by its place from the west.
const EXIT_AT: int = 0
const START_AT: int = 1
const GUIDE_AT: int = 2
const SEAL_AT: int = 8


func run(_tree: SceneTree) -> String:
	var result: String = _lead_to_seal()
	if result.is_empty():
		result = _go_ahead_alone()
	if result.is_empty():
		result = _go_ahead_seen()
	if result.is_empty():
		result = _refuse_bad_seals()
	return result


## Walking into the guide talks to them, and they follow; the player walks through them to two
## tiles from the seal, the guide walks after and opens it, and the player walks on through. A save
## made while the guide follows loads back the same.
static func _lead_to_seal() -> String:
	var state: GameState = _corridor(1)
	var events: Array[RefCounted] = FlowSteps.step(state, EAST)
	if _escort(state).escorts != { _guide(state): 0 } or state.player(0).tile != _at(START_AT):
		return "talking to the guide didn't make them follow: %s" % [_escort(state).escorts]
	events.append_array(FlowSteps.step(state, EAST))
	events.append_array(FlowSteps.step(state, EAST))
	var saved: String = _reloads(state)
	if not saved.is_empty():
		return saved
	for _tile: int in SEAL_AT - 2 - _place_of(state.player(0).tile):
		events.append_array(FlowSteps.step(state, EAST))
	for _tick: int in MovementFeature.MOVE_TICKS * 6:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		events.append_array(state.events)
	if state.region.terrain[_at(SEAL_AT)] != Region.GROUND or _opened(events) != 1:
		return "the guide led to their seal didn't open it once: %d" % _opened(events)
	if _went_ahead(events) != 0 or state.entity(_guide(state)).tile != _at(SEAL_AT - 1):
		return "the guide went ahead, or stands on %s" % state.entity(_guide(state)).tile
	for _tile: int in 3:
		events.append_array(FlowSteps.step(state, EAST))
	if state.player(0).tile != _at(SEAL_AT + 1):
		return "the player didn't walk through the open seal: %s" % state.player(0).tile
	return ""


## A world saved with the guide following loads back with the same hash.
static func _reloads(state: GameState) -> String:
	var loaded: GameState = FlowSteps.rules_on(FlowSteps.BASIC, _ground(), SEED)
	var data: DataReader = DataReader.new(state.to_data())
	if loaded.load_changed_tiles(data):
		loaded.load_data(data)
	if data.failed() or loaded.state_hash() != state.state_hash():
		return "a world saved mid-escort didn't load back the same: %s" % data.problem
	return ""


## Alone, the player who talked to the guide walks out through the exit: in that tick the rules
## raise that the guide went ahead for them, and the guide is beside the seal with it open.
static func _go_ahead_alone() -> String:
	var state: GameState = _corridor(1)
	var _talked: Array[RefCounted] = FlowSteps.step(state, EAST)
	var _out: Array[RefCounted] = FlowSteps.step(state, WEST)
	Simulation.step(state, FlowSteps.command(WEST))
	if not state.events.any(func(event: RefCounted) -> bool: return event is ExitTaken):
		return "the player didn't walk out through the exit"
	if _went_ahead(state.events) != 1 or _opened(state.events) != 1:
		return "leaving alone didn't send the guide ahead to open the seal at once"
	if state.entity(_guide(state)).tile != _at(SEAL_AT - 1):
		return "the guide gone ahead stands on %s" % state.entity(_guide(state)).tile
	return ""


## With player 2 still in the corridor, player 1 talks to the guide and walks out: the guide goes
## ahead walking, step by step, and opens the seal once there.
static func _go_ahead_seen() -> String:
	var state: GameState = _corridor(2)
	var _talked: Array[RefCounted] = FlowSteps.step(state, EAST, 2)
	var _out: Array[RefCounted] = FlowSteps.step(state, WEST, 2)
	Simulation.step(state, FlowSteps.commands([WEST, Command.NO_MOVE]))
	if _went_ahead(state.events) != 1 or _opened(state.events) != 0:
		return "leaving with player 2 still there didn't send the guide ahead on foot"
	var events: Array[RefCounted] = state.events.duplicate()
	for _tick: int in MovementFeature.MOVE_TICKS * (SEAL_AT + 2):
		Simulation.step(state, FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
		events.append_array(state.events)
	var moved: int = 0
	for event: RefCounted in events:
		if event is EntityMoved and (event as EntityMoved).entity_id == _guide(state):
			moved += 1
	if moved != SEAL_AT - 1 - GUIDE_AT or _opened(events) != 1:
		return "the guide gone ahead took %d steps and opened %d times" % [moved, _opened(events)]
	return ""


## A seal on ground, and one whose person the corridor doesn't place, are refused.
static func _refuse_bad_seals() -> String:
	var on_ground: String = LEGEND.replace("boulder; sealed", "ground; sealed")
	if FlowSteps.region(CORRIDOR, on_ground).problem.is_empty():
		return "a seal on ground was read"
	var nobody: String = LEGEND.replace("until teska_na_amvrel", "until nobody_here")
	if FlowSteps.region(CORRIDOR, nobody).problem.is_empty():
		return "a seal of a person the corridor doesn't place was read"
	return ""


## The corridor with the playground's rules, its exit leading to the glade, and `players` players
## on their starts.
static func _corridor(players: int) -> GameState:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, _ground(), SEED)
	for slot: int in players:
		var _player: Entity = state.add_entity(slot, state.region.starts[slot])
	return state


## The corridor's region, its exit leading to the glade.
static func _ground() -> Region:
	var ground: Region = FlowSteps.region(CORRIDOR, LEGEND)
	ground.exit_blueprints[0] = FlowSteps.GLADE
	return ground


## The corridor's tile `place` tiles east of its exit.
static func _at(place: int) -> Vector2i:
	return _ground_exit() + Vector2i(place - EXIT_AT, 0)


## How many tiles east of the exit `tile` is.
static func _place_of(tile: Vector2i) -> int:
	return tile.x - _ground_exit().x + EXIT_AT


## The corridor's exit tile.
static func _ground_exit() -> Vector2i:
	var exit: Vector3i = FlowSteps.region(CORRIDOR, LEGEND).exits[0]
	return Vector2i(exit.x, exit.y)


static func _escort(state: GameState) -> EscortFeature:
	return state.feature(EscortFeature.ID) as EscortFeature


## The guide's entity id.
static func _guide(state: GameState) -> int:
	return (state.feature(NpcFeature.ID) as NpcFeature).npcs[0]


## How often `events` say the guide opened their seal.
static func _opened(events: Array[RefCounted]) -> int:
	var count: int = 0
	for event: RefCounted in events:
		if event is EventEmitted and (event as EventEmitted).event_name == GUIDE + "_opened":
			count += 1
	return count


## How often `events` say the guide went ahead.
static func _went_ahead(events: Array[RefCounted]) -> int:
	var count: int = 0
	for event: RefCounted in events:
		if event is GuideWentAhead and (event as GuideWentAhead).npc == GUIDE:
			count += 1
	return count
