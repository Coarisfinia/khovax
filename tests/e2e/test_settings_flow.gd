extends RefCounted
## Settings flow (#161): every graphics setting starts at Auto, which picks the project's value for
## this platform and says so in its label; a player's choice takes effect at once and survives a
## restart; and choosing Auto again hands the setting back. Anti-aliasing is the first: MSAA and the
## ink pass's smoothing together. In the game, the menu's Settings tab (#355, #362) does all that:
## the `menu` action opens the menu, easing in; while it's open the player's keys don't walk and,
## by default, single player pauses (#302): no tick runs. The tab lists every setting, each on Auto
## at first; a step changes one and keeps it, its Auto button hands it back; turning the pause off
## lets the ticks run on behind the menu; turning the damage numbers off hides them and a text size
## sizes them (#764); the rows fit a phone's screen; and the close button at its
## top right, the cancel action (a controller's B) and the menu action each close the menu, easing
## out, and the game goes on. Its Character tab (#391) shows the player's personal
## color (#233), on Auto at first: a color picked on its wheel colors their circle at once and is
## kept in their profile, and its Auto button hands the world's default back. It lists the player's
## dominated monsters (#400): none at first, then each by its species' name and level, the three
## they carry first, in order, the first their companion, each marked in words. Its gear slots
## (#690) change with a press outside a fight and are kept in the profile, and stay put during one.

const SETTINGS_PATH: String = "user://test_settings.json"
const PROFILE_PATH: String = "user://test_settings_profile.json"
## A color the player picks on the Character tab's wheel, as the profile keeps it.
const PICKED: int = 0x3366cc
const STEP: float = 1.0 / Simulation.TICKS_PER_SECOND

var _tree: SceneTree


func run(tree: SceneTree) -> String:
	_tree = tree
	_forget()
	var msaa_before: Viewport.MSAA = tree.root.msaa_3d
	var result: String = _check_auto()
	if result.is_empty():
		result = _check_choice_kept()
	if result.is_empty():
		result = _check_back_to_auto()
	if result.is_empty():
		result = _check_fraction_dropped()
	if result.is_empty():
		result = await _check_menu()
	tree.root.msaa_3d = msaa_before
	_forget()
	return result


## A new player's anti-aliasing is Auto: the project's MSAA for this platform, on screen and in the
## label, with the ink smoothed unless MSAA is off.
func _check_auto() -> String:
	var graphics: Graphics = _start()
	var auto: int = ProjectSettings.get_setting_with_override(Graphics.MSAA_SETTING)
	var label: String = graphics.anti_aliasing_label()
	var problem: String = _check_applied(graphics, auto)
	graphics.free()
	if not problem.is_empty():
		return "Auto: " + problem
	if not label.begins_with("Auto (") or _label_of(auto) not in label:
		return "Auto's label is %s" % label
	return ""


## Turning anti-aliasing off takes effect at once, drops the "Auto" from the label and survives a
## restart.
func _check_choice_kept() -> String:
	var graphics: Graphics = _start()
	var problem: String = graphics.choose_anti_aliasing(Viewport.MSAA_DISABLED)
	if problem.is_empty():
		problem = _check_applied(graphics, Viewport.MSAA_DISABLED)
	var label: String = graphics.anti_aliasing_label()
	graphics.free()
	if not problem.is_empty():
		return "choosing off: " + problem
	if label != "Off":
		return "the chosen setting's label is %s" % label
	var restarted: Graphics = _start()
	problem = _check_applied(restarted, Viewport.MSAA_DISABLED)
	restarted.free()
	if not problem.is_empty():
		return "after a restart: " + problem
	return ""


## Choosing Auto again hands the setting back, also after a restart.
func _check_back_to_auto() -> String:
	var graphics: Graphics = _start()
	var problem: String = graphics.choose_auto(Graphics.ANTI_ALIASING)
	if problem.is_empty():
		problem = _check_applied(graphics, Graphics.auto_anti_aliasing())
	graphics.free()
	if not problem.is_empty():
		return "choosing Auto again: " + problem
	var restarted: Graphics = _start()
	problem = _check_applied(restarted, Graphics.auto_anti_aliasing())
	var label: String = restarted.anti_aliasing_label()
	restarted.free()
	if not problem.is_empty() or not label.begins_with("Auto ("):
		return "Auto again, after a restart: %s (%s)" % [problem, label]
	return ""


