extends RefCounted
## Settings flow (#161): every graphics setting starts at Auto, which picks the project's value for
## this platform and says so in its label; a player's choice takes effect at once and survives a
## restart; and choosing Auto again hands the setting back. Anti-aliasing is the first: MSAA and the
## ink pass's smoothing together. In the game, the menu's Settings tab (#355, #362) does all that:
## the `menu` action opens the menu, easing in; while it's open the player's keys don't walk and,
## by default, single player pauses (#302): no tick runs. The tab lists every setting, each on Auto
## at first; a step changes one and keeps it, its Auto button hands it back; turning the pause off
## lets the ticks run on behind the menu; turning the damage numbers off hides them and a text size
## sizes them (#764); its README button opens the README's downloads (#1312); the rows fit a
## phone's screen; and the close button at its
## top right, the cancel action (a controller's B) and the menu action each close the menu, easing
## out, and the game goes on. Its Character tab (#391) shows the player's personal
## color (#233), on Auto at first: a color picked on its wheel colors their circle at once and is
## kept in their profile, and its Auto button hands the world's default back. It lists the player's
## dominated monsters (#400): none at first, then each by its species' name and level, which the
## monsters carried through a domination earn progress toward (#1251), the three
## they carry first, in order, the first their companion, each marked in words. A Vynnimu there
## ascends into a Vynakiir with its Ascend button (#1235) once it has reached its level and the
## player holds an arcane crystal. Its gear slots (#690) change with a press outside a fight and
## are kept in the profile, and stay put during one.
## Its Controls tab (#1414) lists every action with the glyphs that press it on the device in use.

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
		result = result if not result.is_empty() else await _menu_development_scroll(menu)
		result = result if not result.is_empty() else _menu_ascension(menu)
	if result.is_empty():
		result = await _menu_holds_game(driver, true)
		result = result if not result.is_empty() else await _menu_takes_no_presses(menu, main)
	if result.is_empty():
		result = await _menu_choices(menu, graphics, main.get_node("SurveyChoice") as SurveyChoice)
	if result.is_empty():
		result = await _menu_pause_choice(menu, driver)
	if result.is_empty():
		result = _menu_readme(menu)
	if result.is_empty():
		result = await _menu_controls(menu)
	if result.is_empty():
		result = await _menu_holds_game(driver, false)
	main.queue_free()
	await _tree.process_frame
	return result


## The `menu` action opens the menu, easing in, and its Settings tab lists every setting, each on
## Auto. Before, its open button on a touch screen shows the glyph of the menu's key or button.
## Then its submenus.
func _open_menu(menu: GameMenu) -> String:
	if menu.is_open() or menu.opacity() > 0.0:
		return "the menu shows before it's opened"
	var glyphs: String = _open_button_glyphs(menu)
	if not glyphs.is_empty():
		return glyphs
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
		HostSettings.DIFFICULTY,
		HostSettings.DROP_RATE,
		HostSettings.RESET_DELAY,
	]
	# Every setting, whatever order their owners added their rows in (#1614): each row's submenu,
	# and so where it shows, is checked on its own (_menu_submenus).
	var every: Array[String] = settings.duplicate()
	every.sort()
	listed.sort()
	if listed != every:
		return "the Settings tab lists %s, not every setting" % [listed]
	# The world's settings have no Auto: the world starts at Standard (#1315, #1316).
	var hosts: Array[String] = [
		shown[HostSettings.DIFFICULTY],
		shown[HostSettings.DROP_RATE],
		shown[HostSettings.RESET_DELAY],
	]
	if hosts != ["Standard", "Standard (100%)", "Standard (1 hour)"]:
		return "the world's settings aren't Standard at first: %s" % [hosts]
	for setting: String in settings.slice(0, -3):
		if not shown[setting].begins_with("Auto ("):
			return "%s isn't on Auto at first: %s" % [setting, shown[setting]]
	return _menu_submenus(menu)


## Why the menu's open button, shown as on a touch screen, doesn't show Escape after a key and
## Start after a controller's button, or shows a glyph after a touch, or "" (#1192).
static func _open_button_glyphs(menu: GameMenu) -> String:
	var button: Button = menu.open_button()
	var kept: bool = button.visible
	button.visible = true
	var buttons: Array[Button] = [button]
	var shown: Array = FlowInput.glyphs_by_device(
		func() -> Array: return FlowInput.badges_shown(buttons)
	)
	button.visible = kept
	var wanted: Array = [
		[InputGlyphs.KEYS[KEY_ESCAPE]],
		[InputGlyphs.BUTTONS[JOY_BUTTON_START]],
		[null],
	]
	if shown != wanted:
		return "the menu's open button shows %s after a key, a controller and a touch" % [shown]
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
	if tab.shown != tab.auto_text() or not tab.picker.color.is_equal_approx(default):
		return "the Character tab doesn't start on Auto's color: %s" % tab.shown
	var picked: Color = PersonalColor.of_number(PICKED)
	tab.picker.color_changed.emit(picked)
	player.show_state()
	# Saved debounced like a gain (#391): a tick before the menu paused the game may have saved the
	# start instance's entry (#730), so the pick waits; flushing saves it, as quitting would.
	var _flushed: String = holder.keeper.flush()
	var kept: Profile = ProfileStore.load_from(PROFILE_PATH)
	if (tab.shown != tab.chosen_text()
			or not player.circle.color.is_equal_approx(picked)
			or kept.personal_color != PICKED):
		return "a picked color isn't shown on the circle or kept: %s, %s, %x" % [
			tab.shown,
			player.circle.color,
			kept.personal_color,
		]
	tab.auto_button.pressed.emit()
	player.show_state()
	if (tab.shown != tab.auto_text()
			or holder.personal_color() != Profile.AUTO_COLOR
			or not tab.picker.color.is_equal_approx(default)
			or not player.circle.color.is_equal_approx(default)):
		return "the Character tab's Auto doesn't hand the world's color back"
	return ""


