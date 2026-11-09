class_name ControlPointFeature
extends Feature
## Control point battles (#580, #643): an instance made for one has control points its region
## pieces mark (ControlPointPlacements), each held by a side or by nobody. A side holds its points
## together, so in co-op every player of a side holds them alike (#74). A side holding no control
## point loses the battle: a BattleLost event, once. The attackers start with one (#580), which
## the region pieces mark.
##
## A point changes hands like a domination (#644, #423): a player closes a ring around it with the
## trail and places their totem on a tile of that ring, spending one of its charges. Their side
## holds the point from then on, and the totem wards it: one totem per point, so a point their side
## has warded takes no other, and the other side has to take it back the same way. Placing a totem
## on their side's own point that no totem wards yet wards it. The ring comes off the trail, as a
## domination's does. A ring with wild monsters inside is a domination's (DominationFeature, which
## steps earlier and places the totem first), never a control point's.
##
## Every point the players' side has warded strengthens their rings (#1492): it adds
## Tuning.WARDED_POINT_RING_POWER to the power of each ring they close
## (DominationFeature.strengthen).

## The feature's stable id (#784): saved and hashed, so never changed once it shipped.
const ID: String = "control_points"
## The side the players take control points for. They're the attackers, as in a conquest (#548);
## a battle naming the players' side, the defenders in a defense mission (#579), is #1493.
const PLAYERS_SIDE: int = ControlPointSides.ATTACKERS

## Every control point, in the region's tile order.
var points: Array[Vector2i] = []
## The side holding each control point (ControlPointSides), in the order of `points`.
var holders: Array[int] = []
## Whether a totem wards each control point (#644), in the order of `points`.
var warded: Array[bool] = []
## The side that lost the battle (ControlPointSides), or NOBODY while it goes on.
var loser: int = ControlPointSides.NOBODY


func id() -> String:
	return ID


## The trail its rings are drawn with, the wild monsters that make a ring a domination's, and the
## domination whose totems ward its points (#644), which an instance may lack: then no point
## changes hands (and without wild monsters, no ring holds one).
func after() -> Array[String]:
	var earlier: Array[String] = [TrailFeature.ID, WildMonsterFeature.ID, DominationFeature.ID]
	return earlier


func start(state: GameState) -> void:
	var placed: Dictionary[Vector2i, String] = state.region.placed(ControlPointPlacements.KIND)
	points.assign(placed.keys())
	points.sort()
	holders.clear()
	warded.clear()
	for point: Vector2i in points:
		holders.append(ControlPointPlacements.side_of(placed[point]))
		warded.append(false)


## Takes the control points players place their totems on, then ends the battle once a side holds
## no control point: that side lost.
func step(state: GameState, commands: Array[Command]) -> void:
	if loser != ControlPointSides.NOBODY:
		return
	_place_totems(state, commands)
	loser = _side_without_points()
	if loser != ControlPointSides.NOBODY:
		state.events.append(BattleLost.new(loser))


## The first fighting side that holds no control point, or NOBODY.
func _side_without_points() -> int:
	for side: int in ControlPointSides.FIGHTING:
		if not holders.has(side):
			return side
	return ControlPointSides.NOBODY


## Every player, in id order, whose command places their totem while they stand on the ring around
## a control point their side hasn't warded, and who has a charge left, spends it: their side holds
## that point and the totem wards it, and the ring comes off the trail. A taking that leaves a side
## without points decides the battle: no later player's totem counts that tick.
func _place_totems(state: GameState, commands: Array[Command]) -> void:
	var trail: TrailFeature = state.feature(TrailFeature.ID) as TrailFeature
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	if trail == null or domination == null:
		return
	for entity: Entity in state.entities:
		var command: Command = Command.of(commands, entity.slot)
		if command == null or command.totem != Command.PLACE_TOTEM:
			continue
		var index: int = _taken_by(state, entity)
		if index < 0 or not domination.spend_totem(entity.id):
			continue
		_take(state, index, entity.id, trail, domination.ring_walls(state))
		if _side_without_points() != ControlPointSides.NOBODY:
			return


## Whether the player `player_id` placing their totem now would take or ward a control point
## (#1503, the totem's button asks this too, as its own step does).
func can_place_totem(state: GameState, player_id: int) -> bool:
	var player: Entity = state.entity(player_id)
	return player != null and loser == ControlPointSides.NOBODY and _taken_by(state, player) >= 0