## A hand-edited settings file whose value isn't a whole number drops that setting back to Auto
## and keeps the others (#631).
func _check_fraction_dropped() -> String:
	var text: String = JSON.stringify({ Graphics.ANTI_ALIASING: 0.5, GameMenu.PAUSE_SETTING: 0 })
	var problem: String = SaveStore.write_save(SETTINGS_PATH, text)
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	SaveStore.remove(SETTINGS_PATH)
	if (not problem.is_empty() or kept.chosen.size() != 1
			or kept.chosen.get(GameMenu.PAUSE_SETTING) != 0):
		return "a fractional setting isn't dropped: %s %s" % [problem, kept.chosen]
	return ""


## The settings menu in the game, its settings kept in the test's file.
func _check_menu() -> String:
	_forget()
	var main: Node = await FlowGame.start(_tree, PROFILE_PATH)
	var graphics: Graphics = main.get_node("Graphics") as Graphics
	graphics.settings_path = SETTINGS_PATH
	graphics.settings = Settings.new()
	graphics.apply()
	var menu: GameMenu = main.get_node("Hud/GameMenu") as GameMenu
	var driver: GameDriver = FlowGame.driver(main)
	var result: String = await _open_menu(menu)
	if result.is_empty():
		result = _menu_character(menu, main)
	if result.is_empty():
		result = _menu_monsters(menu, main)
	if result.is_empty():
		result = await _menu_holds_game(driver, true)
	if result.is_empty():
		result = _menu_choices(menu, graphics, main.get_node("SurveyChoice") as SurveyChoice)
	if result.is_empty():
		result = await _menu_pause_choice(menu, driver)
	if result.is_empty():
		result = _menu_on_screens(menu)
	if result.is_empty():
		result = await _close_menu(menu)
	if result.is_empty():
		result = await _menu_holds_game(driver, false)
	main.queue_free()
	await _tree.process_frame
	return result


## The `menu` action opens the menu, easing in, and its Settings tab lists every setting, each on
## Auto.
func _open_menu(menu: GameMenu) -> String:
	if menu.is_open() or menu.opacity() > 0.0:
		return "the menu shows before it's opened"
	_press(menu, &"menu")
	if not menu.is_open() or menu.opacity() >= 1.0:
		return "the menu action doesn't open the menu, or it snaps open"
	await _tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	if menu.opacity() < 1.0:
		return "the menu doesn't finish easing in"
	var shown: Dictionary[String, String] = menu.settings.shown
	# Laid out in its scene (#437): it scrolls only up and down.
	if menu.settings.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return "the Settings tab's scene scrolls sideways"
	var listed: Array[String] = []
	for setting: String in shown:
		listed.append(setting)
	var settings: Array[String] = [
		Graphics.ANTI_ALIASING,
		SurveyChoice.PLACE_SETTING,
		SurveyChoice.ZOOM_SETTING,
		DamageNumbersChoice.SHOWN_SETTING,
		DamageNumbersChoice.SIZE_SETTING,
		GameMenu.PAUSE_SETTING,
	]
	if listed != settings:
		return "the Settings tab lists %s, not every setting" % [listed]
	for setting: String in listed:
		if not shown[setting].begins_with("Auto ("):
			return "%s isn't on Auto at first: %s" % [setting, shown[setting]]
	return ""


## The Character tab starts on Auto, the world's default color for this player; a color picked on
## its wheel colors their circle at once and is in their profile on disk, and Auto hands the
## default back.
func _menu_character(menu: GameMenu, main: Node) -> String:
	var tab: CharacterTab = menu.character
	var driver: GameDriver = FlowGame.driver(main)
	var holder: ProfileHolder = FlowGame.holder(main)
	var player: PlayerView = main.get_node("Instance/Player") as PlayerView
	var default: Color = PersonalColor.of(driver.world.world_seed, driver.input.slot)
	# Laid out in its scene (#437): it scrolls only up and down, and its wheel is a wheel.
	if (tab.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
			or tab.picker.picker_shape != ColorPicker.SHAPE_HSV_WHEEL):
		return "the Character tab's scene scrolls sideways or has no color wheel"
	if tab.shown != CharacterTab.AUTO_TEXT or not tab.picker.color.is_equal_approx(default):
		return "the Character tab doesn't start on Auto's color: %s" % tab.shown
	var picked: Color = PersonalColor.of_number(PICKED)
	tab.picker.color_changed.emit(picked)
	player.show_state()
	# Saved debounced like a gain (#391): a tick before the menu paused the game may have saved the
	# start instance's entry (#730), so the pick waits; flushing saves it, as quitting would.
	var _flushed: String = holder.keeper.flush()
	var kept: Profile = ProfileStore.load_from(PROFILE_PATH)
	if (tab.shown != CharacterTab.CHOSEN_TEXT
			or not player.circle.color.is_equal_approx(picked)
			or kept.personal_color != PICKED):
		return "a picked color isn't shown on the circle or kept: %s, %s, %x" % [
			tab.shown,
			player.circle.color,
			kept.personal_color,
		]
	tab.auto_button.pressed.emit()
	player.show_state()
	if (tab.shown != CharacterTab.AUTO_TEXT
			or holder.personal_color() != Profile.AUTO_COLOR
			or not tab.picker.color.is_equal_approx(default)
			or not player.circle.color.is_equal_approx(default)):
		return "the Character tab's Auto doesn't hand the world's color back"
	return ""