## The Character tab lists no monsters for a new player; once they dominate four, it lists the three
## they carry first, in the order dominated, the first their companion, then the fourth.
func _menu_monsters(menu: GameMenu, main: Node) -> String:
	var tab: CharacterTab = menu.character
	var none: Array[String] = [DominatedMonstersList.none_text()]
	if tab.monsters.shown != none:
		return "the Character tab lists monsters before any is dominated: %s" % [tab.monsters.shown]
	var gain: Gain = Gain.new()
	gain.dominated_species.assign(["ombulumo", "tikazzir", "tikazzir", "ombulumo"])
	var problem: String = FlowGame.holder(main).keeper.take(gain, Time.get_ticks_msec())
	if not problem.is_empty():
		return "the dominations aren't taken: " + problem
	tab.refresh()
	# Each domination earns the monsters carried then a point (#1251): the first earned three, a
	# level.
	var listed: Array[String] = [
		"Carried 1, companion: Ombulumo, level 2",
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
	_might(tab).refresh()
	if part <= 0 or _might(tab).shown != [
		"Might: %d" % part,
		"From your carried monsters: %d" % part,
	]:
		return "the Character tab's Might is %s, not the carried monsters' %d" % [
			_might(tab).shown,
			part,
		]
	tab.materials.refresh()
	if tab.materials.shown != (["No materials yet"] as Array[String]):
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
## as an unknown faction once the content no longer has it (#1657); neutral again, it leaves the
## list.
func _menu_factions(tab: CharacterTab, main: Node) -> String:
	var panel: FactionStandingsPanel = tab.factions
	var neutral: Array[String] = ["No faction standings yet"]
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
		"Unknown faction: -1",
	]
	if not changed.is_empty() or panel.shown != listed:
		return "the Character tab's factions are %s, not %s" % [panel.shown, listed]
	var links: String = _menu_faction_links(panel, main, faction.id)
	if not links.is_empty():
		return links
	changed = standings.change(faction.id, -2) + standings.change("zz_vanished", 1)
	panel.refresh()
	if not changed.is_empty() or panel.shown != neutral:
		return "a faction back at neutral stays listed: %s" % [panel.shown]
	return _menu_met_factions(tab, main)


## Why the listed faction's name isn't a link to its codex page that showing it met (#1447), or the
## vanished one's, which the content no longer has, is one, or "".
func _menu_faction_links(panel: FactionStandingsPanel, main: Node, faction_id: String) -> String:
	var rows: Array[Node] = panel.get_child(1).get_children()
	var vanished: NameLinks = rows[rows.size() - 1] as NameLinks
	if vanished == null or not vanished.links.is_empty():
		return "the Character tab links a faction the content doesn't have"
	var problem: String = FlowGame.faction_link_problem(main, rows[0] as NameLinks, faction_id)
	return "the Character tab's faction line: " + problem if not problem.is_empty() else ""


## A faction whose name the player has met is listed at its standing before anything moves it
## (#1383): the Odun Kragothai, met, at its start one rank below neutral (#1378); met at neutral,
## the Story guild isn't listed.
func _menu_met_factions(tab: CharacterTab, main: Node) -> String:
	var panel: FactionStandingsPanel = tab.factions
	var keeper: CodexKeeper = main.get_node("CodexKeeper") as CodexKeeper
	keeper.meet(TextTags.FACTION, "amvrel_velmarai")
	keeper.meet(TextTags.FACTION, "odun_kragothai")
	panel.refresh()
	var odun: Faction = FactionContent.cached().factions["odun_kragothai"]
	var listed: Array[String] = [
		"%s: -1, %s" % [odun.name, odun.rank_name(-1)],
	]
	if panel.shown != listed:
		return "the met factions on the Character tab are %s, not %s" % [panel.shown, listed]
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
	var result: String = _gear_starts_empty(_gear(tab))
	if result.is_empty():
		result = _gear_changes(_gear(tab), main)
	if result.is_empty():
		result = _menu_gear_fight(_gear(tab), main, nearby)
	wild.monsters.assign(nearby)
	return result if not result.is_empty() else _menu_reorder(tab, main)


## Every gear slot starts empty and free to change, its button showing its slot's icon and taking
## a controller's focus.
func _gear_starts_empty(panel: GearPanel) -> String:
	panel.refresh()
	var empty: Array[String] = []
	for slot: String in GearSlots.SLOTS:
		empty.append(GearPanel.slot_name(slot) + ": empty")
		var button: Button = panel.buttons[slot]
		if button.icon != GearPanel.ICONS[slot] or button.focus_mode != Control.FOCUS_ALL:
			return "the %s slot's button lacks its icon or a controller's focus" % slot
	empty.append("Press a slot to change its gear.")
	if panel.shown != empty:
		return "the gear slots don't start empty and free to change: %s" % [panel.shown]
	return ""


## Why a slot of `panel` doesn't show the model of its gear in `equipped` beside it, or the empty
## one shows any (#1581), or "".
func _gear_pictured(panel: GearPanel, equipped: Dictionary[String, String]) -> String:
	var gear: GearContent = GearContent.cached()
	for slot: String in GearSlots.SLOTS:
		var model: String = gear.items[equipped[slot]].model if equipped.has(slot) else ""
		var picture: ItemPicture = panel.pictures[slot]
		# The model loaded onto its stage too, not only named.
		if picture.shown != model or (picture.stage.model != null) == model.is_empty():
			return "the %s slot shows the model %s" % [slot, picture.shown]
	return ""


## Pressing the slots puts the player's gear in, its model beside each (#1581), and the gear is
## kept in their profile on disk; the spikes in the trap slot (#692) post one request to the outbox
## in the same save (#818), which the next tick carries into the world's store of the player's trap.
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
		"Press a slot to change its gear.",
	]
	if panel.shown != lines or kept.gear.equipped != expected:
		return "pressing the slots put in %s, kept %s" % [panel.shown, kept.gear.equipped]
	var pictured: String = _gear_pictured(panel, expected)
	if not pictured.is_empty():
		return pictured
	var code: int = SpikesFeature.code_of("thorn_spikes")
	var traps: Array[int] = []
	for request: OutboxEntry in kept.outbox.entries:
		if request.kind == OutboxEntry.TRAP:
			traps.append(request.data)
	if traps != [code]:
		return "changing the gear posted the trap requests %s, not one for the spikes" % [traps]
	# A tick carries one request, oldest first: the host's difficulty steps (_menu_difficulty) go
	# ahead of the trap's.
	var driver: GameDriver = FlowGame.driver(main)
	var stored: int = 0
	for _tick: int in kept.outbox.entries.size():
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
		stored = SpikesFeature.trap_of(driver.world.stored(driver.input.slot, SpikesFeature.ID))
		if stored == code:
			break
	if stored != code:
		return "the spikes in the trap slot didn't reach the world's store: %d" % stored
	return _gear_keeps_passives(FlowGame.holder(main), driver)


