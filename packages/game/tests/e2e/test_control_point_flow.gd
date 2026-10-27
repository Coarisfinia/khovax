extends RefCounted
## Control point flow (#580, #643): only instances made for control point battles have control
## points, which their region pieces mark in the legend, each with the side holding it at the start;
## the region brings the feature that runs them (#879), so ordinary instances have none. Who holds
## each point is state, hashed and saved. A side holding no control point loses the battle, once.
## The sides hold their points together, never a player alone, so co-op players share them (#74).

const SEED: int = 3
## A battle ground: the attackers start with one control point, the defenders hold two and one
## more is held by nobody.
## Written with \n, as the formatter strips a multi-line string's leading spaces.
const GRID: String = " 🟫🚩🟫🟫\n🟫🔴🟫⚪🟫\n 🏯🟫🏯🟫"
const LEGEND: String = """- `🚩`: a control point, held by the attackers
- `🏯`: a control point, held by the defenders
- `⚪`: a control point, held by nobody
"""
const ATTACKERS: int = ControlPointSides.ATTACKERS
const DEFENDERS: int = ControlPointSides.DEFENDERS
const NOBODY: int = ControlPointSides.NOBODY
## Who holds each of GRID's control points at the start.
const HELD: Dictionary[Vector2i, int] = {
	Vector2i(0, -1): ATTACKERS,
	Vector2i(1, 0): NOBODY,
	Vector2i(-2, 1): DEFENDERS,
	Vector2i(0, 1): DEFENDERS,
}


func run(_tree: SceneTree) -> String:
	var steps: Array[Callable] = [
		_check_ordinary_instances,
		_check_marked,
		_check_unknown_side,
		_check_hashed,
		_check_lost,
		_check_saved,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return ""


## No instance of the game's own is a battle yet: none has control points.
func _check_ordinary_instances() -> String:
	for instance_name: String in InstanceBlueprints.names():
		if InstanceBlueprints.create(
			instance_name,
			SEED,
			0,
		).feature(ControlPointFeature.ID) != null:
			return "%s, an ordinary instance, has control points" % instance_name
	return ""


## The legend's control points are the feature's, in tile order, each held as the legend says, and
## a battle both sides hold points in goes on.
func _check_marked() -> String:
	var state: GameState = _battle()
	var points: ControlPointFeature = _points(state)
	if points == null:
		return "a region marking control points doesn't bring the feature"
	var expected: Array[Vector2i] = []
	expected.assign(HELD.keys())
	expected.sort()
	if points.points != expected:
		return "the control points are %s, not %s" % [points.points, expected]
	var holders: Array[int] = []
	for point: Vector2i in expected:
		holders.append(HELD[point])
	if points.holders != holders:
		return "the control points are held by %s, not %s" % [points.holders, holders]
	if _lost_in(state, 3) != NOBODY or points.loser != NOBODY:
		return "a battle both sides hold control points in ended"
	return ""


## A control point naming a side there is none of is refused.
func _check_unknown_side() -> String:
	var legend: String = "- `🚩`: a control point, held by the wanderers\n"
	if FlowSteps.region("🔴🚩", legend).problem.is_empty():
		return "a control point held by an unknown side was read"
	return ""


## Who holds a control point, and who lost, are in the state hash.
func _check_hashed() -> String:
	var base: int = _battle().state_hash()
	var changed: GameState = _battle()
	_points(changed).holders[0] = NOBODY if _points(changed).holders[0] != NOBODY else ATTACKERS
	if changed.state_hash() == base:
		return "changing who holds a control point didn't change the state hash"
	var lost: GameState = _battle()
	_points(lost).loser = DEFENDERS
	if lost.state_hash() == base:
		return "a lost battle hashes like one going on"
	return ""


## Once the defenders hold no control point (here, as the attackers took them all), they lost the
## battle: told once, never again.
func _check_lost() -> String:
	var state: GameState = _battle()
	var points: ControlPointFeature = _points(state)
	for index: int in points.holders.size():
		if points.holders[index] == DEFENDERS:
			points.holders[index] = ATTACKERS
	if _lost_in(state, 1) != DEFENDERS or points.loser != DEFENDERS:
		return "the defenders holding no control point didn't lose the battle"
	if _lost_in(state, 3) != NOBODY:
		return "a battle was lost twice"
	return ""


## A saved battle loads with the same holders and loser, and a save that doesn't fit the region's
## control points is refused.
func _check_saved() -> String:
	var state: GameState = _battle()
	_points(state).holders[0] = ATTACKERS
	_points(state).loser = DEFENDERS
	var loaded: GameState = _battle()
	_points(loaded).load_values(loaded, DataReader.new(_points(state).save_values()))
	if loaded.state_hash() != state.state_hash():
		return "a saved battle didn't load as it was"
	var bad: DataReader = DataReader.new({ "holders": [ATTACKERS], "loser": NOBODY })
	_points(_battle()).load_values(loaded, bad)
	if not bad.failed():
		return "a save with the wrong number of control points was read"
	return ""


## A battle on GRID with the playground's rules and one player.
func _battle() -> GameState:
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, FlowSteps.region(GRID, LEGEND), SEED)
	var _player: Entity = state.add_entity(0, state.region.starts[0])
	return state


static func _points(state: GameState) -> ControlPointFeature:
	return state.feature(ControlPointFeature.ID) as ControlPointFeature


## The side a BattleLost event says lost within `ticks` ticks of `state`, or NOBODY.
static func _lost_in(state: GameState, ticks: int) -> int:
	for _tick: int in ticks:
		Simulation.step(state, FlowSteps.command(Command.NO_MOVE))
		for event: RefCounted in state.events:
			if event is BattleLost:
				return (event as BattleLost).side
	return NOBODY