## The Character tab lists no monsters for a new player; once they dominate four, it lists the three
## they carry first, in the order dominated, the first their companion, then the fourth.
func _menu_monsters(menu: GameMenu, main: Node) -> String:
	var tab: CharacterTab = menu.character
	var none: Array[String] = [DominatedMonstersList.NONE_TEXT]
	if tab.monsters.shown != none:
		return "the Character tab lists monsters before any is dominated: %s" % [tab.monsters.shown]
	var gain: Gain = Gain.new()
	gain.dominated_species.assign(["ombulumo", "tikazzir", "tikazzir", "ombulumo"])
	var problem: String = FlowGame.holder(main).keeper.take(gain, Time.get_ticks_msec())
	if not problem.is_empty():
		return "the dominations aren't taken: " + problem
	tab.refresh()
	var listed: Array[String] = [
		"Carried 1, companion: Ombulumo, level 1",
		"Carried 2: Tikazzir, level 1",
		"Carried 3: Tikazzir, level 1",
		"Not carried: Ombulumo, level 1",
	]
	if tab.monsters.shown != listed:
		return "the Character tab lists %s, not the dominated monsters" % [tab.monsters.shown]
	# The materials (#295): none at first, then each with its count, in id order.
	# Might (#509): the number and its one part yet, the carried monsters'.
	var profile: Profile = FlowGame.holder(main).keeper.profile
	var species: Dictionary[String, Species] = SpeciesContent.load_species().species
	var part: int = Might.monsters_part(profile, species)
	tab.might.refresh()
	if part <= 0 or tab.might.shown != [
		MightPanel.TOTAL_TEXT % part,
		MightPanel.MONSTERS_TEXT % part,
	]:
		return "the Character tab's Might is %s, not the carried monsters' %d" % [
			tab.might.shown,
			part,
		]
	tab.materials.refresh()
	if tab.materials.shown != ([MaterialsList.NONE_TEXT] as Array[String]):
		return "the Character tab lists materials before any is found: %s" % [tab.materials.shown]
	var found: Gain = Gain.new()
	found.materials.assign({ "moss": 3, "berry": 1 })
	var _taken: String = FlowGame.holder(main).keeper.take(found, Time.get_ticks_msec())
	tab.materials.refresh()
	if tab.materials.shown != (["Berry: 1", "Moss: 3"] as Array[String]):
		return "the Character tab's materials are %s, not the ones found" % [tab.materials.shown]
	return _menu_factions(tab, main)


## The standings with the factions (#533): none listed while the player is neutral with all; then
## each one they aren't neutral with, in id order, with its name, signed standing and rank name, or
## by its id in words once the content no longer has it; neutral again, it leaves the list.
func _menu_factions(tab: CharacterTab, main: Node) -> String:
	var panel: FactionStandingsPanel = tab.factions
	var neutral: Array[String] = [FactionStandingsPanel.NONE_TEXT]
	panel.refresh()
	if panel.shown != neutral:
		return "the Character tab lists factions while neutral with all: %s" % [panel.shown]
	var content: FactionContent = FactionContent.load_factions()
	var ids: Array[String] = []
	ids.assign(content.factions.keys())
	ids.sort()
	if ids.is_empty():
		return "no faction to stand with: " + content.problem
	var faction: Faction = content.factions[ids[0]]
	var standings: Standings = FlowGame.holder(main).keeper.profile.standings
	var changed: String = standings.change(faction.id, 2) + standings.change("zz_vanished", -1)
	panel.refresh()
	var listed: Array[String] = [
		"%s: +2, %s" % [faction.name, faction.rank_name(2)],
		"Zz Vanished: -1",
	]
	if not changed.is_empty() or panel.shown != listed:
		return "the Character tab's factions are %s, not %s" % [panel.shown, listed]
	changed = standings.change(faction.id, -2) + standings.change("zz_vanished", 1)
	panel.refresh()
	if not changed.is_empty() or panel.shown != neutral:
		return "a faction back at neutral stays listed: %s" % [panel.shown]
	return _menu_gear(tab, main)