## The unique ward charm that keeps the passives on (#617), put into the ward slot the way the
## panel does (ProfileHolder.equip, which tells the session a request was posted), posts a request
## that the next ticks carry into the world's store of the player's companions; taking it out
## posts one that stops it.
func _gear_keeps_passives(holder: ProfileHolder, driver: GameDriver) -> String:
	var keeper: ProfileKeeper = holder.keeper
	keeper.profile.gear.owned["vis_omera"] = 1
	for gear_id: String in ["vis_omera", "warding_charm"]:
		holder.equip("ward", gear_id)
		if keeper.profile.gear.equipped.get("ward", "") != gear_id:
			return "%s didn't go into the ward slot" % gear_id
		var on: bool = gear_id == "vis_omera"
		var kept: bool = not on
		for _tick: int in keeper.profile.outbox.entries.size():
			driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
			var entry: Dictionary = driver.world.stored(driver.input.slot, CompanionFeature.ID)
			kept = CompanionPassives.kept(entry)
			if kept == on:
				break
		if kept != on:
			return "with %s in the ward slot, the world's store keeps the passives on: %s" % [
				gear_id,
				kept,
			]
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
	expected.append("Gear can't be changed during a fight.")
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
	var ids: Array[String] = tab.monsters.shown_ids.duplicate()
	var outbox: Outbox = FlowGame.holder(main).keeper.profile.outbox
	var posted: int = outbox.entries.size()
	tab.monsters.move(ids[3], 0)
	var moved: Array[String] = [
		"Carried 1, companion: Ombulumo, level 1",
		"Carried 2: Ombulumo, level 2",
		"Carried 3: Tikazzir, level 1",
		"Not carried: Tikazzir, level 1",
	]
	var reordered: Array[String] = [ids[3], ids[0], ids[1], ids[2]]
	# The world hears of the new companion at once (#1459), in a new run of carry requests.
	if (tab.monsters.shown != moved or tab.monsters.shown_ids != reordered
			or not FlowSteps.companion_sent(outbox, posted, ids[3])):
		return "moving a monster first didn't make it the companion: %s" % [tab.monsters.shown]
	posted = outbox.entries.size()
	# The second row's up button: its line, then up, then down, each showing its arrow (#584).
	var second: HBoxContainer = tab.monsters.get_child(1).get_child(1) as HBoxContainer
	var up: Button = second.get_child(1) as Button
	var down: Button = second.get_child(2) as Button
	if up.icon != DominatedMonstersList.UP_ICON or down.icon != DominatedMonstersList.DOWN_ICON:
		return "a row's up and down buttons don't show their arrows"
	up.pressed.emit()
	var _flushed: String = FlowGame.holder(main).keeper.flush()
	var kept: Array[String] = ProfileStore.load_from(PROFILE_PATH).carried
	if (tab.monsters.shown_ids[0] != ids[0] or kept != [ids[0], ids[3], ids[1]]
			or not FlowSteps.companion_sent(outbox, posted, ids[0])):
		return "a row's up button didn't move it, or the order isn't kept or sent: %s" % [kept]
	return _menu_details(tab)


## Each type shows after its family's badge (#627): breeze in the last family, mana in the first.
## Every family has its own icon, so the badges never tell families apart by color alone (#68).
func _type_badges(tab: CharacterTab) -> String:
	var families: Array[int] = []
	for row: Node in tab.monsters.details.find_children("*", "HBoxContainer", true, false):
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
	var marks: String = _knot_marks(tab, true)
	return marks if not marks.is_empty() else _menu_development(tab)


