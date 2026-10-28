extends RefCounted
## Tile harvest flow (#696): a player standing next to gems in the mana forest presses the interact
## action; after a few ticks the gems drop their crystals, every player in the instance getting
## their own roll on the gems' tile table (#74), and turn into bare rock, which the instance keeps
## in its changed tiles until it's purged (#212). Walking off in between stops the harvest, and
## without the press nothing happens. A harvest going on survives a save. Every tile kind that can
## be harvested names a tile table and a depleted kind that exist, and an instance without such
## tiles has no harvesting. In a session, this machine's player's crystals burst from the tile and
## land in their profile; another player's don't. On a touch screen the interact button (#1488)
## shows only while a press would begin a harvest, and the Controls tab shows a tap for it.

const SEED: int = 7
## The mana forest, ringed by gems (#1218).
const FOREST: String = "ivenwhal_wudhen"
const GEMS: String = "gems"
## Where the flow's profile is saved, apart from the player's own.
const SAVE_PATH: String = "user://test_tile_harvest_profile.json"
## This machine's player's crystals from the gems the session step harvests.
const OWN_LOOT: Dictionary[String, int] = { "crystal": 2 }


func run(tree: SceneTree) -> String:
	var result: String = _check_content()
	if result.is_empty():
		result = _check_features()
	if result.is_empty():
		result = _check_harvested()
	if result.is_empty():
		result = _check_stopped()
	if result.is_empty():
		result = _check_kept()
	if result.is_empty():
		result = _check_button_shows()
	if result.is_empty() and _first_loot() != _first_loot():
		result = "the same seed harvested the gems with different rolls"
	if result.is_empty():
		result = await _check_taken(tree)
	return result


## Every kind that can be harvested yields a tile table that loads, and becomes a kind that exists
## and can't be harvested by hand again; every tile table is one a kind yields. Gems can be
## harvested by hand.
func _check_content() -> String:
	var yielded: Array[String] = []
	for kind: String in TileContent.load_tiles().tiles:
		var yields: String = TileKinds.harvest_yields(kind)
		if yields.is_empty():
			continue
		yielded.append(yields)
		if LootContent.table_for(yields, LootTable.TILE) == null:
			return "%s yields %s, which isn't a tile table" % [kind, yields]
		var depleted: String = TileKinds.harvested_into(kind)
		if not TileKinds.has(depleted) or TileKinds.harvested_by_hand(depleted):
			return "%s becomes %s, which isn't a kind that stays harvested" % [kind, depleted]
	for table: LootTable in LootContent.load_loot_tables().loot_tables.values():
		if table.kind == LootTable.TILE and not yielded.has(table.id):
			return "no tile kind yields the tile table %s" % table.id
	if not TileKinds.harvested_by_hand(GEMS):
		return "gems can't be harvested by hand"
	return ""


## The mana forest's gems bring harvesting; the playground, without such tiles, has none.
func _check_features() -> String:
	if InstanceBlueprints.create(FOREST, SEED, 1).feature(TileHarvestFeature.ID) == null:
		return "the mana forest's gems can't be harvested"
	if FlowSteps.basic(SEED).feature(TileHarvestFeature.ID) != null:
		return "an instance without harvestable tiles has harvesting"
	return ""