## The gear slots (#690), each a button with its slot's icon that a controller can focus, empty at
## first. Pressing one puts the player's next piece of gear for it in, in id order, and empties it
## after the last; a slot without gear for it stays empty. The gear is kept in their profile on
## disk. No wild monster is near, so no fight stops it.
func _menu_gear(tab: CharacterTab, main: Node) -> String:
	var state: GameState = FlowGame.driver(main).state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var nearby: Array[int] = wild.monsters.duplicate()
	wild.monsters.clear()
	var result: String = _gear_starts_empty(tab.gear)
	if result.is_empty():
		result = _gear_changes(tab.gear, main)
	if result.is_empty():
		result = _menu_gear_fight(tab.gear, main, nearby)
	wild.monsters.assign(nearby)
	return result if not result.is_empty() else _menu_reorder(tab, main)


## Every gear slot starts empty and free to change, its button showing its slot's icon and taking
## a controller's focus.
func _gear_starts_empty(panel: GearPanel) -> String:
	panel.refresh()
	var empty: Array[String] = []
	for slot: String in GearSlots.SLOTS:
		empty.append(GearPanel.SLOT_TEXT % [slot.capitalize(), GearPanel.EMPTY_TEXT])
		var button: Button = panel.buttons[slot]
		if button.icon != GearPanel.ICONS[slot] or button.focus_mode != Control.FOCUS_ALL:
			return "the %s slot's button lacks its icon or a controller's focus" % slot
	empty.append(GearPanel.FREE_TEXT)
	if panel.shown != empty:
		return "the gear slots don't start empty and free to change: %s" % [panel.shown]
	return ""


## Pressing the slots puts the player's gear in, and the gear is kept in their profile on disk; the
## spikes in the trap slot (#692) post one request to the outbox in the same save (#818), which the
## next tick carries into the world's store of the player's trap.
func _gear_changes(panel: GearPanel, main: Node) -> String:
	var keeper: ProfileKeeper = FlowGame.holder(main).keeper
	keeper.profile.gear.owned.assign({ "warding_charm": 1, "thorn_spikes": 1 })
	# Ward on, trap on, throw has nothing for it; ward off and on again.
	for slot: String in ["ward", "trap", "throw", "ward", "ward"]:
		panel.buttons[slot].pressed.emit()
	var _flushed: String = keeper.flush()
	var kept: Profile = ProfileStore.load_from(PROFILE_PATH)
	var expected: Dictionary[String, String] = { "ward": "warding_charm", "trap": "thorn_spikes" }
	var lines: Array[String] = [
		"Ward: Warding charm (Loose)",
		"Trap: Thorn spikes (Loose)",
		"Throw: empty",
		GearPanel.FREE_TEXT,
	]
	if panel.shown != lines or kept.gear.equipped != expected:
		return "pressing the slots put in %s, kept %s" % [panel.shown, kept.gear.equipped]
	var code: int = SpikesFeature.code_of("thorn_spikes")
	var traps: Array[int] = []
	for request: OutboxEntry in kept.outbox.entries:
		if request.kind == OutboxEntry.TRAP:
			traps.append(request.data)
	if traps != [code]:
		return "changing the gear posted the trap requests %s, not one for the spikes" % [traps]
	var driver: GameDriver = FlowGame.driver(main)
	driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	var entry: Dictionary = driver.world.stored(driver.input.slot, SpikesFeature.ID)
	var stored: int = SpikesFeature.trap_of(entry)
	if stored != code:
		return "the spikes in the trap slot didn't reach the world's store: %d" % stored
	return ""