## The detail pane (#430) shows the first monster until another is selected, then that one's
## progress toward its next level (#1251) and stats; it sits beside the list on a landscape screen
## and below it on a portrait one.
func _menu_details(tab: CharacterTab) -> String:
	var details: MonsterDetails = tab.monsters.details
	var first: String = tab.monsters.shown_ids[0]
	if tab.monsters.selected != first or not details.shown[0].begins_with("Ombulumo, level 2"):
		return "the detail pane doesn't start on the first monster: %s" % [details.shown]
	# A click on the third row, as the mouse gives it.
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	var third: Label = tab.monsters.get_child(1).get_child(2).get_child(0) as Label
	third.gui_input.emit(click)
	var expected: Array[String] = [
		"Tikazzir, level 1",
		"Progress: 2 of 3 to level 2",
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
	return _type_badges(tab)


## The selected monster's development web (#679), under fog of war (#1417): the level 2 Ombulumo
## sees each direction's first node and none further out, and has one to take. Pressing one takes it
## and keeps it in the profile on disk; then the node beyond it and its links show, the taken one
## says so in words, and with no level left no node can be pressed.
func _menu_development(tab: CharacterTab) -> String:
	var first: String = tab.monsters.shown_ids[0]
	tab.monsters.select(first)
	var view: DevelopmentWebView = tab.find_children("*", "DevelopmentWebView", true, false)[0]
	var nodes: Array = view.buttons.keys()
	nodes.sort()
	var picks: Array[String] = [DevelopmentWebView.title_text(), DevelopmentWebView.picks_text(1)]
	if view.shown != picks or nodes != ["deep_1", "heavy_1", "sturdy_1", "swift_1"]:
		return "the web doesn't show each direction's first node only: %s %s" % [view.shown, nodes]
	var looks: String = _development_looks(view)
	if not looks.is_empty():
		return looks
	view.buttons["sturdy_1"].pressed.emit()
	var _flushed: String = (tab.driver.holder as ProfileHolder).keeper.flush()
	var kept: Array[String] = ProfileStore.load_from(PROFILE_PATH).monster_of(first).taken
	var outbox: Outbox = (tab.driver.holder as ProfileHolder).keeper.profile.outbox
	var problem: String = _sent_at_once(outbox) if kept == (["sturdy_1"] as Array[String]) else (
		"pressing a node didn't take it, or it isn't kept: %s" % [kept]
	)
	if not problem.is_empty():
		return problem
	var posted: int = outbox.entries.size()
	nodes = view.buttons.keys()
	nodes.sort()
	if nodes != ["deep_1", "heavy_1", "sturdy_1", "sturdy_2", "swift_1"]:
		return "taking a node didn't reveal the one beyond it alone: %s" % [nodes]
	if not view.buttons["sturdy_1"].text.begins_with(DevelopmentWebView.taken_text()):
		return "a taken node doesn't say so in words: %s" % view.buttons["sturdy_1"].text
	# With no level left, pressing an open node takes nothing.
	view.buttons["heavy_1"].pressed.emit()
	if ((tab.driver.holder as ProfileHolder).keeper.profile.monster_of(first).taken.size() != 1
			or outbox.entries.size() != posted
			or view.buttons["heavy_1"].focus_mode != Control.FOCUS_ALL):
		return "a node was taken or sent with no level left, or can't take the focus"
	if view.shown[1] != DevelopmentWebView.no_picks_text():
		return "the web doesn't say it takes a node at its next level: %s" % [view.shown]
	if view.is_visible_in_tree() and not view.buttons["sturdy_1"].has_focus():
		return "the focus didn't stay on the node just taken, for a controller"
	return _knot_marks(tab, false)


## Why the knot mark (#1443) isn't on the level 2 Ombulumo's row alone, in words and with the
## knot's shape, and on the menu's open button, shown then on every device, while it has a knot to
## take (`waits`), or is still there once it hasn't; or "".
func _knot_marks(tab: CharacterTab, waits: bool) -> String:
	tab.monsters.refresh()
	var wanted: Array[bool] = [waits, false, false, false]
	var row: Node = tab.monsters.get_child(1).get_child(0)
	var mark: KnotMark = null
	for part: Node in row.find_children("*", "", true, false):
		mark = part as KnotMark if part is KnotMark else mark
	if tab.monsters.marked != wanted or (mark != null) != waits:
		return "the monsters' rows carry the knot mark %s, not %s" % [tab.monsters.marked, wanted]
	if mark != null and (mark.get_child(1) as Label).text != KnotMark.text():
		return "the knot mark doesn't say so in words"
	if mark != null:
		# A click on the mark selects its monster, as one on its line does.
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		mark.gui_input.emit(click)
		if tab.monsters.selected != tab.monsters.shown_ids[0]:
			return "a click on the knot mark doesn't select its monster"
	var menu: GameMenu = tab.get_parent().get_parent().get_parent().get_parent() as GameMenu
	if menu.knot_waits() != waits:
		return "the menu doesn't see that a carried monster has a knot to take"
	menu.show_knot(menu.knot_waits())
	var button: Button = menu.open_button()
	var text: String = menu.knot_text() if waits else menu.open_text()
	var icon: Texture2D = KnotMark.ICON if waits else GameMenu.OPEN_ICON
	# Headless has no touch screen: without a knot, the button hides again.
	if button.text != text or button.icon != icon or button.visible != waits:
		return "the menu's open button is %s, %s with a knot %s" % [
			button.text,
			"shown" if button.visible else "hidden",
			"to take" if waits else "taken",
		]
	return ""


## A dominated Vynnimu's details say into what, at which level and with which material it ascends
## (#1235), and its Ascend button can't be pressed below that level or without the material. With
## both, pressing it makes it a Vynakiir, spends the arcane crystal, says so below its details, and
## the bestiary knows the Vynakiir. Carried first, it reaches the world as a Vynakiir at once
## (#1485).
func _menu_ascension(menu: GameMenu) -> String:
	var tab: CharacterTab = menu.character
	var profile: Profile = (tab.driver.holder as ProfileHolder).keeper.profile
	var gain: Gain = Gain.new()
	gain.dominated_species.assign(["vynnimu"])
	(tab.driver.holder as ProfileHolder).take(gain)
	var pup: DominatedMonster = profile.dominated_monsters[profile.dominated_monsters.size() - 1]
	tab.monsters.move(pup.short_id, 0)
	tab.monsters.select(pup.short_id)
	var details: MonsterDetails = tab.monsters.details
	var told: String = _evolution_told(details.evolution)
	if not told.is_empty():
		return told
	if not details.ascend_button.disabled:
		return "a level 1 Vynnimu's Ascend button can be pressed"
	pup.level = 43
	profile.materials["arcane_crystal"] = 1
	tab.monsters.refresh()
	if details.ascend_button.disabled:
		return "a level 43 Vynnimu with a crystal can't press Ascend"
	var posted: int = profile.outbox.entries.size()
	details.ascend_button.pressed.emit()
	var known: Bestiary = BestiaryKeeper.of((tab.driver.holder as ProfileHolder))
	if pup.species != "vynakiir" or profile.materials.has("arcane_crystal"):
		return "pressing Ascend didn't make it a Vynakiir, or kept the crystal"
	if not _sent_ascended(profile.outbox, posted, pup.short_id):
		return "the ascended companion didn't go to the world as a Vynakiir at once"
	if details.notice != MonsterDetails.ascended_text("Vynnimu", "Vynakiir"):
		return "no line says it ascended: %s" % details.notice
	if details.ascend_button.visible or not details.shown[0].begins_with("Vynakiir, level 43"):
		return "the details don't show the Vynakiir: %s" % [details.shown]
	if known == null or known.level_of("vynakiir") != Bestiary.KNOWN:
		return "the bestiary didn't learn the Vynakiir it ascended into"
	return ""


## Why a level 1 Vynnimu's ascension (#1796) isn't shown as a picture: its form, an item for the
## arcane crystal (none held) that opens its card on a controller's focus and hides it again, and
## the level below the arrow; or "".
static func _evolution_told(evolution: EvolutionGraphic) -> String:
	var wanted: Array[String] = [
		"Arcane Crystal",
		EvolutionGraphic.material_text("Arcane Crystal", 0),
		EvolutionGraphic.level_text(43),
	]
	if not evolution.visible or evolution.card.shown != wanted:
		return "a Vynnimu's ascension isn't shown, or its card says %s" % [evolution.card.shown]
	if evolution.item.text != EvolutionGraphic.held_text(0) or evolution.level_line != "Level 43":
		return "its item says %s and its level %s" % [evolution.item.text, evolution.level_line]
	if evolution.card.visible:
		return "the item's card shows before the item is focused"
	evolution.item.grab_focus()
	var opened: bool = evolution.card.visible
	# The pointer on the open card meets the card, not what it covers, like the Ascend button
	# (#1807).
	var on_card: bool = _pointed_at(evolution.card, evolution.card.get_global_rect().get_center())
	var _away: bool = _pointed_at(evolution.card, Vector2.ZERO)
	evolution.item.release_focus()
	if not opened or evolution.card.visible:
		return "the item's card doesn't open on a controller's focus, or stays once it leaves"
	if not on_card:
		return "a pointer on the item's card reaches what lies below it"
	return ""


## Whether moving the mouse to `at` on `seen`'s screen puts it on `seen`.
static func _pointed_at(seen: Control, at: Vector2) -> bool:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	seen.get_viewport().push_input(motion)
	return seen.get_viewport().gui_get_hovered_control() == seen


## Whether a run of carry requests posted to `outbox` past its first `posted` entries brings the
## companion `short_id` as a Vynakiir (#1485): an ascension mid-session goes to the world at once.
static func _sent_ascended(outbox: Outbox, posted: int, short_id: String) -> bool:
	return (FlowSteps.companion_sent(outbox, posted, short_id)
			and FlowSteps.carry_sent(outbox, posted)[0] == CarryRequest.species_code("vynakiir"))


## Ombulumo's sturdy_1 taken mid-session goes to the world at once, not at the next session
## (#1459): the newest run of carry requests waiting in `outbox` has the companion leaning +5% HP.
static func _sent_at_once(outbox: Outbox) -> String:
	var values: Array[int] = FlowSteps.carry_sent(outbox)
	# Its species, its short id, then its leaning (CarryRequest.values_of).
	var at_leaning: int = 2
	var leaning: CompanionLeaning = null
	if values.size() > at_leaning:
		leaning = CompanionLeaning.of_code(values[at_leaning])
	if leaning == null or not leaning.same_as(CompanionLeaning.of(50, 0, 0)):
		return "the node taken didn't send the companion leaning +5% HP to the world at once"
	return ""


## On a phone held upright the web steepens its spokes to fit the tab's width, its nodes never
## covering each other (#1442): taking a node a step further out keeps the focus on it and in sight,
## so a controller never loses it off the edge (#1441).
func _menu_development_scroll(menu: GameMenu) -> String:
	var tab: CharacterTab = menu.character
	var view: DevelopmentWebView = tab.find_children("*", "DevelopmentWebView", true, false)[0]
	var first: String = tab.monsters.shown_ids[0]
	# Two more levels: two nodes to take, beside the one taken already.
	(tab.driver.holder as ProfileHolder).keeper.profile.monster_of(first).level += 2
	# The menu lays itself out for the window every frame: it rests, so the phone's layout holds.
	menu.set_process(false)
	menu.lay_out(Vector2(360.0, 640.0))
	tab.monsters.select(first)
	await _tree.process_frame
	await _tree.process_frame
	var problem: String = await _taken_in_sight(view, "sturdy_2")
	if problem.is_empty():
		problem = await _taken_in_sight(view, "sturdy_3")
	menu.set_process(true)
	menu.lay_out(Vector2(1920.0, 1080.0))
	return problem


## Takes `node` on `view`'s web; returns why it isn't focused and fully in sight after, or "".
func _taken_in_sight(view: DevelopmentWebView, node: String) -> String:
	view.buttons[node].pressed.emit()
	await _tree.process_frame
	await _tree.process_frame
	var button: Button = view.buttons[node]
	var shown: Rect2 = button.get_global_rect()
	var web: Control = button.get_parent()
	var across: Rect2 = (web.get_parent() as Control).get_global_rect()
	# A pixel's leeway for rounding, here and below.
	if web.size.x > across.size.x + 1.0:
		return "the web doesn't fit the narrow screen with %s taken: %s in %s" % [
			node,
			web.size,
			across.size,
		]
	var rects: Array[Rect2] = []
	for each: Button in view.buttons.values():
		rects.append(each.get_global_rect().grow(-1.0))
	for first: int in rects.size():
		for second: int in range(first + 1, rects.size()):
			if rects[first].intersects(rects[second]):
				return "two nodes cover each other on the narrow screen: %s" % [rects]
	var inside: bool = shown.position.x >= across.position.x and shown.end.x <= across.end.x + 1.0
	if not button.has_focus() or not inside:
		return "taking %s didn't keep it focused and in sight: %s in %s" % [node, shown, across]
	return ""


## An open node of the web says what it shifts in words, is finger-sized, and stays reachable on a
## narrow screen: the web scrolls sideways on its own (#1441). A special or a passive node says what
## it grants (#1452).
func _development_looks(view: DevelopmentWebView) -> String:
	var web: Control = view.buttons["sturdy_1"].get_parent()
	var across: ScrollContainer = web.get_parent() as ScrollContainer
	if across == null or across.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		return "the development web doesn't scroll sideways on its own"
	if view.buttons["sturdy_1"].custom_minimum_size.y <= 0.0:
		return "a node isn't finger-sized"
	if view.buttons["sturdy_1"].text != "HP +5%":
		return "an open node doesn't say in words what it shifts: " + view.buttons["sturdy_1"].text
	# The deepest nodes, still in fog here, grant a stronger special and a passive, by name (#1452).
	var grants: Array[String] = [view.node_text("heavy_4"), view.node_text("deep_4")]
	if grants != (["Special +20%", "Passive\nLombu-bombu"] as Array[String]):
		return "a special or a passive node doesn't say what it grants: %s" % [grants]
	return ""


## While the menu is open (`open`), the player's keys don't walk and no tick runs; once it's
## closed, both go on.
func _menu_holds_game(driver: GameDriver, open: bool) -> String:
	Input.action_press("move_right")
	var walks: bool = (driver.input as LocalInput).command(driver.state).move != Command.NO_MOVE
	Input.action_release("move_right")
	var ticked: bool = await _ticks_run(driver)
	if walks == open or ticked == open:
		return "with the menu %s, the keys %s walk and the ticks %s run" % [
			"open" if open else "closed",
			"do" if walks else "don't",
			"do" if ticked else "don't",
		]
	return ""


## Behind the open menu the action buttons hide and take no touch, and presses made while it's
## open (the special's key, place_totem held on as it closes) or in the frame it closes
## (interact, a controller's A that may close it) never reach the first command after it closes
## (#1509). Closed, the buttons show again; then the menu opens again for the next steps.
func _menu_takes_no_presses(menu: GameMenu, main: Node) -> String:
	var special: SpecialButton = main.get_node("Hud/SpecialButton") as SpecialButton
	var input: LocalInput = main.get_node("LocalInput") as LocalInput
	special.touch = true
	special.lay_out_in(special.get_viewport_rect().size)
	var shown_open: bool = special.visible
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = special.rect().get_center()
	touch.pressed = true
	special.get_viewport().push_input(touch)
	var touched: bool = Input.is_action_pressed(&"special_attack")
	var lift: InputEventScreenTouch = touch.duplicate() as InputEventScreenTouch
	lift.pressed = false
	special.get_viewport().push_input(lift)
	Input.action_press(&"special_attack")
	Input.action_press(&"place_totem")
	input._process(0.0)
	Input.action_release(&"special_attack")
	menu.toggle()
	Input.action_press(&"interact")
	input._process(0.0)
	Input.action_release(&"interact")
	var first: Command = input.command(FlowGame.driver(main).state)
	var held_over: String = await _totem_held_over(input, FlowGame.driver(main))
	special.lay_out_in(special.get_viewport_rect().size)
	var shown_closed: bool = special.visible
	special.touch = false
	special.lay_out_in(special.get_viewport_rect().size)
	menu.toggle()
	await _tree.create_timer(GameMenu.FADE_SECONDS * 2.0).timeout
	if shown_open or touched:
		return "the special's button shows or takes a touch behind the open menu"
	if first.special or first.interact or first.totem != Command.NO_TOTEM:
		return "a press made while the menu was open, or as it closed, reached the next command"
	if not shown_closed:
		return "the special's button doesn't show again once the menu closes"
	return held_over


## place_totem held on past the menu's closing (#1549) still places nothing a few frames later;
## let go and pressed anew, it places at once, even in a command asked before the frame's
## _process hears the press. Leaves it let go.
func _totem_held_over(input: LocalInput, driver: GameDriver) -> String:
	await _tree.process_frame
	await _tree.process_frame
	await _tree.process_frame
	var held: Command = input.command(driver.state)
	Input.action_release(&"place_totem")
	Input.action_press(&"place_totem")
	var fresh: Command = input.command(driver.state)
	Input.action_release(&"place_totem")
	if held.totem != Command.NO_TOTEM:
		return "place_totem held on past the menu's closing placed the totem"
	if fresh.totem != Command.PLACE_TOTEM:
		return "a fresh press of place_totem after the menu closed placed no totem"
	return ""


## The Settings tab opens on its list of submenus (#1314), each setting's row in its own: a
## submenu's button shows its rows in place of the list, and its Back button or a controller's B
## goes back to the list, the menu still open. Left on a submenu, it's back on its list the next
## time it shows.
func _menu_submenus(menu: GameMenu) -> String:
	var tab: SettingsTab = menu.settings
	if tab.open_submenu() != SettingsTab.LIST:
		return "the Settings tab opens on %s, not its list" % tab.open_submenu()
	var homes: Dictionary[String, String] = {
		Graphics.ANTI_ALIASING: SettingsTab.GRAPHICS,
		SurveyChoice.PLACE_SETTING: SettingsTab.INTERFACE,
		SurveyChoice.ZOOM_SETTING: SettingsTab.INTERFACE,
		DamageNumbersChoice.SHOWN_SETTING: SettingsTab.INTERFACE,
		DamageNumbersChoice.SIZE_SETTING: SettingsTab.INTERFACE,
		GameMenu.PAUSE_SETTING: SettingsTab.GAME,
		HostSettings.DIFFICULTY: SettingsTab.DIFFICULTY,
		HostSettings.DROP_RATE: SettingsTab.WORLD,
		HostSettings.RESET_DELAY: SettingsTab.WORLD,
	}
	for setting: String in homes:
		if tab.submenu_of(setting) != homes[setting]:
			return "%s is in the submenu %s" % [setting, tab.submenu_of(setting)]
	# The Interface submenu's rows in the order they show, though the menu and game/ add them
	# (#1614).
	var titles: Array[String] = []
	var interface: Node = tab.back_button(SettingsTab.INTERFACE).get_parent().get_parent()
	for row: Node in interface.get_children():
		if row is Label:
			titles.append((row as Label).text)
	if titles != ["Survey", "Survey zoom", "Damage numbers", "Damage number size"]:
		return "the Interface submenu shows the rows %s" % [titles]
	var tabs: TabContainer = tab.get_parent() as TabContainer
	var was_on: int = tabs.current_tab
	tabs.current_tab = tab.get_index()
	var anti_aliasing: Button = tab.button(Graphics.ANTI_ALIASING, "Next")
	var problem: String = _submenus_open(menu, tab, anti_aliasing)
	tab.opener(SettingsTab.GRAPHICS).pressed.emit()
	tabs.current_tab = was_on
	tabs.current_tab = tab.get_index()
	if problem.is_empty() and tab.open_submenu() != SettingsTab.LIST:
		problem = "the Settings tab, shown again, is still on %s" % tab.open_submenu()
	tabs.current_tab = was_on
	return problem


## Opening the Graphics submenu shows its rows only, B goes back, and so does the Game submenu's
## Back button.
func _submenus_open(menu: GameMenu, tab: SettingsTab, anti_aliasing: Button) -> String:
	if anti_aliasing.is_visible_in_tree():
		return "a submenu's rows show over the list"
	# A controller's focus on the Graphics button moves onto its Back button, and back after B.
	tab.opener(SettingsTab.GRAPHICS).grab_focus()
	tab.opener(SettingsTab.GRAPHICS).pressed.emit()
	if tab.get_viewport().gui_get_focus_owner() != tab.back_button(SettingsTab.GRAPHICS):
		return "opening a submenu doesn't move the focus onto its Back button"
	if (tab.open_submenu() != SettingsTab.GRAPHICS or not anti_aliasing.is_visible_in_tree()
			or tab.opener(SettingsTab.GRAPHICS).is_visible_in_tree()
			or tab.button(GameMenu.PAUSE_SETTING, "Next").is_visible_in_tree()):
		return "the Graphics button doesn't show only its rows in place of the list"
	_press_b(menu)
	if tab.open_submenu() != SettingsTab.LIST or not menu.is_open():
		return "a controller's B in a submenu doesn't go back to the list, or closes the menu"
	if tab.get_viewport().gui_get_focus_owner() != tab.opener(SettingsTab.GRAPHICS):
		return "going back doesn't move the focus onto the submenu's button"
	var difficulty: String = _menu_difficulty(menu, tab)
	if not difficulty.is_empty():
		return difficulty
	tab.opener(SettingsTab.GAME).pressed.emit()
	tab.back_button(SettingsTab.GAME).pressed.emit()
	if (tab.open_submenu() != SettingsTab.LIST
			or not tab.opener(SettingsTab.GAME).is_visible_in_tree()):
		return "a submenu's Back button doesn't go back to the list"
	return ""


## The host opens the Difficulty submenu and steps the difficulty to Hard (#1315): it has no Auto
## button, the row says Hard at once and the request waits in the profile's outbox for the world;
## stepping back says Standard again, and the submenu's Back button returns to the list.
func _menu_difficulty(menu: GameMenu, tab: SettingsTab) -> String:
	var next: Button = tab.button(HostSettings.DIFFICULTY, "Next")
	if next.is_visible_in_tree():
		return "the difficulty's row shows over the list"
	tab.opener(SettingsTab.DIFFICULTY).pressed.emit()
	if tab.open_submenu() != SettingsTab.DIFFICULTY or not next.is_visible_in_tree():
		return "the Difficulty button doesn't show the difficulty's row"
	if next.get_parent().has_node("Auto"):
		return "the difficulty has an Auto button"
	next.pressed.emit()
	var outbox: Outbox = (menu.driver.holder as ProfileHolder).keeper.profile.outbox
	var asked: bool = false
	for request: OutboxEntry in outbox.entries:
		asked = asked or request.kind == OutboxEntry.HOST_SETTING
	var said: String = tab.shown[HostSettings.DIFFICULTY]
	tab.button(HostSettings.DIFFICULTY, "Previous").pressed.emit()
	if said != "Hard" or not asked or tab.shown[HostSettings.DIFFICULTY] != "Standard":
		return "stepping the difficulty shows %s, asking the world: %s" % [said, asked]
	tab.back_button(SettingsTab.DIFFICULTY).pressed.emit()
	if tab.open_submenu() != SettingsTab.LIST or next.is_visible_in_tree():
		return "the Difficulty submenu's Back button doesn't return to the list"
	return ""


## Stepping anti-aliasing on and the Survey's place back takes effect and keeps them;
## anti-aliasing's Auto button hands it back. The step buttons show their arrows (#584).
func _menu_choices(menu: GameMenu, graphics: Graphics, survey: SurveyChoice) -> String:
	var tab: SettingsTab = menu.settings
	if (tab.button(Graphics.ANTI_ALIASING, "Previous").icon != SettingsTab.PREVIOUS_ICON
			or tab.button(Graphics.ANTI_ALIASING, "Next").icon != SettingsTab.NEXT_ICON):
		return "a setting's step buttons don't show their arrows"
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
	return problem if not problem.is_empty() else await _menu_damage_numbers(menu)


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
			or numbers.strikes[0].text != "fainted"):
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
	if sized != "Auto (100%)":
		return "the damage number size's Auto shows %s" % sized
	return await _numbers_rise_up_the_screen(numbers)


