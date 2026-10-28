extends RefCounted
## Control point flow (#580, #643): only instances made for control point battles have control
## points, which their region pieces mark in the legend, each with the side holding it at the start;
## the region brings the feature that runs them (#879), so ordinary instances have none. Who holds
## each point is state, hashed and saved. A side holding no control point loses the battle, once.
## The sides hold their points together, never a player alone, so co-op players share them (#74).
## A player takes a point by closing a ring around it and placing their totem on it (#644), which
## wards it: one totem per point.

const SEED: int = 3
## A battle ground: the attackers start with one control point, the defenders hold two and one
## more is held by nobody.
## Written with \n, as the formatter strips a multi-line string's leading spaces.
const GRID: String = " 🟫🚩🟫🟫\n🟫🔴🟫⚪🟫\n 🏯🟫🏯🟫"
const LEGEND: String = """- `🚩`: a control point, held by the attackers
- `🏯`: a control point, held by the defenders
- `⚪`: a control point, held by nobody
"""
## A battle ground with room for rings: the attackers' point and one of the defenders' inside,
## each with a ring of ground around it, and the defenders' other point on the edge.
const RING_GRID: String = (
	" 🟫🟫🟫🟫🟫🟫🟫\n🟫🔴🟫🟫🟫🟫🟫\n 🟫🚩🟫🟫🏯🟫🟫\n🟫🟫🟫🟫🟫🟫🟫\n 🟫🟫🟫🟫🟫🟫🏯"
)
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
		_check_warded,
		_check_taken,
	]
	for step: Callable in steps:
		var result: String = step.call()
		if not result.is_empty():
			return result
	return ""


## An instance has control points exactly when its region marks them, so ordinary instances have
## none and one made for a battle has its own.
func _check_ordinary_instances() -> String:
	for instance_name: String in InstanceBlueprints.names():
		var state: GameState = InstanceBlueprints.create(instance_name, SEED, 0)
		var marked: bool = not state.region.placed(ControlPointPlacements.KIND).is_empty()
		if (state.feature(ControlPointFeature.ID) != null) != marked:
			return "%s has control points without its region marking them, or the reverse" % (
				instance_name
			)
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


## A control point naming a side there is none of is refused, on a grid that reads with a known one.
func _check_unknown_side() -> String:
	var known: String = "- `🚩`: a control point, held by the attackers\n"
	if not FlowSteps.region("🔴🚩🟫", known).problem.is_empty():
		return "a control point held by the attackers wasn't read"
	var unknown: String = "- `🚩`: a control point, held by the wanderers\n"
	if FlowSteps.region("🔴🚩🟫", unknown).problem.is_empty():
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
	var wards: Array[int] = []
	var _sized: int = wards.resize(HELD.size())
	wards.fill(0)
	var short: Dictionary = { "holders": [ATTACKERS], "warded": wards, "loser": NOBODY }
	var bad: DataReader = DataReader.new(short)
	_points(_battle()).load_values(loaded, bad)
	if not bad.failed():
		return "a save with the wrong number of control points was read"
	return ""


## A ring with a gap around a point takes nothing, and no charge; placing a totem on a closed ring
## around the players' own point wards it, spending a charge, and a warded point takes no second
## totem. The totem's button agrees each time (#1503): faded where the totem takes nothing.
func _check_warded() -> String:
	var state: GameState = _ring_battle()
	var points: ControlPointFeature = _points(state)
	var own: int = _inner_point(state, ATTACKERS)
	var own_ring: Array[Vector2i] = _ring(points.points[own])
	var fort_ring: Array[Vector2i] = _ring(points.points[_inner_point(state, DEFENDERS)])
	_color(state, fort_ring.slice(0, 5), state.player(0))
	if FlowSteps.usable(TotemButton.new(), state, 0):
		return "the totem's button shows usable on a ring with a gap"
	if _taken(state, _totem(state, 0)) != -1 or _charges(state, 0) != PlaceholderTotems.CHARGES:
		return "a ring with a gap took a control point or spent a charge"
	_color(state, own_ring, state.player(1))
	if not FlowSteps.usable(TotemButton.new(), state, 1):
		return "the totem's button is faded on a ring around the players' own unwarded point"
	var warded: int = _taken(state, _totem(state, 1))
	if warded != own or not points.warded[own] or points.holders[own] != ATTACKERS:
		return "a totem on a ring around the players' own point didn't ward it"
	_color(state, own_ring, state.player(1))
	if FlowSteps.usable(TotemButton.new(), state, 1):
		return "the totem's button shows usable on a ring around a warded point"
	if _taken(state, _totem(state, 1)) != -1 or _charges(state, 1) != PlaceholderTotems.CHARGES - 1:
		return "a warded control point took a second totem"
	return ""