## During a fight, a wild monster beside the player, the slots' buttons still show their gear but
## don't change it, and a line says why; the player's ring sealing a wild monster in, and a wild
## monster enraged anywhere in the instance, are fights too.
func _menu_gear_fight(panel: GearPanel, main: Node, nearby: Array[int]) -> String:
	var state: GameState = FlowGame.driver(main).state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	var hiding: HidingFeature = state.feature(HidingFeature.ID) as HidingFeature
	var fighter: Entity = null
	for monster_id: int in nearby:
		if fighter == null and (hiding == null or not hiding.is_hidden(monster_id)):
			fighter = state.entity(monster_id)
	if fighter == null:
		return "no wild monster in sight to fight"
	var tile: Vector2i = fighter.tile
	fighter.tile = state.player(FlowGame.driver(main).input.slot).tile
	wild.monsters.assign([fighter.id])
	var expected: Array[String] = panel.shown.slice(0, GearSlots.SLOTS.size())
	expected.append(GearPanel.FIGHT_TEXT)
	panel.buttons["ward"].pressed.emit()
	panel.refresh()
	var locked: bool = panel.buttons["ward"].disabled
	fighter.tile = tile
	if not locked or panel.shown != expected:
		return "during a fight, the gear changed or no line says why: %s" % [panel.shown]
	var sealing: String = _gear_locked_by_seal(panel, state, fighter.id)
	if not sealing.is_empty():
		return sealing
	# Back where it stood but enraged (owner, 1+3 on #690): still a fight, wherever it is.
	wild.enrage(state, fighter.id, 0)
	panel.refresh()
	if not panel.buttons["ward"].disabled:
		return "an enraged wild monster in the instance isn't a fight"
	return ""


## While the player's ring seals the wild monster `monster_id` in (owner, 1+3 on #690), wherever it
## stands, the gear stays put; the seal is taken off again afterwards.
func _gear_locked_by_seal(panel: GearPanel, state: GameState, monster_id: int) -> String:
	var domination: DominationFeature = state.feature(DominationFeature.ID) as DominationFeature
	if domination == null:
		return "the instance has no rings to seal a wild monster in"
	var player_id: int = state.player(panel.driver.input.slot).id
	var seal: RingSeal = RingSeal.new()
	seal.monsters.assign([monster_id])
	domination.seals[player_id] = seal
	panel.refresh()
	var locked: bool = panel.buttons["ward"].disabled
	var _unsealed: bool = domination.seals.erase(player_id)
	panel.refresh()
	if not locked:
		return "the player's ring sealing a wild monster in isn't a fight"
	return ""


## The player orders their monsters (#430): moving the one not carried to the front makes it the
## companion and pushes the third out of the carried three; its row's up button then moves the new
## second one up again. The order is kept in their profile on disk.
func _menu_reorder(tab: CharacterTab, main: Node) -> String:
	var ids: Array[int] = tab.monsters.shown_ids.duplicate()
	tab.monsters.move(ids[3], 0)
	var moved: Array[String] = [
		"Carried 1, companion: Ombulumo, level 1",
		"Carried 2: Ombulumo, level 1",
		"Carried 3: Tikazzir, level 1",
		"Not carried: Tikazzir, level 1",
	]
	var reordered: Array[int] = [ids[3], ids[0], ids[1], ids[2]]
	if tab.monsters.shown != moved or tab.monsters.shown_ids != reordered:
		return "moving a monster first didn't make it the companion: %s" % [tab.monsters.shown]
	# The second row's up button: its line, then up, then down.
	var second: HBoxContainer = tab.monsters.get_child(1).get_child(1) as HBoxContainer
	(second.get_child(1) as Button).pressed.emit()
	var keeper: ProfileKeeper = FlowGame.holder(main).keeper
	var _flushed: String = keeper.flush()
	var kept: Profile = ProfileStore.load_from(PROFILE_PATH)
	var expected: Array[int] = [ids[0], ids[3], ids[1]]
	if tab.monsters.shown_ids[0] != ids[0] or kept.carried != expected:
		return "a row's up button didn't move it, or the order isn't kept: %s" % [kept.carried]
	return _menu_details(tab)


## Each type shows after its family's badge (#627): breeze in the last family, mana in the first.
## Every family has its own icon, so the badges never tell families apart by color alone (#68).
func _type_badges(details: MonsterDetails) -> String:
	var families: Array[int] = []
	for row: Node in details.find_children("*", "HBoxContainer", true, false):
		for part: Node in row.get_children():
			if part is TypeBadge:
				families.append((part as TypeBadge).family)
	var wanted: Array[int] = [4, 0]
	if families != wanted:
		return "the types don't show their families' badges: %s" % [families]
	var icons: Dictionary[Texture2D, bool] = {}
	for icon: Texture2D in TypeBadge.ICONS:
		icons[icon] = true
	if icons.size() != TypeChart.FAMILIES.size() or TypeBadge.COLORS.size() != icons.size():
		return "not every family has its own icon and a color"
	return ""