## A damage number rises up the screen by its whole rise (#804): along the game camera's up,
## across its view, not straight up, of which the steep camera shows only a small part.
func _numbers_rise_up_the_screen(numbers: DamageNumbersView) -> String:
	numbers.show_strike(Vector2i.ZERO, SpecialStruck.new(0, 0, 5, false))
	var label: Label3D = numbers.strikes[-1]
	var start: Vector3 = label.position
	await _tree.create_timer(DamageNumbersView.SECONDS * 0.5).timeout
	var risen: Vector3 = label.position - start
	var up: Vector3 = label.get_viewport().get_camera_3d().global_basis.y.normalized()
	if risen.length() <= 0.0 or risen.normalized().dot(up) < 0.999:
		return "a damage number rose by %s, not up the game camera's screen (%s)" % [risen, up]
	return ""


## The Settings tab's README button (#1312) opens the README's downloads, through the link opener
## the test swaps in, so no browser opens. Then the rows fit every screen.
func _menu_readme(menu: GameMenu) -> String:
	var tab: SettingsTab = menu.settings
	var opened: Array[String] = []
	tab.open_link = func(url: String) -> Error:
		opened.append(url)
		return OK
	tab.readme_button.pressed.emit()
	if (tab.readme_button.text != tab.readme_text()
			or opened.size() != 1
			or opened[0] != SettingsTab.README_URL):
		return "the README button opened %s" % [opened]
	return _menu_on_screens(menu)


