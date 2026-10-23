extends RefCounted
## Chest flow (#124): the glade's region pieces place treasure chests by hand, and they stay on
## their pieces however the seed arranges and turns them. A player who walks onto a chest opens it:
## it bursts into loot, every player in the instance gets their own roll on the glade's chest table
## (owner, #124), and the chest is gone, so walking there again opens nothing. The same seed opens
## the same chest with the same loot. Instances without a chest table have no chests. This
## machine's player's own loot lands in their profile and its save; the others' doesn't (#74).
## The chests show (#135): one on every closed chest's tile, and an opened one bursts into this
## machine's player's own loot, each item named with its amount, and sinks away. Loot on the
## ground (#203) works the same, without a chest: the glade's pieces place it, the first player to
## step on it finds it, every player rolls their own, it's gone after, it reaches this machine's
## player's profile, and it shows as a gem that bursts the same way. Chests hold crafting supplies
## and basic gear (#694), a piece for every slot, while the loot on the ground holds no gear; gear
## from a chest lands in the profile's gear, not its materials.

const SEED: int = 7
## Where the flow's profile is saved, apart from the player's own.
const SAVE_PATH: String = "user://test_chest_profile.json"
## Slot 0's loot from the chest the save step opens; slot 1 gets a berry.
const OWN_LOOT: Dictionary[String, int] = { "moss": 2 }
## Slot 0's loot from the loot on the ground the save step finds.
const FOUND_LOOT: Dictionary[String, int] = { "berry": 3 }
## Slot 0's gear from another chest the save step opens.
const OWN_GEAR: Dictionary[String, int] = { "warding_charm": 1 }

## The direction the last _open_first_chest walked in.
var _direction: int = 0


func run(tree: SceneTree) -> String:
	var result: String = _check_placed()
	if result.is_empty():
		result = _check_tables()
	if result.is_empty():
		result = _check_opened()
	if result.is_empty():
		result = _check_found()
	if result.is_empty() and _first_found() != _first_found():
		result = "the same seed found the loot with different rolls"
	if result.is_empty():
		if _first_loot() != _first_loot():
			result = "the same seed opened the chest with different loot"
	if result.is_empty() and FlowSteps.basic(SEED).feature(ChestFeature.ID) != null:
		result = "an instance without a chest table has chests"
	if result.is_empty():
		result = await _check_saved(tree)
	return result


## Every chest the pieces mark is in the region, on ground, for every seed.
func _check_placed() -> String:
	for seed_value: int in 12:
		var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, seed_value, 1)
		var chests: ChestFeature = state.feature(ChestFeature.ID) as ChestFeature
		if chests == null or chests.chests.is_empty():
			return "seed %d's glade has no chests" % seed_value
		for chest: Vector2i in chests.chests:
			if not state.region.is_walkable(chest):
				return "seed %d put a chest on %s, which isn't ground" % [seed_value, chest]
		for spot: Vector2i in chests.loot_spots:
			if not state.region.is_walkable(spot) or chests.chests.has(spot):
				return "seed %d put loot on %s, which isn't free ground" % [seed_value, spot]
		if chests.loot_spots.is_empty():
			return "seed %d's glade has no loot on the ground" % seed_value
	return ""


## The glade's chests hold crafting supplies and a loose piece of gear for every slot (#694); the
## loot on its ground holds no gear.
func _check_tables() -> String:
	var chests: ChestFeature = InstanceBlueprints.create(FlowSteps.GLADE, SEED, 1).feature(
		ChestFeature.ID,
	) as ChestFeature
	var gear: GearContent = GearContent.load_gear()
	var slots: Array[String] = []
	for item: String in chests.table.items:
		var piece: GearItem = gear.items.get(item)
		if piece != null and piece.rarity == GearItem.RARITIES[0] and not slots.has(piece.slot):
			slots.append(piece.slot)
	if slots.size() != GearSlots.SLOTS.size() or not chests.table.items.has("moss"):
		return "the glade's chests hold basic gear for %s and %s" % [slots, chests.table.items]
	for item: String in chests.ground_table.items:
		if gear.items.has(item):
			return "the glade's loot on the ground holds the gear %s" % item
	return ""


## Two players: the first walks onto a chest and opens it, and both get their roll.
func _check_opened() -> String:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, SEED, 2)
	var chests: ChestFeature = state.feature(ChestFeature.ID) as ChestFeature
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