## The detail pane (#430) shows the first monster until another is selected, then that one's
## stats; it sits beside the list on a landscape screen and below it on a portrait one.
func _menu_details(tab: CharacterTab) -> String:
	var details: MonsterDetails = tab.monsters.details
	var first: int = tab.monsters.shown_ids[0]
	if tab.monsters.selected != first or not details.shown[0].begins_with("Ombulumo, level 1"):
		return "the detail pane doesn't start on the first monster: %s" % [details.shown]
	# A click on the third row, as the mouse gives it.
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var third: Label = tab.monsters.get_child(1).get_child(2).get_child(0) as Label
	third.gui_input.emit(click)
	var expected: Array[String] = [
		"Tikazzir, level 1",
		"Types: breeze, mana",
		"HP: 60",
		"Strength: 70",
		"Speed: 90",
		"Special: Tizik-tazak (Supremacy)",
		"Passive for you: Kirzi-tirzi (Harmony and supremacy)",
		"Own passive: Zirki-kirki",
		"Sight: you see 2 steps further while you carry it",
	]
	if details.shown != expected:
		return "clicking a monster didn't show its stats: %s" % [details.shown]
	var menu: GameMenu = tab.get_parent().get_parent().get_parent().get_parent() as GameMenu
	menu.lay_out(Vector2(360.0, 640.0))
	var stacked: bool = (details.get_parent() as BoxContainer).vertical
	menu.lay_out(Vector2(1920.0, 1080.0))
	if not stacked or (details.get_parent() as BoxContainer).vertical:
		return "the detail pane isn't below the list upright and beside it on a landscape screen"
	# Beside each other, both share the row; the trimmed rows would otherwise shrink to nothing.
	var both: int = tab.monsters.size_flags_horizontal & details.size_flags_horizontal
	if both & Control.SIZE_EXPAND == 0:
		return "the monsters and their detail pane don't share the row"
	var column: Control = details.get_parent().get_parent() as Control
	var paired: float = column.custom_minimum_size.x
	menu.lay_out(Vector2(360.0, 640.0))
	if paired <= column.custom_minimum_size.x:
		return "the column doesn't widen for the detail pane beside the monsters"
	return _type_badges(details)


## While the menu is open (`open`), the player's keys don't walk and no tick runs; once it's
## closed, both go on.
func _menu_holds_game(driver: GameDriver, open: bool) -> String:
	Input.action_press("move_right")
	var walks: bool = driver.input.command(driver.state).move != Command.NO_MOVE
	Input.action_release("move_right")
	var ticked: bool = await _ticks_run(driver)
	if walks == open or ticked == open:
		return "with the menu %s, the keys %s walk and the ticks %s run" % [
			"open" if open else "closed",
			"do" if walks else "don't",
			"do" if ticked else "don't",
		]
	return ""


## Stepping anti-aliasing on and the Survey's place back takes effect and keeps them;
## anti-aliasing's Auto button hands it back.
func _menu_choices(menu: GameMenu, graphics: Graphics, survey: SurveyChoice) -> String:
	var tab: SettingsTab = menu.settings
	var choices: Array[int] = Graphics.ANTI_ALIASING_CHOICES
	var next: int = choices[posmod(choices.find(Graphics.auto_anti_aliasing()) + 1, choices.size())]
	tab.button(Graphics.ANTI_ALIASING, "Next").pressed.emit()
	var problem: String = _check_applied(graphics, next)
	if problem.is_empty() and tab.shown[Graphics.ANTI_ALIASING] != _label_of(next):
		problem = "the menu shows anti-aliasing as %s" % tab.shown[Graphics.ANTI_ALIASING]
	var place: int = posmod(SurveyChoice.AUTO_PLACE - 1, SurveyChoice.Place.size())
	tab.button(SurveyChoice.PLACE_SETTING, "Previous").pressed.emit()
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	if problem.is_empty() and (survey.place_shown() != place
			or kept.chosen.get(SurveyChoice.PLACE_SETTING) != place
			or kept.chosen.get(Graphics.ANTI_ALIASING) != next):
		problem = "the menu's choices aren't followed or kept: %s" % [kept.chosen]
	tab.button(Graphics.ANTI_ALIASING, "Auto").pressed.emit()
	if problem.is_empty():
		problem = _check_applied(graphics, Graphics.auto_anti_aliasing())
	kept = Settings.load_from(SETTINGS_PATH)
	if problem.is_empty() and (kept.chosen.has(Graphics.ANTI_ALIASING)
			or not tab.shown[Graphics.ANTI_ALIASING].begins_with("Auto (")):
		problem = "the menu's Auto doesn't hand anti-aliasing back: %s" % [kept.chosen]
	return problem if not problem.is_empty() else _menu_damage_numbers(menu)