## The settings' rows fit a phone held either way and a desktop screen.
func _menu_on_screens(menu: GameMenu) -> String:
	for screen: Vector2 in [Vector2(360.0, 640.0), Vector2(640.0, 360.0), Vector2(1920.0, 1080.0)]:
		menu.lay_out(screen)
		var width: float = menu.settings.rows_width()
		if width <= 0.0 or width > screen.x - 2.0 * GameMenu.MARGIN:
			return "the settings' rows are %d pixels wide on a %s screen" % [width, screen]
		var problem: String = _open_button_placed(menu, screen)
		if problem.is_empty():
			# The Survey in the top right corner too, the list and the button then on the left.
			var _right: String = menu.survey.cycle(1)
			problem = _open_button_placed(menu, screen)
			var _back: String = menu.survey.cycle(-1)
		if not problem.is_empty():
			return problem
	var saving: String = _credits_log_button(menu)
	if saving.is_empty():
		saving = _credits_bug_report(menu)
	return saving if not saving.is_empty() else _menu_credits(menu)


## The open button stands at the top's middle on a landscape screen, and on a screen held upright
## at the top of the quest list's side, the list starting below the room it leaves for it, and at
## its side's top while the button is hidden (#1465): the left, or the right while the Survey is
## in the top left corner.
func _open_button_placed(menu: GameMenu, screen: Vector2) -> String:
	var button: Button = menu.open_button()
	var shown: bool = button.visible
	var hidden_top: float = _list_top(menu, screen, false)
	var hidden_room: float = _quest_list(menu).room_above
	var list_top: float = _list_top(menu, screen, true)
	var room: float = _quest_list(menu).room_above
	var at: Rect2 = button.get_rect()
	var badged: Rect2 = GameMenu.with_badge(button)
	badged.position += at.position
	button.visible = shown
	menu.lay_out(screen)
	var column: Rect2 = _quest_list(menu).column_in(screen)
	var placed: bool = (is_equal_approx(at.get_center().x, screen.x / 2.0)
			and is_equal_approx(at.position.y, GameMenu.MARGIN) and room == 0.0)
	if screen.y > screen.x:
		placed = (_at_side(at, badged, column, screen)
				and is_equal_approx(at.position.y, column.position.y)
				and is_equal_approx(room, badged.end.y - at.position.y + QuestListView.GAP))
	placed = (placed and hidden_room == 0.0 and is_equal_approx(hidden_top, column.position.y)
			and is_equal_approx(list_top, column.position.y + room))
	if not placed:
		return "open button %s on %s, list side %s, room %s/%s, list top %s/%s" % [
			at,
			screen,
			column,
			room,
			hidden_room,
			list_top,
			hidden_top,
		]
	return ""