## The control point the totem of `player` would take or ward, or -1: they have a charge left and
## stand on the ring around a point their side hasn't warded, on no wall a domination's ring needs.
func _taken_by(state: GameState, player: Entity) -> int:
	var trail: TrailFeature = state.feature(TrailFeature.ID) as TrailFeature
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	if trail == null or domination == null or domination.totems.charges_of(player.id) == 0:
		return -1
	if domination.ring_walls(state).has(player.tile):
		return -1
	return _ringed_under(state, trail.shared, player.tile)


## The player `player_id`'s totem takes the control point at `index` for the players' side and
## wards it, and its ring comes off the trail, but not the wall tiles a domination's ring still
## `needed`.
func _take(
	state: GameState,
	index: int,
	player_id: int,
	trail: TrailFeature,
	needed: Dictionary[Vector2i, bool],
) -> void:
	holders[index] = PLAYERS_SIDE
	warded[index] = true
	_strengthen(state)
	state.events.append(ControlPointTaken.new(points[index], PLAYERS_SIDE, player_id))
	var cleared: Array[Vector2i] = []
	for wall: Vector2i in _ring_around(state, trail.shared, points[index]):
		if not needed.has(wall):
			cleared.append(wall)
	trail.clear(state, cleared)


## Tells the domination the ring power the points the players' side has warded add to their rings.
func _strengthen(state: GameState) -> void:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	if domination == null:
		return
	var ours: int = 0
	for index: int in points.size():
		if warded[index] and holders[index] == PLAYERS_SIDE:
			ours += 1
	domination.strengthen(ours * Tuning.WARDED_POINT_RING_POWER)


## The first control point, in the order of `points`, that the players' side hasn't warded and
## whose ring has a tile on `tile`, or -1. A ring with a wild monster inside is a domination's
## (#423), even one DominationFeature didn't take up because its dominator has a ring already.
func _ringed_under(state: GameState, trail: Trail, tile: Vector2i) -> int:
	if not trail.tiles.has(tile):
		return -1
	var edge: Array[Vector2i] = RingShape.edge_of(state.region)
	var reachable: Dictionary[Vector2i, bool] = RingShape.outside(state.region, trail, edge)
	for index: int in points.size():
		var point: Vector2i = points[index]
		var ours: bool = warded[index] and holders[index] == PLAYERS_SIDE
		if ours or trail.tiles.has(point) or reachable.has(point):
			continue
		if _ring_around(
			state,
			trail,
			point,
		).has(tile) and not _holds_wild_monster(state, trail, point):
			return index
	return -1


## Whether a wild monster stands in the pocket the trail encloses around `point`.
static func _holds_wild_monster(state: GameState, trail: Trail, point: Vector2i) -> bool:
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null:
		return false
	var spots: Array[Vector2i] = [point]
	var pocket: Dictionary[Vector2i, bool] = RingShape.enclosed_with(state.region, trail, spots)
	for monster_id: int in wild.monsters:
		if pocket.has(state.entity(monster_id).tile):
			return true
	return false


## The ring around the enclosed control point on `point`: the trail tiles next to what it encloses.
static func _ring_around(state: GameState, trail: Trail, point: Vector2i) -> Array[Vector2i]:
	var spots: Array[Vector2i] = [point]
	return RingShape.wall_around(state.region, trail, spots)


func hash_values() -> Array[int]:
	var values: Array[int] = [points.size()]
	for index: int in points.size():
		var ward: int = 1 if warded[index] else 0
		values.append_array([points[index].x, points[index].y, holders[index], ward])
	values.append(loser)
	return values


## Who holds each point and whether a totem wards it, in the order of `points`, and who lost; the
## points follow from the region.
func save_values() -> Dictionary:
	var wards: Array[int] = []
	for ward: bool in warded:
		wards.append(1 if ward else 0)
	return { "holders": holders.duplicate(), "warded": wards, "loser": loser }


func load_values(state: GameState, values: DataReader) -> void:
	var nobody: int = ControlPointSides.NOBODY
	var held: Array[int] = values.wholes("holders", nobody, ControlPointSides.DEFENDERS)
	var wards: Array[int] = values.wholes("warded", 0, 1)
	if held.size() != points.size() or wards.size() != points.size():
		values.fail("the saved control points aren't the region's")
		return
	var lost: int = values.whole("loser", nobody, ControlPointSides.DEFENDERS)
	if values.failed():
		return
	holders = held
	warded.clear()
	for ward: int in wards:
		warded.append(ward == 1)
	loser = lost
	_strengthen(state)