## Turning the pause off lets the ticks run on behind the open menu, and keeps that; its Auto
## button pauses the game again.
func _menu_pause_choice(menu: GameMenu, driver: GameDriver) -> String:
	var tab: SettingsTab = menu.settings
	tab.button(GameMenu.PAUSE_SETTING, "Next").pressed.emit()
	if not await _ticks_run(driver) or tab.shown[GameMenu.PAUSE_SETTING] != "Off":
		return "with the pause off, the open menu still holds the ticks"
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	if kept.chosen.get(GameMenu.PAUSE_SETTING) != 0:
		return "the pause choice isn't kept: %s" % [kept.chosen]
	tab.button(GameMenu.PAUSE_SETTING, "Auto").pressed.emit()
	if await _ticks_run(driver) or not menu.pauses():
		return "the pause's Auto doesn't pause the game again"
	return ""


## Turning the damage numbers off (#764) keeps an auto attack's number from showing and a special's
## to its fainting's words, and is kept; a larger text size makes them larger and is kept; Auto
## hands both back: shown, at their usual size.
func _menu_damage_numbers(menu: GameMenu) -> String:
	var tab: SettingsTab = menu.settings
	var view: Node = menu.owner.get_node("Instance/DamageNumbersView")
	var numbers: DamageNumbersView = view as DamageNumbersView
	var felled: SpecialStruck = SpecialStruck.new(0, 0, 7, true)
	tab.button(DamageNumbersChoice.SHOWN_SETTING, "Next").pressed.emit()
	numbers.show_auto(Vector2i.ZERO, 3, [])
	numbers.show_strike(Vector2i.ZERO, felled)
	var kept: Settings = Settings.load_from(SETTINGS_PATH)
	if (tab.shown[DamageNumbersChoice.SHOWN_SETTING] != "Off"
			or kept.chosen.get(DamageNumbersChoice.SHOWN_SETTING) != 0
			or numbers.strikes.size() != 1
			or numbers.strikes[0].text != DamageNumbersView.FAINTED_TEXT):
		return "turned off, the damage numbers show %s, kept as %s" % [
			numbers.strikes.map(func(label: Label3D) -> String: return label.text),
			kept.chosen,
		]
	tab.button(DamageNumbersChoice.SHOWN_SETTING, "Auto").pressed.emit()
	tab.button(DamageNumbersChoice.SIZE_SETTING, "Next").pressed.emit()
	numbers.show_auto(Vector2i.ZERO, 3, [])
	var size: float = RisingText.PIXEL_SIZE * DamageNumbersView.AUTO_SHARE * 1.25
	kept = Settings.load_from(SETTINGS_PATH)
	if (tab.shown[DamageNumbersChoice.SHOWN_SETTING] != "Auto (On)"
			or tab.shown[DamageNumbersChoice.SIZE_SETTING] != "125%"
			or kept.chosen.get(DamageNumbersChoice.SIZE_SETTING) != 3
			or not is_equal_approx(numbers.strikes[-1].pixel_size, size)):
		return "a larger damage number size isn't followed or kept: %s" % [kept.chosen]
	tab.button(DamageNumbersChoice.SIZE_SETTING, "Auto").pressed.emit()
	var sized: String = tab.shown[DamageNumbersChoice.SIZE_SETTING]
	return "" if sized == "Auto (100%)" else "the damage number size's Auto shows %s" % sized


## The settings' rows fit a phone held either way and a desktop screen.
func _menu_on_screens(menu: GameMenu) -> String:
	for screen: Vector2 in [Vector2(360.0, 640.0), Vector2(640.0, 360.0), Vector2(1920.0, 1080.0)]:
		menu.lay_out(screen)
		var width: float = menu.settings.rows_width()
		if width <= 0.0 or width > screen.x - 2.0 * GameMenu.MARGIN:
			return "the settings' rows are %d pixels wide on a %s screen" % [width, screen]
	return _menu_credits(menu)


## The Credits tab (#462) shows every pack CREDITS.md credits, each heading in bold, with its
## fields' names in bold and no Markdown marks or repository paths left over.
func _menu_credits(menu: GameMenu) -> String:
	var tab: CreditsTab = menu.find_child("Credits", true, false) as CreditsTab
	# Laid out in its scene (#437): BBCode on, and focusable so a controller scrolls it.
	if not tab.bbcode_enabled or tab.focus_mode != Control.FOCUS_ALL:
		return "the Credits tab's scene doesn't render BBCode or take the focus"
	var shown: String = tab.text
	var markdown: String = FileAccess.get_file_as_string(CreditsTab.PATH)
	for line: String in markdown.split("\n"):
		var heading: String = CreditsTab.to_bbcode(line).strip_edges()
		if line.begins_with(CreditsTab.PACK) and not shown.contains(heading):
			return "the Credits tab doesn't show the pack " + line
	if markdown.is_empty() or shown.contains("**") or shown.contains("Files:"):
		return "the Credits tab shows Markdown marks or repository paths: " + shown.left(200)
	if not shown.contains("[b]License:[/b]"):
		return "the Credits tab doesn't name the licenses"
	return ""