## Whether the button at `at`, with its badge `badged`, stands on the edge of the list's `column`
## on a screen of `screen` pixels: its left edge on the left, its badge's right edge on the right.
static func _at_side(at: Rect2, badged: Rect2, column: Rect2, screen: Vector2) -> bool:
	if column.get_center().x < screen.x / 2.0:
		return is_equal_approx(at.position.x, column.position.x)
	return is_equal_approx(badged.end.x, column.end.x)


## Where the quest list starts on a screen of `screen` pixels, the menu's open button `shown` or
## not.
static func _list_top(menu: GameMenu, screen: Vector2, shown: bool) -> float:
	menu.open_button().visible = shown
	menu.lay_out(screen)
	_quest_list(menu).lay_out_in(screen, 1.0)
	return _quest_list(menu).position.y


## The Credits tab's button that saves the error log as a file (#1541) shows only on the web, and
## what it saves starts with the log's header.
func _credits_log_button(menu: GameMenu) -> String:
	var page: Node = menu.find_child("Credits", true, false)
	var save: ErrorLogButton = page.get_node("ErrorLog") as ErrorLogButton
	if save == null or save.visible != OS.has_feature("web") or not ErrorLog.written():
		return "the Credits tab's button saving the error log shows other than only on the web"
	if not ErrorLog.saved().get_string_from_utf8().begins_with(ErrorLog.header().left(20)):
		return "the error log saved as a file doesn't start with its header"
	return ""


## The Credits tab's "Report a bug" button (#1405) opens, through the link opener the test swaps
## in, a new issue whose body names the build's version and the platform, as the error log's header
## does, and where the log is (the tab, or its save button on the web), but no folder of the device.
func _credits_bug_report(menu: GameMenu) -> String:
	var report: BugReportButton = (
		menu.find_child("Credits", true, false).get_node("BugReport") as BugReportButton
	)
	if report == null or not report.visible:
		return "the Credits tab has no Report a bug button"
	var opened: Array[String] = []
	report.open_link = func(url: String) -> Error:
		opened.append(url)
		return OK
	report.pressed.emit()
	if opened.size() != 1 or not opened[0].begins_with(BugReportButton.NEW_ISSUE_URL):
		return "the Report a bug button opened %s" % [opened]
	var body: String = opened[0].trim_prefix(BugReportButton.NEW_ISSUE_URL).uri_decode()
	if (not body.contains(ErrorLog.header().strip_edges())
			or not body.contains(BuildVersion.LOCAL_BUILD)
			or not body.contains(BugReportButton.log_place())
			or body.contains(OS.get_user_data_dir())):
		return "the bug report's body doesn't name the version, platform and log: " + body
	return ""