## A closed ring around the defenders' point takes it for the players' side and wards it, spending
## one charge; the ring comes off the trail, and the defenders, left without a point, lose. The
## totem's button shows usable on that ring (#1503).
func _check_taken() -> String:
	var state: GameState = _ring_battle()
	var points: ControlPointFeature = _points(state)
	var fort: int = _inner_point(state, DEFENDERS)
	var fort_ring: Array[Vector2i] = _ring(points.points[fort])
	# The defenders' point on the edge goes to the attackers, so the fort is the defenders' last.
	for index: int in points.holders.size():
		if index != fort and points.holders[index] == DEFENDERS:
			points.holders[index] = ATTACKERS
	_color(state, fort_ring, state.player(0))
	if not FlowSteps.usable(TotemButton.new(), state, 0):
		return "the totem's button is faded on a closed ring around the defenders' point"
	var events: Array[RefCounted] = _totem(state, 0)
	if _taken(
		state,
		events,
	) != fort or points.holders[fort] != ATTACKERS or not points.warded[fort]:
		return "a totem on a closed ring around the defenders' point didn't take and ward it"
	if not events.any(func(event: RefCounted) -> bool: return event is BattleLost):
		return "the defenders lost their last control point but not the battle"
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	for tile: Vector2i in fort_ring.slice(1):
		if trail.tiles.has(tile):
			return "the ring around a taken control point stayed on the trail"
	if _charges(state, 0) != PlaceholderTotems.CHARGES - 1:
		return "taking a control point didn't spend one charge"
	return ""


## A battle on RING_GRID with the playground's rules: player 1 on the ring around the defenders'
## inner point, player 2 on the one around the attackers' point.
func _ring_battle() -> GameState:
	var ground: Region = FlowSteps.region(RING_GRID, LEGEND)
	var state: GameState = FlowSteps.rules_on(FlowSteps.BASIC, ground, SEED)
	var points: ControlPointFeature = _points(state)
	var _taker: Entity = state.add_entity(
		0,
		_ring(points.points[_inner_point(state, DEFENDERS)])[0],
	)
	var _warder: Entity = state.add_entity(
		1,
		_ring(points.points[_inner_point(state, ATTACKERS)])[0],
	)
	return state


## The charges left on the totem of the player in `slot`.
static func _charges(state: GameState, slot: int) -> int:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	return domination.totems.charges_of(state.player(slot).id)


## The index of GRID's control point held by `side` away from the region's edge.
static func _inner_point(state: GameState, side: int) -> int:
	var points: ControlPointFeature = _points(state)
	for index: int in points.points.size():
		var inner: bool = not RingShape.on_edge(state.region, points.points[index])
		if points.holders[index] == side and inner:
			return index
	return -1


## The six tiles around `point`.
static func _ring(point: Vector2i) -> Array[Vector2i]:
	var ring: Array[Vector2i] = []
	for direction: Vector2i in Hex.DIRECTIONS:
		ring.append(point + direction)
	return ring


## Colors `tiles` into the trail as `player`'s.
static func _color(state: GameState, tiles: Array[Vector2i], player: Entity) -> void:
	var trail: Trail = (state.feature(TrailFeature.ID) as TrailFeature).shared
	for tile: Vector2i in tiles:
		var _colored: bool = trail.color(tile, player.id)


## The events of a tick the player in `slot` of two places their totem in.
static func _totem(state: GameState, slot: int) -> Array[RefCounted]:
	Simulation.step(state, FlowSteps.totem(slot, 2))
	return state.events.duplicate()


## The index of the control point a ControlPointTaken event in `events` says was taken, or -1.
static func _taken(state: GameState, events: Array[RefCounted]) -> int:
	for event: RefCounted in events:
		if event is ControlPointTaken:
			return _points(state).points.find((event as ControlPointTaken).point)
	return -1


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
