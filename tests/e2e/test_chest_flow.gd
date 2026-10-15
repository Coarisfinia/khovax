extends RefCounted
## Chest flow (#124): the glade's region pieces place treasure chests by hand, and they stay on
## their pieces however the seed arranges and turns them. A player who walks onto a chest opens it:
## it bursts into loot, every player in the run gets their own roll on the glade's loot table
## (owner, #124), and the chest is gone, so walking there again opens nothing. The same seed opens
## the same chest with the same loot. Instances without a loot table have no chests. This
## machine's player's own loot lands in their profile and its save; the others' doesn't (#74).
## The chests show (#135): one on every closed chest's tile, and an opened one bursts into this
## machine's player's own loot, each item named with its amount, and sinks away.

const SEED: int = 7
## Where the flow's profile is saved, apart from the player's own.
const SAVE_PATH: String = "user://test_chest_profile.json"
## Slot 0's loot from the chest the save step opens; slot 1 gets a berry.
const OWN_LOOT: Dictionary[String, int] = { "moss": 2 }

## The direction the last _open_first_chest walked in.
var _direction: int = 0


func run(tree: SceneTree) -> String:
	var result: String = _check_placed()
	if result.is_empty():
		result = _check_opened()
	if result.is_empty():
		if _first_loot() != _first_loot():
			result = "the same seed opened the chest with different loot"
	if result.is_empty() and InstanceBlueprints.basic(SEED).feature(Features.CHESTS) != null:
		result = "an instance without a loot table has chests"
	if result.is_empty():
		result = await _check_saved(tree)
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


## A chest opened in a run: the driver's ticked events bring this machine's player (slot 0) their
## own roll, into the profile and its save at once, and not slot 1's.
func _check_saved(tree: SceneTree) -> String:
	SaveStore.remove(SAVE_PATH)
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	var holder: ProfileHolder = main.get_node("ProfileHolder") as ProfileHolder
	holder.save_path = SAVE_PATH
	tree.root.add_child(main)
	await tree.process_frame
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	driver.set_process(false)
	driver.ticked.emit(driver.state.tick, _chest_opened())
	var saved: Profile = SaveStore.load_profile(SAVE_PATH)
	var result: String = ""
	if saved.materials != OWN_LOOT:
		result = "the profile saved %s from the chest, not %s" % [saved.materials, OWN_LOOT]
	if result.is_empty():
		result = _check_shown(main.get_node("ChestView") as ChestView, driver)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## The chest view (#135): in the glade, a chest on every closed chest's tile. An opened chest
## bursts into this machine's player's own loot only once a player sees it (never through the fog,
## never for an instance the view isn't showing), and sinks away; another instance clears it all.
func _check_shown(view: ChestView, driver: GameDriver) -> String:
	if not view.bursts.is_empty():
		return "a chest the view doesn't show burst into loot"
	driver.instance = InstanceBlueprints.GLADE
	driver.start(SEED)
	view.show_state()
	var chests: ChestFeature = driver.state.feature(Features.CHESTS) as ChestFeature
	var shown: Array[Vector2i] = view.figures.keys()
	if shown != chests.chests:
		return "the glade shows chests on %s, not on %s" % [shown, chests.chests]
	var chest: Vector2i = chests.chests[0]
	if not view.figures[chest].visible:
		driver.ticked.emit(driver.state.tick, _chest_opened(chest))
		if not view.bursts.is_empty():
			return "a chest in the fog burst into loot"
	_stand_next_to(driver, chest)
	view.show_state()
	driver.ticked.emit(driver.state.tick, _chest_opened(chest))
	var texts: Array[String] = []
	for burst: Label3D in view.bursts:
		texts.append(burst.text)
	var expected: Array[String] = ["+2 moss"]
	if texts != expected or ChestView.loot_text(OWN_LOOT) != expected[0]:
		return "the opened chest burst into %s, not this player's %s" % [texts, expected]
	chests.chests.erase(chest)
	view.show_state()
	if view.figures.has(chest):
		return "an opened chest stayed on %s" % chest
	return _check_cleared(view, driver)


## Another instance drops the glade's chests and loot at once, sinking or not.
func _check_cleared(view: ChestView, driver: GameDriver) -> String:
	driver.instance = InstanceBlueprints.BASIC
	driver.start(SEED)
	view.show_state()
	if not view.figures.is_empty() or not view.bursts.is_empty():
		return "another instance kept the glade's chests or loot"
	return ""


## Moves player 0 next to `chest` and runs a tick, so the fog lifts around it.
func _stand_next_to(driver: GameDriver, chest: Vector2i) -> void:
	for direction: Vector2i in Hex.DIRECTIONS:
		if driver.state.region.is_walkable(chest + direction):
			driver.state.player(0).tile = chest + direction
			break
	driver.advance(1.0 / Simulation.TICKS_PER_SECOND)


## A tick's events with the chest on `tile` opened: OWN_LOOT for slot 0, a berry for slot 1.
func _chest_opened(tile: Vector2i = Vector2i.ZERO) -> Array[RefCounted]:
	var other: Dictionary[String, int] = { "berry": 1 }
	var loot: Dictionary[int, Dictionary] = { 0: OWN_LOOT, 1: other }
	var events: Array[RefCounted] = [ChestOpened.new(tile, 1, loot)]
	return events