## The Credits tab (#462) names the build's version first (#744; a local one here, which CI's
## export alone stamps), then where the error log is (#1510), which starts with that version, then
## shows every pack CREDITS.md credits, each heading in bold, with its
## fields' names in bold and no Markdown marks or repository paths left over.
func _menu_credits(menu: GameMenu) -> String:
	var tab: CreditsTab = menu.find_child("Credits", true, false).get_node("Text") as CreditsTab
	# Laid out in its scene (#437): BBCode on, and focusable so a controller scrolls it.
	if not tab.bbcode_enabled or tab.focus_mode != Control.FOCUS_ALL:
		return "the Credits tab's scene doesn't render BBCode or take the focus"
	var shown: String = tab.text
	var version: String = "[b]Version:[/b] " + BuildVersion.LOCAL_BUILD + "\n"
	if not shown.begins_with(version + CreditsTab.log_line()) or ErrorLog.location().is_empty():
		return "the Credits tab doesn't name the version and the log first: " + shown.left(160)
	var logged: String = FileAccess.get_file_as_string(ErrorLog.PATH)
	if not logged.begins_with(str(ProjectSettings.get_setting("application/config/name")) + " "):
		return "the error log doesn't start with the game and its version: " + logged.left(80)
	if not logged.contains(BuildVersion.LOCAL_BUILD):
		return "the error log doesn't name the version: " + logged.left(80)
	# It never names the folders a path could name the player by.
	var hidden: String = ErrorLog.new(null).scrubbed(OS.get_user_data_dir() + "/world.json")
	if hidden != "user://world.json":
		return "the error log names the user folder: " + hidden
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


## The Controls tab (#1414) lists every action the project binds, each row with the glyphs of what
## presses it on the device in use, following a change of device: W, A, S and D, the left stick or
## a drag to walk, and on touch a tap where no gesture does it. Every row takes the focus, so a
## controller moves among them, and the focused one is framed.
func _menu_controls(menu: GameMenu) -> String:
	var tab: ControlsTab = menu.controls_tab()
	var listed: Array[StringName] = []
	for words: String in ControlsTab.ROWS:
		listed.append_array(ControlsTab.ROWS[words])
		# Each row's label shows its words, translated (in English, the same words).
		var label: Label = tab.rows[words].get_child(0).get_child(0) as Label
		if label == null or label.text != words or tab.words_of(words) != words:
			return "the Controls tab's row %s shows %s" % [
				words,
				label.text if label else "nothing",
			]
	# The actions the project binds itself, not Godot's own UI actions it leaves as they are.
	var project: ConfigFile = ConfigFile.new()
	var _read: Error = project.load("res://project.godot")
	for action: String in project.get_section_keys("input"):
		if StringName(action) not in listed:
			return "the Controls tab doesn't list " + action
	var problem: String = _controls_glyphs(FlowInput.glyphs_by_device(_controls_shown.bind(tab)))
	if not problem.is_empty():
		return problem
	return await _controls_focus(menu, tab)


## On the Controls tab, down (the left stick, the d-pad or the arrow key) moves the focus to the
## next row, which is framed. Then the menu closes (_close_menu).
func _controls_focus(menu: GameMenu, tab: ControlsTab) -> String:
	var tabs: TabContainer = tab.get_parent() as TabContainer
	var was_on: int = tabs.current_tab
	tabs.current_tab = tab.get_index()
	# The rows are laid out once the shown tab has had its frames.
	await _tree.process_frame
	await _tree.process_frame
	var walk: PanelContainer = tab.rows["Walk"]
	walk.grab_focus()
	var down: InputEventAction = InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	menu.get_viewport().push_input(down)
	var focused: Control = menu.get_viewport().gui_get_focus_owner()
	var resting: StyleBox = walk.get_theme_stylebox("panel")
	var framed: StyleBox = tab.rows["Special attack"].get_theme_stylebox("panel")
	if focused != null:
		focused.release_focus()
	tabs.current_tab = was_on
	if focused != tab.rows["Special attack"] or framed == resting:
		return "down on the Controls tab focuses %s, framed: %s" % [focused, framed != resting]
	return await _close_menu(menu)


## Checks the Controls tab's glyphs `by_device` (a keyboard's, a controller's, touch's): a glyph in
## every row, the walking keys, stick or drag, and a tap on touch where no gesture does it.
func _controls_glyphs(by_device: Array) -> String:
	var keys: Array[Texture2D] = []
	for key: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		keys.append(InputGlyphs.KEYS[key])
	var walks: Array = [keys, [InputGlyphs.STICK_LEFT], [InputGlyphs.DRAG]]
	for device: int in by_device.size():
		var shown: Dictionary = by_device[device]
		for words: String in ControlsTab.ROWS:
			var glyphs: Array = shown[words]
			if glyphs.is_empty():
				return "the Controls tab shows no glyph for %s on device %d" % [words, device]
		if shown["Walk"] != walks[device]:
			return "the Controls tab's Walk row shows %s on device %d" % [shown["Walk"], device]
	var touch: Dictionary = by_device[2]
	if touch["Special attack"] != [InputGlyphs.pointing(DeviceInUse.Device.TOUCH)]:
		return "on touch, the Controls tab doesn't show a tap for the special attack"
	return ""


## The glyphs the Controls tab shows now, by row, after it follows the device in use.
func _controls_shown(tab: ControlsTab) -> Dictionary:
	tab.refresh()
	return tab.shown.duplicate()


## The close button sits at the menu's top right (#554), showing its icon (#459). It closes the
## menu, easing out, and so do the cancel action (a controller's B) and the `menu` action, each
## after opening it again; while the menu is closed, cancel leaves it closed.
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


## The Character tab's Might panel, which game/ hands in (#1614).
static func _might(tab: CharacterTab) -> MightPanel:
	return tab.find_child("Might", true, false) as MightPanel


## The Character tab's gear panel, which game/ hands in (#1614).
static func _gear(tab: CharacterTab) -> GearPanel:
	return tab.find_child("Gear", true, false) as GearPanel


## The quest list at the top's side, beside the menu in the main scene's HUD.
static func _quest_list(menu: GameMenu) -> QuestListView:
	return menu.get_parent().get_node("QuestList") as QuestListView