## Two players: the first steps onto the loot on the ground and finds it, both get their roll,
## no chest opens, and it's gone after.
func _check_found() -> String:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, SEED, 2)
	var chests: ChestFeature = state.feature(ChestFeature.ID) as ChestFeature
	var lying: int = chests.loot_spots.size()
	var events: Array[RefCounted] = _step_onto(state, chests.loot_spots[0])
	var found: LootFound = null if events.size() != 1 else events[0] as LootFound
	if found == null or chests.loot_spots.size() != lying - 1:
		return "stepping onto the loot didn't find it, or opened a chest: %s" % [events]
	var both: bool = found.loot.size() == 2 and found.loot.has(0) and found.loot.has(1)
	if found.finder_id != state.player(0).id or not both:
		return "the loot didn't go to both players: %s" % found.loot
	var back: int = posmod(_direction + 3, Hex.DIRECTIONS.size())
	if not _walk(state, back).is_empty() or not _walk(state, _direction).is_empty():
		return "the loot was found twice"
	return _check_found_kept(state)


## The loot still lying and the rolls to come are saved and restored: a glade loaded from the save
## lies the same and rolls on the same stream.
func _check_found_kept(state: GameState) -> String:
	var chests: ChestFeature = state.feature(ChestFeature.ID) as ChestFeature
	var fresh: GameState = InstanceBlueprints.create(FlowSteps.GLADE, SEED, 2)
	var restored: ChestFeature = fresh.feature(ChestFeature.ID) as ChestFeature
	var values: DataReader = DataReader.new(chests.save_values())
	restored.load_values(fresh, values)
	if values.failed() or restored.hash_values() != chests.hash_values():
		return "the loot still lying didn't survive a save: %s" % values.problem
	return ""


## Puts player 0 next to the first chest and walks them onto it; returns the ChestOpened event, or
## null.
func _open_first_chest(state: GameState) -> ChestOpened:
	var chest: Vector2i = (state.feature(ChestFeature.ID) as ChestFeature).chests[0]
	var events: Array[RefCounted] = _step_onto(state, chest)
	return null if events.is_empty() else events[0] as ChestOpened


## Puts player 0 on a free tile next to `tile` and walks them onto it; returns the chests opened and
## loot found on the way.
func _step_onto(state: GameState, tile: Vector2i) -> Array[RefCounted]:
	for direction: int in Hex.DIRECTIONS.size():
		var from: Vector2i = tile - Hex.DIRECTIONS[direction]
		if state.region.is_walkable(from) and _free(state, from):
			state.player(0).tile = from
			_direction = direction
			return _walk(state, direction)
	var none: Array[RefCounted] = []
	return none


## Whether no entity stands on `tile`.
func _free(state: GameState, tile: Vector2i) -> bool:
	for entity: Entity in state.entities:
		if entity.tile == tile:
			return false
	return true


## Walks player 0 one whole step in `direction`; returns the chests opened and loot found on the
## way.
func _walk(state: GameState, direction: int) -> Array[RefCounted]:
	var opened: Array[RefCounted] = []
	for event: RefCounted in FlowSteps.step(state, direction, 2):
		if event is ChestOpened or event is LootFound:
			opened.append(event)
	return opened


## The rolls of the first loot found on the ground in a fresh two-player glade from SEED, as text.
func _first_found() -> String:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, SEED, 2)
	var spot: Vector2i = (state.feature(ChestFeature.ID) as ChestFeature).loot_spots[0]
	var events: Array[RefCounted] = _step_onto(state, spot)
	return "none" if events.is_empty() else str((events[0] as LootFound).loot)


## The loot of the first chest opened in a fresh two-player glade from SEED, as text.
func _first_loot() -> String:
	var opened: ChestOpened = _open_first_chest(InstanceBlueprints.create(FlowSteps.GLADE, SEED, 2))
	return "none" if opened == null else str(opened.loot)