## Two players: the first presses interact next to gems. They stay gems until the ticks are up,
## then turn into bare rock, kept as a changed tile, and both players get their crystals.
func _check_harvested() -> String:
	var state: GameState = _beside_gems()
	if state == null:
		return "no free tile beside the mana forest's gems"
	var tile: Vector2i = TileHarvestFeature.target_of(state, state.player(0))
	var events: Array[RefCounted] = _press(state)
	for _tick: int in TileHarvestFeature.HARVEST_TICKS - 1:
		events.append_array(_stand(state))
	if state.region.terrain[tile] != GEMS or not _harvested(events).is_empty():
		return "the gems were harvested before their ticks were up"
	events = _stand(state)
	var harvested: Array[TileHarvested] = _harvested(events)
	if harvested.size() != 1 or harvested[0].tile != tile or harvested[0].kind != GEMS:
		return "the gems weren't harvested once their ticks were up: %s" % [events]
	if state.region.terrain[tile] != "bare_rock" or not state.changed_tiles.has(tile):
		return "the harvested gems didn't turn into bare rock the instance keeps"
	var loot: Dictionary[int, Dictionary] = harvested[0].loot
	if harvested[0].harvester_id != state.player(0).id or loot.keys() != [0, 1]:
		return "the gems' crystals didn't go to both players: %s" % loot
	for slot: int in loot:
		var amount: int = loot[slot].get("crystal", 0)
		if loot[slot].size() != 1 or amount < 1 or amount > 2:
			return "player %d's loot isn't a roll on the gems' table: %s" % [slot, loot[slot]]
	if LootRolls.of(harvested[0]) != loot:
		return "the harvested gems' loot doesn't reach the profiles and quests"
	return ""


## Walking off before the ticks are up stops the harvest, and without the press nothing is
## harvested.
func _check_stopped() -> String:
	var state: GameState = _beside_gems()
	var tile: Vector2i = TileHarvestFeature.target_of(state, state.player(0))
	var events: Array[RefCounted] = _press(state)
	var off: int = _free_direction(state)
	if off == Command.NO_MOVE:
		return "the player has nowhere to walk off to"
	events.append_array(FlowSteps.step(state, off, 2))
	for _tick: int in TileHarvestFeature.HARVEST_TICKS:
		events.append_array(_stand(state))
	if state.region.terrain[tile] != GEMS or not _harvested(events).is_empty():
		return "walking off didn't stop the harvest"
	state = _beside_gems()
	events.clear()
	for _tick: int in TileHarvestFeature.HARVEST_TICKS + 1:
		events.append_array(_stand(state))
	if not _harvested(events).is_empty():
		return "gems were harvested without the press"
	return ""


## A harvest going on is saved and restored: a forest loaded from the save goes on with it alike.
func _check_kept() -> String:
	var state: GameState = _beside_gems()
	var _events: Array[RefCounted] = _press(state)
	var harvest: TileHarvestFeature = state.feature(TileHarvestFeature.ID) as TileHarvestFeature
	if not harvest.targets.has(0):
		return "the press began no harvest"
	var fresh: GameState = _beside_gems()
	var restored: TileHarvestFeature = fresh.feature(TileHarvestFeature.ID) as TileHarvestFeature
	var values: DataReader = DataReader.new(harvest.save_values())
	restored.load_values(fresh, values)
	if values.failed() or restored.hash_values() != harvest.hash_values():
		return "the harvest going on didn't survive a save: %s" % values.problem
	return ""