## The close button sits at the menu's top right (#554), showing its icon (#459). It closes the
## menu, easing out, and so do
## the cancel action (a controller's B) and the `menu` action, each after opening it again; while
## the menu is closed, cancel leaves it closed.
func _close_menu(menu: GameMenu) -> String:
	# The menu lays itself out for the real screen again, after the tests' other screens.
	await _tree.process_frame
	await _tree.process_frame
	var screen: Vector2 = menu.get_viewport_rect().size
	var close: Button = menu.close_button()
	var corner: Rect2 = close.get_global_rect()
	if corner.end.x < screen.x - 2.0 * GameMenu.MARGIN or corner.position.y > 2.0 * GameMenu.MARGIN:
		return "the close button isn't at the top right: %s on a %s screen" % [corner, screen]
	# It shows its icon (#459), drawn in ink like the menu's text.
	if close.icon != GameMenu.CLOSE_ICON or close.get_theme_color("icon_normal_color") != Toon.INK:
		return "the close button doesn't show its icon in ink"
	var result: String = await _closes(
		menu,
		"the close button",
		func() -> void: close.pressed.emit(),
	)
	if result.is_empty():
		result = await _reopened(menu, "the cancel action", _press.bind(menu, &"ui_cancel"))
	if result.is_empty():
		result = await _reopened(menu, "a controller's B", _press_b.bind(menu))
	if result.is_empty():
		result = await _reopened(menu, "the menu action", _press.bind(menu, &"menu"))
	_press(menu, &"ui_cancel")
	if result.is_empty() and menu.is_open():
		result = "the cancel action opens the closed menu"
	return result


## Opens the menu again, then checks that `close` closes it.
func _reopened(menu: GameMenu, way: String, close: Callable) -> String:
	_press(menu, &"menu")
	await _tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	return await _closes(menu, way, close)


## Calling `close` (the `way` the player closes it) closes the open menu, easing out.
func _closes(menu: GameMenu, way: String, close: Callable) -> String:
	close.call()
	if menu.is_open() or menu.opacity() <= 0.0:
		return "%s doesn't close the menu, or it snaps shut" % way
	await _tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	if menu.opacity() > 0.0:
		return "the menu doesn't finish easing out after %s" % way
	return ""


## Whether ticks run on real time over a few ticks' time.
func _ticks_run(driver: GameDriver) -> bool:
	var tick: int = driver.world.tick
	await _tree.create_timer(STEP * 4.0).timeout
	return driver.world.tick > tick


## Presses `action` on the menu's viewport, as a key or a controller's button does.
func _press(menu: GameMenu, action: StringName) -> void:
	var pressed: InputEventAction = InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	menu.get_viewport().push_input(pressed)


## Presses a controller's B on the menu's viewport, which `ui_cancel` binds (#721).
func _press_b(menu: GameMenu) -> void:
	var pressed: InputEventJoypadButton = InputEventJoypadButton.new()
	pressed.button_index = JOY_BUTTON_B
	pressed.pressed = true
	menu.get_viewport().push_input(pressed)


## Graphics as the main scene has it, reading the test's settings file.
func _start() -> Graphics:
	var ink: InkOutline = InkOutline.new()
	var graphics: Graphics = Graphics.new()
	graphics.settings_path = SETTINGS_PATH
	graphics.ink = ink
	graphics.add_child(ink)
	_tree.root.add_child(graphics)
	return graphics


func _check_applied(graphics: Graphics, msaa: int) -> String:
	if graphics.anti_aliasing() != msaa or _tree.root.msaa_3d != msaa:
		return "MSAA is %d on screen and %d in the settings, expected %d" % [
			_tree.root.msaa_3d,
			graphics.anti_aliasing(),
			msaa,
		]
	if graphics.ink.is_smoothed() != (msaa != Viewport.MSAA_DISABLED):
		return "the ink's smoothing doesn't follow MSAA %d" % msaa
	return ""


func _label_of(msaa: int) -> String:
	if msaa == Viewport.MSAA_DISABLED:
		return "Off"
	return "%d× MSAA" % (1 << msaa)


func _forget() -> void:
	SaveStore.remove(SETTINGS_PATH)
	SaveStore.remove(PROFILE_PATH)