## A chest opened and loot found in a session: the driver's ticked events bring this machine's
## player (slot 0) their own rolls, into the profile and its save at once, and not slot 1's.
func _check_saved(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start_held(tree, SAVE_PATH)
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	driver.ticked.emit(driver.state.tick, _chest_opened())
	var gear_loot: Dictionary[int, Dictionary] = { 0: OWN_GEAR }
	var gear_chest: Array[RefCounted] = [ChestOpened.new(Vector2i.ZERO, 1, gear_loot)]
	driver.ticked.emit(driver.state.tick, gear_chest)
	driver.ticked.emit(driver.state.tick, _loot_found())
	(main.get_node("EventBus") as EventBus).flush()
	# The chest's gain is saved at once; the loot's, coming right after, waits for the debounce.
	var _flushed: String = holder.keeper.flush()
	var saved: Profile = ProfileStore.load_from(SAVE_PATH)
	var result: String = ""
	var expected: Dictionary[String, int] = OWN_LOOT.merged(FOUND_LOOT)
	if saved.materials != expected:
		result = "the profile saved %s from the chest and the loot, not %s" % [
			saved.materials,
			expected,
		]
	if result.is_empty() and saved.gear.owned != OWN_GEAR:
		result = "the profile saved the gear %s from the chest, not %s" % [
			saved.gear.owned,
			OWN_GEAR,
		]
	if result.is_empty():
		result = _check_shown(main.get_node("Instance/ChestView") as ChestView, driver)
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
	driver.instance = FlowSteps.GLADE
	driver.start(SEED)
	view.show_state()
	var chests: ChestFeature = driver.state.feature(ChestFeature.ID) as ChestFeature
	var shown: Array[Vector2i] = view.figures.keys()
	var gem: MeshInstance3D = null
	if not chests.loot_spots.is_empty() and view.figures.has(chests.loot_spots[0]):
		gem = view.figures[chests.loot_spots[0]].get_child(0) as MeshInstance3D
	if shown != chests.chests + chests.loot_spots or gem == null or not gem.mesh is SphereMesh:
		return "the glade shows chests and loot on %s, not on %s and %s as gems" % [
			shown,
			chests.chests,
			chests.loot_spots,
		]
	var chest: Vector2i = chests.chests[0]
	if not view.figures[chest].visible:
		FlowSteps.raise(driver, _chest_opened(chest))
		if not view.bursts.is_empty():
			return "a chest in the fog burst into loot"
	_stand_next_to(driver, chest)
	view.show_state()
	FlowSteps.raise(driver, _chest_opened(chest))
	var texts: Array[String] = []
	for burst: Label3D in view.bursts:
		texts.append(burst.text)
	var expected: Array[String] = ["+2 Moss"]
	if texts != expected or ChestView.loot_text(OWN_LOOT) != expected[0]:
		return "the opened chest burst into %s, not this player's %s" % [texts, expected]
	# Gear shows by its name from the gear data, materials by their id in words (#773).
	var named: String = ChestView.loot_text({ "warding_charm": 1, "moss": 2 })
	if named != "+2 Moss\n+1 Warding charm":
		return "loot of gear and a material burst into %s, not their names" % named.c_escape()
	chests.chests.erase(chest)
	view.show_state()
	if view.figures.has(chest):
		return "an opened chest stayed on %s" % chest
	return _check_found_shown(view, driver)


## Loot on the ground, found where a player sees it, bursts into this machine's player's own loot
## too, and its gem goes.
func _check_found_shown(view: ChestView, driver: GameDriver) -> String:
	var chests: ChestFeature = driver.state.feature(ChestFeature.ID) as ChestFeature
	var spot: Vector2i = chests.loot_spots[0]
	_stand_next_to(driver, spot)
	view.show_state()
	var bursts: int = view.bursts.size()
	FlowSteps.raise(driver, _loot_found(spot))
	var text: String = ChestView.loot_text(FOUND_LOOT)
	if view.bursts.size() != bursts + 1 or view.bursts[-1].text != text:
		return "the found loot didn't burst into this player's %s" % FOUND_LOOT
	chests.loot_spots.erase(spot)
	view.show_state()
	if view.figures.has(spot):
		return "found loot stayed on %s" % spot
	return _check_cleared(view, driver)


## Another instance drops the glade's chests and loot at once, sinking or not.
func _check_cleared(view: ChestView, driver: GameDriver) -> String:
	driver.instance = FlowSteps.BASIC
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


## A tick's events with the loot on `tile` found: FOUND_LOOT for slot 0, moss for slot 1.
func _loot_found(tile: Vector2i = Vector2i.ZERO) -> Array[RefCounted]:
	var other: Dictionary[String, int] = { "moss": 1 }
	var loot: Dictionary[int, Dictionary] = { 0: FOUND_LOOT, 1: other }
	var events: Array[RefCounted] = [LootFound.new(tile, 1, loot)]
	return events


## A tick's events with the chest on `tile` opened: OWN_LOOT for slot 0, a berry for slot 1.
func _chest_opened(tile: Vector2i = Vector2i.ZERO) -> Array[RefCounted]:
	var other: Dictionary[String, int] = { "berry": 1 }
	var loot: Dictionary[int, Dictionary] = { 0: OWN_LOOT, 1: other }
	var events: Array[RefCounted] = [ChestOpened.new(tile, 1, loot)]
	return events