## A session: the driver's ticked events bring this machine's player (slot 0) their own crystals,
## bursting from the tile and into the profile at once; another player's don't burst or land.
func _check_taken(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start_held(tree, SAVE_PATH)
	var result: String = _check_burst(main)
	if result.is_empty():
		result = _check_button(main)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## In the session `main`, gems harvested in sight: another player's crystals alone show and give
## nothing; this player's burst and land in their profile.
func _check_burst(main: Node) -> String:
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	var view: HarvestView = main.get_node("Instance/HarvestView") as HarvestView
	var tile: Vector2i = FlowSteps.sight_of(driver.state)[0]
	var player: int = driver.state.player(0).id
	var had: int = holder.keeper.profile.materials.get("crystal", 0)
	var others: Dictionary[int, Dictionary] = { 1: OWN_LOOT }
	var harvested: Array[RefCounted] = [TileHarvested.new(player, tile, GEMS, others)]
	FlowSteps.raise(driver, harvested)
	if not view.bursts.is_empty():
		return "another player's crystals burst for this one"
	var mine: Dictionary[int, Dictionary] = { 0: OWN_LOOT, 1: { "crystal": 1 } }
	harvested = [TileHarvested.new(player, tile, GEMS, mine)]
	FlowSteps.raise(driver, harvested)
	(main.get_node("EventBus") as EventBus).flush()
	if view.bursts.size() != 1 or view.bursts[0].text != ChestView.loot_text(OWN_LOOT):
		return "the harvested tile's crystals didn't burst into this player's own"
	var gained: int = holder.keeper.profile.materials.get("crystal", 0) - had
	if gained != OWN_LOOT["crystal"]:
		return "the profile took %d crystals from the harvested tile, not %s" % [gained, OWN_LOOT]
	return ""


## The interact button shows for a player beside gems, and not once they're knocked down, nor in
## an instance without harvesting.
func _check_button_shows() -> String:
	var state: GameState = _beside_gems()
	if not InteractButton.shows_in(state, 0):
		return "the interact button didn't show beside the gems"
	var knockdown: KnockdownFeature = state.feature(KnockdownFeature.ID) as KnockdownFeature
	if knockdown == null:
		return "the mana forest has no knocking down to check the interact button with"
	knockdown.knock_down(state.player(0).id)
	if InteractButton.shows_in(state, 0):
		return "the interact button showed for a knocked-down player"
	if InteractButton.shows_in(FlowSteps.basic(SEED), 0):
		return "the interact button showed in an instance without harvesting"
	return ""


## In the session `main`, in an instance without harvesting, the interact button stays hidden on a
## touch screen, presses interact, and the Controls tab shows a tap for harvesting.
func _check_button(main: Node) -> String:
	var button: InteractButton = main.get_node("Hud/InteractButton") as InteractButton
	button.touch = true
	button.lay_out_in(button.get_viewport_rect().size)
	button.touch = false
	if button.visible or button.button.action != &"interact" or button.icon == null:
		return "the interact button showed with nothing to harvest, or presses another action"
	var tap: Array[Texture2D] = [InputGlyphs.pointing(DeviceInUse.Device.TOUCH)]
	if ControlsTab.glyphs_of([&"interact"], DeviceInUse.Device.TOUCH) != tap:
		return "the Controls tab didn't show a tap for harvesting by hand"
	return ""


## A two-player mana forest from SEED with player 0 on a free tile beside gems, on which nothing can
## be harvested, or null when there's none.
func _beside_gems() -> GameState:
	var state: GameState = InstanceBlueprints.create(FOREST, SEED, 2)
	for tile: Vector2i in state.region.terrain:
		if state.region.terrain[tile] != GEMS:
			continue
		for direction: Vector2i in Hex.DIRECTIONS:
			var beside: Vector2i = tile + direction
			if FlowSteps.walkable_for_players(state, beside):
				state.player(0).tile = beside
				return state
	return null


## A direction player 0 can walk off in, or Command.NO_MOVE.
func _free_direction(state: GameState) -> int:
	for direction: int in Hex.DIRECTIONS.size():
		var tile: Vector2i = state.player(0).tile + Hex.DIRECTIONS[direction]
		if FlowSteps.walkable_for_players(state, tile):
			return direction
	return Command.NO_MOVE


## One tick with player 0 pressing interact and player 1 standing; returns its events.
func _press(state: GameState) -> Array[RefCounted]:
	var commands: Array[Command] = FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE])
	commands[0].interact = true
	Simulation.step(state, commands)
	return state.events.duplicate()


## One tick with both players standing; returns its events.
func _stand(state: GameState) -> Array[RefCounted]:
	Simulation.step(state, FlowSteps.commands([Command.NO_MOVE, Command.NO_MOVE]))
	return state.events.duplicate()


## The tiles harvested in `events`.
func _harvested(events: Array[RefCounted]) -> Array[TileHarvested]:
	var harvested: Array[TileHarvested] = []
	for event: RefCounted in events:
		if event is TileHarvested:
			harvested.append(event as TileHarvested)
	return harvested


## The loot of the gems harvested first in a fresh two-player mana forest from SEED, as text.
func _first_loot() -> String:
	var state: GameState = _beside_gems()
	var events: Array[RefCounted] = _press(state)
	for _tick: int in TileHarvestFeature.HARVEST_TICKS:
		events.append_array(_stand(state))
	var harvested: Array[TileHarvested] = _harvested(events)
	return "none" if harvested.is_empty() else str(harvested[0].loot)
