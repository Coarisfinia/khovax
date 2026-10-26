extends RefCounted
## Starting quests flow (#1320): the quests of the starting instance, every quest whose steps all
## count there, can all be finished on every difficulty the host can choose (#1315), by a player
## who does only what the quests point at. Until a tutorial line exists, these stand in for it
## (owner, #1320). The player plays a fresh world alone, without companions, follows the quest
## their quest list follows (QuestTracker.focused) to the tile it's marked at (QuestTargets), and
## walks onto it; a domination step marked over a wild monster no ring can enclose where it stands
## (RingableGround) rings the nearest one of its species that can be, as a player would. They ring a
## monster by
## walking once round it and placing their totem, and the quests count what the world raises.

## The world's seed: the same world every run, so the check is deterministic.
const WORLD_SEED: int = 0
## How long the player gets to finish them all, in ticks.
const MOST_TICKS: int = 4 * Tuning.TICKS_PER_HOUR
## How long a closed ring gets to seal and dominate, in ticks.
const SEAL_TICKS: int = 20 * Simulation.TICKS_PER_SECOND

var _world: World
var _start: String = ""
var _quests: QuestTracker
var _dominated: int = 0


func run(_tree: SceneTree) -> String:
	for difficulty: int in HostSettings.DIFFICULTIES:
		var problem: String = _play(difficulty)
		if not problem.is_empty():
			return "at difficulty %d: %s" % [difficulty, problem]
	return ""


## Plays a fresh world at `difficulty` until every starting quest is finished; "" once they are, or
## which aren't when the player runs out of time or has nothing left to go to.
func _play(difficulty: int) -> String:
	_start = Realms.start()
	_world = World.new(BlueprintSource.new(), WORLD_SEED, _start, 1)
	if not _world.problem.is_empty():
		return _world.problem
	_quests = QuestTracker.new()
	_quests.book = QuestKeeper.book_of(QuestContent.cached())
	_dominated = 0
	var asking: Command = Command.new()
	var data: int = HostSettings.request_data(HostSettings.DIFFICULTY, difficulty)
	Outbox.new().post(OutboxEntry.HOST_SETTING, data).fill(asking)
	_tick([asking])
	if HostSettings.difficulty(_state()) != difficulty:
		return "the host's request for the difficulty wasn't taken"
	var starting: Array[String] = _starting()
	if starting.is_empty():
		return "the starting instance %s has no quest of its own" % _start
	while _world.tick < MOST_TICKS and not _left(starting).is_empty():
		var targets: Dictionary[String, Vector2i] = QuestTargets.of(_state(), _quests, 0, _start)
		var before: int = _world.tick
		if targets.is_empty() or not _follow(targets) or _world.tick == before:
			break
	var left: Array[String] = _left(starting)
	if left.is_empty():
		return ""
	return "%s still open after %d ticks" % [", ".join(left), _world.tick]


## The ids of the quests whose steps, choices included, all count in the starting instance.
func _starting() -> Array[String]:
	var ids: Array[String] = []
	for id: String in _quests.book:
		var here: bool = true
		for step: QuestStep in _quests.book[id].steps:
			var ways: Array[QuestStep] = [step]
			if not step.choices.is_empty():
				ways = step.choices
			for way: QuestStep in ways:
				here = here and way.instance == _start
		if here:
			ids.append(id)
	ids.sort()
	return ids


## Which of `ids` aren't finished.
func _left(ids: Array[String]) -> Array[String]:
	var left: Array[String] = []
	for id: String in ids:
		if not _quests.finished.has(id):
			left.append(id)
	return left


## Goes after the target of the followed quest, else the first one in `targets`: rings a marked
## wild monster, or walks onto the tile. Whether the player got there.
func _follow(targets: Dictionary[String, Vector2i]) -> bool:
	var followed: String = _quests.focused()
	var key: String = targets.keys()[0]
	for id: String in targets:
		if id == followed or id.begins_with(followed + "/"):
			key = id
			break
	var tile: Vector2i = targets[key]
	var monster: int = _monster_at(tile)
	if monster < 0:
		return _walk_to(tile)
	monster = monster if _ringable(tile) else _nearest_ringable(_wild().species_of(monster))
	return monster >= 0 and _dominate(monster)


## The wild monster standing on `tile`, or -1.
func _monster_at(tile: Vector2i) -> int:
	for monster: int in _wild().monsters:
		if _state().entity(monster).tile == tile:
			return monster
	return -1


## Whether a player can close a ring of one round `center`: every tile next to it walkable.
func _ringable(center: Vector2i) -> bool:
	for tile: Vector2i in Hex.ring(1, center):
		if not FlowSteps.walkable_for_players(_state(), tile):
			return false
	return true


## The wild monster of `species` nearest the player a ring of one can close round, or -1: the
## marked one's species, which its step asks for.
func _nearest_ringable(species: String) -> int:
	var nearest: int = -1
	var gap: int = 0
	var from: Vector2i = _state().player(0).tile
	for monster: int in _wild().monsters:
		var tile: Vector2i = _state().entity(monster).tile
		var near: bool = nearest < 0 or Hex.distance(tile, from) < gap
		if _wild().species_of(monster) == species and _ringable(tile) and near:
			nearest = monster
			gap = Hex.distance(tile, from)
	return nearest


## Walks once round `monster`, from the ring tile nearest the player, and places the totem until the
## ring dominates or comes to nothing. Whether it dominated.
func _dominate(monster: int) -> bool:
	var center: Vector2i = _state().entity(monster).tile
	var ring: Array[Vector2i] = Hex.ring(1, center)
	var first: int = 0
	var from: Vector2i = _state().player(0).tile
	for at: int in ring.size():
		if Hex.distance(ring[at], from) < Hex.distance(ring[first], from):
			first = at
	for step: int in ring.size() + 1:
		var moved: bool = _state().entity(monster).tile == center
		if not moved or not _walk_to(ring[(first + step) % ring.size()]):
			return false
	var before: int = _dominated
	for _waited: int in SEAL_TICKS:
		_tick(FlowSteps.totem())
		if _dominated > before:
			return true
	return false


## Walks the player to `goal` by a shortest way. Whether they stand there. It steps the whole
## World, so the instance's and the world's events reach the quests, where FlowSteps.walk steps one
## instance's state alone.
func _walk_to(goal: Vector2i) -> bool:
	var from: Vector2i = _state().player(0).tile
	for direction: int in FlowSteps.shortest_path(_state(), from, goal):
		for at: int in MovementFeature.MOVE_TICKS:
			_tick(FlowSteps.command(direction if at == 0 else Command.NO_MOVE))
	return _state().player(0).tile == goal


## Steps the world one tick with `commands` and counts what it raised on the player's quests.
func _tick(commands: Array[Command]) -> void:
	_world.step(commands)
	var events: Array[RefCounted] = []
	events.append_array(_state().events)
	events.append_array(_world.events)
	for event: RefCounted in events:
		_dominated += 1 if event is WildMonsterDominated else 0
		for fact: QuestFact in QuestFacts.of(event, 0, _start):
			var _done: Array[QuestDefinition] = _quests.advance(fact)


func _state() -> GameState:
	return _world.instance(_start)


func _wild() -> WildMonsterFeature:
	return _state().feature(WildMonsterFeature.ID) as WildMonsterFeature
