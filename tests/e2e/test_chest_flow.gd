extends RefCounted
## Chest flow (#124): the glade's region pieces place treasure chests by hand, and they stay on
## their pieces however the seed arranges and turns them. A player who walks onto a chest opens it:
## it bursts into loot, every player in the run gets their own roll on the glade's loot table
## (owner, #124), and the chest is gone, so walking there again opens nothing. The same seed opens
## the same chest with the same loot. Instances without a loot table have no chests.

const SEED: int = 7

## The direction the last _open_first_chest walked in.
var _direction: int = 0


func run(_tree: SceneTree) -> String:
	var result: String = _check_placed()
	if result.is_empty():
		result = _check_opened()
	if result.is_empty():
		if _first_loot() != _first_loot():
			result = "the same seed opened the chest with different loot"
	if result.is_empty() and InstanceBlueprints.basic(SEED).feature(Features.CHESTS) != null:
		result = "an instance without a loot table has chests"
	return result


## Every chest the pieces mark is in the region, on ground, for every seed.
func _check_placed() -> String:
	for seed_value: int in 12:
		var state: GameState = InstanceBlueprints.create("glade", seed_value, 1)
		var chests: ChestFeature = state.feature(Features.CHESTS) as ChestFeature
		if chests == null or chests.chests.is_empty():
			return "seed %d's glade has no chests" % seed_value
		for chest: Vector2i in chests.chests:
			if not state.region.is_walkable(chest):
				return "seed %d put a chest on %s, which isn't ground" % [seed_value, chest]
	return ""


## Two players: the first walks onto a chest and opens it, and both get their roll.
func _check_opened() -> String:
	var state: GameState = InstanceBlueprints.create("glade", SEED, 2)
	var chests: ChestFeature = state.feature(Features.CHESTS) as ChestFeature
	var closed: int = chests.chests.size()
	var opened: ChestOpened = _open_first_chest(state)
	if opened == null or chests.chests.size() != closed - 1:
		return "walking onto the chest didn't open it"
	var both: bool = opened.loot.size() == 2 and opened.loot.has(0) and opened.loot.has(1)
	if opened.opener_id != state.player(0).id or not both:
		return "the chest's loot didn't go to both players: %s" % opened.loot
	for slot: int in opened.loot:
		var loot: Dictionary = opened.loot[slot]
		if loot.size() != 1 or not chests.table.items.has(str(loot.keys()[0])):
			return "player %d's loot isn't a roll on the glade's table: %s" % [slot, loot]
	# Off the chest's tile and back on: it's gone, so nothing opens.
	var back: int = posmod(_direction + 3, Hex.DIRECTIONS.size())
	if not _walk(state, back).is_empty() or not _walk(state, _direction).is_empty():
		return "a chest opened twice"
	return ""


## Puts player 0 next to the first chest and walks them onto it; returns the ChestOpened event, or
## null.
func _open_first_chest(state: GameState) -> ChestOpened:
	var chest: Vector2i = (state.feature(Features.CHESTS) as ChestFeature).chests[0]
	for direction: int in Hex.DIRECTIONS.size():
		var from: Vector2i = chest - Hex.DIRECTIONS[direction]
		if state.region.is_walkable(from) and _free(state, from):
			state.player(0).tile = from
			_direction = direction
			var events: Array[ChestOpened] = _walk(state, direction)
			return null if events.is_empty() else events[0]
	return null


## Whether no entity stands on `tile`.
func _free(state: GameState, tile: Vector2i) -> bool:
	for entity: Entity in state.entities:
		if entity.tile == tile:
			return false
	return true


## Walks player 0 one whole step in `direction`; returns the chests opened on the way.
func _walk(state: GameState, direction: int) -> Array[ChestOpened]:
	var opened: Array[ChestOpened] = []
	for tick: int in MovementFeature.MOVE_TICKS:
		var move: int = direction if tick == 0 else Command.NO_MOVE
		Simulation.step(state, _commands(move))
		for event: RefCounted in state.events:
			if event is ChestOpened:
				opened.append(event as ChestOpened)
	return opened


## Player 0's command `move`, and player 1 standing still.
func _commands(move: int) -> Array[Command]:
	var commands: Array[Command] = [Command.new(move), Command.new(Command.NO_MOVE)]
	return commands


## The loot of the first chest opened in a fresh two-player glade from SEED, as text.
func _first_loot() -> String:
	var opened: ChestOpened = _open_first_chest(InstanceBlueprints.create("glade", SEED, 2))
	return "none" if opened == null else str(opened.loot)
