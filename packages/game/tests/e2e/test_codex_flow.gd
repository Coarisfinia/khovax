extends RefCounted
## Codex flow (#1174): the menu's Codex tab, after its gameplay tabs and before its system tabs, is
## the codex book, which lists every entry the player has unlocked, each kind under its heading. A
## new player's book says it's empty. Teska na Amvrel's greeting shows the speaker's name, which
## lists them under "People" (#1005), and its second line the Amvrel Velmarai's, which lists the
## guild under "Lexicon", and the realm Ardvaun's, listed under "Realms" (#1175); a species seen is
## listed under "Bestiary" (#1173), and a place met under "Places", whose entry opens its page.
## Entering a place a realm draws meets its name and its realm's; the playground, which no realm
## draws, meets nothing. The
## names met are kept
## in the profile's file beside the profile, so a new session finds them there. The guild's entry
## opens its lexicon page over the menu, with a controller's A, a click or a tap, and B, Escape or
## the page's close button close it back to the book: the menu stays open, the game still hears no
## input, and the focus goes back to the entry. A save whose names met are malformed is refused,
## and an older save starts with none.

const PROFILE: String = "user://test_codex_profile.json"
const ENTERING_PROFILE: String = "user://test_codex_entering_profile.json"
const GREETING: String = "teska_na_amvrel_greeting"
const GUILD: String = "amvrel_velmarai"
const SCOUT: String = "teska_na_amvrel"
const SCREEN: Vector2i = Vector2i(1152, 648)


func run(tree: SceneTree) -> String:
	# A desktop screen: the headless window is too small for the menu's tabs, and the clicks must
	# land on the book's entry.
	var kept_size: Vector2i = tree.root.size
	tree.root.size = SCREEN
	var main: Node = await FlowGame.start(tree, PROFILE)
	var driver: GameDriver = FlowGame.held_driver(main)
	var menu: GameMenu = main.get_node("Hud/GameMenu") as GameMenu
	var book: CodexBook = menu.find_child("Codex", true, false) as CodexBook
	var result: String = _empty_book(driver, book)
	if result.is_empty():
		result = await _meet_the_guild(tree, main, book)
	if result.is_empty():
		result = _see_a_species(main, book)
	if result.is_empty():
		result = await _open_from_book(tree, main, driver, menu, book)
	if result.is_empty():
		result = _kept_in_profile(main)
	if result.is_empty():
		result = _refuse_malformed()
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(PROFILE)
	if result.is_empty():
		result = await _enter_a_place(tree)
	tree.root.size = kept_size
	return result


## The book is the menu's tab after Quests and before Settings, and a new player's lists nothing,
## also after a tick in the playground, which no realm draws.
static func _empty_book(driver: GameDriver, book: CodexBook) -> String:
	driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	if book == null:
		return "the menu has no Codex tab"
	var tabs: Array[String] = []
	for tab: Node in book.get_parent().get_children():
		tabs.append(tab.name)
	var at: int = tabs.find("Codex")
	if at < 1 or tabs[at - 1] != "Quests" or tabs[at + 1] != "Settings":
		return "the menu's tabs are %s" % [tabs]
	book.refresh()
	var none: Label = book.get_node("Middle/Rows").get_child(0) as Label
	if not book.shown.is_empty() or none == null or none.text != CodexBook.NONE_TEXT:
		return "a new player's book listed %s" % [book.shown]
	return ""


## The greeting's first line names no faction; reading on to the second, which names the guild,
## lists it in the book, under the lexicon's heading.
static func _meet_the_guild(tree: SceneTree, main: Node, book: CodexBook) -> String:
	var screen: DialogScreen = main.get_node("Hud/DialogScreen") as DialogScreen
	var keeper: CodexKeeper = main.get_node("CodexKeeper") as CodexKeeper
	if not screen.open(GREETING):
		return "the greeting didn't open"
	await tree.process_frame
	if keeper.has_met(TextTags.FACTION, GUILD):
		return "the guild was met before its name was shown"
	if not keeper.has_met(TextTags.PERSON, SCOUT):
		return "the greeting's speaker wasn't met"
	FlowInput.press_pad(book, JOY_BUTTON_A)
	if screen.line_index != 1 or not keeper.has_met(TextTags.FACTION, GUILD):
		return "reading on to the guild's name didn't meet it"
	book.refresh()
	var heading: Label = book.get_node("Middle/Rows").get_child(0) as Label
	var entry: Button = book.entry_button(TextTags.FACTION, GUILD)
	if book.shown.get(TextTags.FACTION, []) != [GUILD] or heading == null or entry == null:
		return "the book listed %s" % [book.shown]
	if heading.text != CodexPage.LEXICON_TEXT or entry.text != "Amvrel Velmarai":
		return "the book showed %s: %s" % [heading.text, entry.text]
	if book.shown.get(TextTags.REALM, []) != ["ardvaun"]:
		return "reading the guild's line didn't list the realm it names: %s" % [book.shown]
	return ""


## A species the player has seen (the bestiary, #1173) is listed under the bestiary's heading,
## after the lexicon, and the greeting's speaker under the people's, after it (#1005); then the
## realms' and, once the player has met Lumwen Hoal's name, as the greeting's third line shows it,
## the places' (#1175).
static func _see_a_species(main: Node, book: CodexBook) -> String:
	var bestiary: BestiaryKeeper = main.get_node("BestiaryKeeper") as BestiaryKeeper
	bestiary.learn("ombulumo", Bestiary.SEEN, "lumwen_hoal")
	(main.get_node("CodexKeeper") as CodexKeeper).meet(TextTags.PLACE, "lumwen_hoal")
	book.refresh()
	var rows: Array[String] = []
	for row: Node in book.get_node("Middle/Rows").get_children():
		rows.append(str(row.get("text")))
	if book.shown.get(TextTags.MONSTER, []) != ["ombulumo"]:
		return "the book listed %s after seeing Ombulumo" % [book.shown]
	var expected: Array[String] = [
		CodexPage.LEXICON_TEXT,
		"Amvrel Velmarai",
		CodexPage.BESTIARY_TEXT,
		"Ombulumo",
		CodexPage.PEOPLE_TEXT,
		"Teska na Amvrel",
		CodexPage.REALMS_TEXT,
		"Ardvaun",
		CodexPage.PLACES_TEXT,
		"Lumwen Hoal",
	]
	return "" if rows == expected else "the book showed %s" % [rows]


## With the menu open on the book, A on the guild's entry opens its page and B closes it; a click
## opens it and Escape closes it; a tap opens it and A on its close button closes it. Each time the
## menu stays open under it, the game hears no input, and the focus is back on the entry.
static func _open_from_book(
	tree: SceneTree,
	main: Node,
	driver: GameDriver,
	menu: GameMenu,
	book: CodexBook,
) -> String:
	var page: CodexPage = main.get_node("Hud/CodexPage") as CodexPage
	menu.toggle()
	(book.get_parent() as TabContainer).current_tab = book.get_index()
	await tree.process_frame
	await tree.process_frame
	var entry: Button = book.entry_button(TextTags.FACTION, GUILD)
	entry.grab_focus()
	FlowInput.press_pad(book, JOY_BUTTON_A)
	var problem: String = _closes_back(page, driver, menu, entry, _pad_closer(book, JOY_BUTTON_B))
	if not problem.is_empty():
		return "A, then B: " + problem
	var spot: Vector2 = entry.get_global_rect().get_center()
	FlowInput.tap(book, spot, InputEvent.DEVICE_ID_MOUSE)
	problem = _closes_back(page, driver, menu, entry, _escape.bind(book))
	if not problem.is_empty():
		return "a click, then Escape: " + problem
	FlowInput.tap(book, spot, InputEvent.DEVICE_ID_EMULATION)
	problem = _closes_back(page, driver, menu, entry, _pad_closer(book, JOY_BUTTON_A))
	if not problem.is_empty():
		return "a tap, then A on the close button: " + problem
	problem = _open_place(book, page)
	if not problem.is_empty():
		return problem
	menu.toggle()
	return "" if not driver.input.blocked else "the game still heard no input with the menu closed"


## Why the guild's page isn't open over the menu, or doesn't close back to the book's `entry` when
## `closing` runs, or "".
static func _closes_back(
	page: CodexPage,
	driver: GameDriver,
	menu: GameMenu,
	entry: Button,
	closing: Callable,
) -> String:
	if not page.is_open() or page.title.text != "Amvrel Velmarai" or not driver.input.blocked:
		return "the guild's page didn't open over the menu"
	closing.call()
	if page.is_open() or not menu.is_open() or not driver.input.blocked:
		return "the page didn't close back to the open menu"
	if entry.get_viewport().gui_get_focus_owner() != entry:
		return "the focus didn't go back to the entry"
	return ""


## A on Lumwen Hoal's entry opens its page (#1175): the place's name, what it means and its entry,
## with no standing; B closes it back to the entry.
static func _open_place(book: CodexBook, page: CodexPage) -> String:
	var entry: Button = book.entry_button(TextTags.PLACE, "lumwen_hoal")
	entry.grab_focus()
	FlowInput.press_pad(book, JOY_BUTTON_A)
	var gloss: String = page.gloss.get_parsed_text()
	if (not page.is_open()
			or page.heading.text != CodexPage.PLACES_TEXT
			or page.title.text != "Lumwen Hoal"
			or gloss != "Lumwen Hoal: the soft clearing"
			or page.entry.text.is_empty()
			or page.standing.visible):
		return "Lumwen Hoal's entry opened %s, %s" % [page.title.text, gloss]
	FlowInput.press_pad(book, JOY_BUTTON_B)
	if page.is_open() or entry.get_viewport().gui_get_focus_owner() != entry:
		return "B didn't close Lumwen Hoal's page back to its entry"
	return ""


## A new session in Lumwen Hoal (#1175): its first ticks meet the place and its realm, Ardvaun.
## The runner puts its own starting instance back after.
static func _enter_a_place(tree: SceneTree) -> String:
	GameDriver.start_instance = FlowSteps.GLADE
	var main: Node = await FlowGame.start(tree, ENTERING_PROFILE)
	var driver: GameDriver = FlowGame.held_driver(main)
	var keeper: CodexKeeper = main.get_node("CodexKeeper") as CodexKeeper
	driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	await tree.process_frame
	driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	var result: String = ""
	if not keeper.has_met(TextTags.PLACE, FlowSteps.GLADE):
		result = "entering Lumwen Hoal didn't meet it"
	elif keeper.met_ids(TextTags.REALM) != ["ardvaun"]:
		result = "entering Lumwen Hoal met the realms %s" % [keeper.met_ids(TextTags.REALM)]
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(ENTERING_PROFILE)
	return result


## The guild stays met in the profile's file: a new session's keeper reads it from there.
static func _kept_in_profile(main: Node) -> String:
	FlowGame.holder(main).flush()
	var fresh: CodexKeeper = CodexKeeper.new()
	var profile: Profile = ProfileStore.load_from(PROFILE, [fresh])
	var met: bool = fresh.has_met(TextTags.FACTION, GUILD)
	fresh.free()
	if not profile.problem.is_empty() or not met:
		return "the profile's file didn't keep the guild met: " + profile.problem
	return ""


## Names met under a kind without a codex page, or with an id that isn't one or is there twice,
## are refused; a save from before the book starts with none met.
static func _refuse_malformed() -> String:
	var keeper: CodexKeeper = CodexKeeper.new()
	var bad: Array[Variant] = [
		null,
		{ TextTags.GEAR: [GUILD] },
		{ TextTags.FACTION: GUILD },
		{ TextTags.FACTION: ["Amvrel Velmarai"] },
		{ TextTags.FACTION: [GUILD, GUILD] },
	]
	var result: String = ""
	for met: Variant in bad:
		if keeper.read({ CodexKeeper.KEY: met }).is_empty():
			result = "names met %s were read" % [met]
	var older: Dictionary = {}
	keeper.migrate(older, ProfileSave.FORMAT - 1)
	if result.is_empty() and (not keeper.read(older).is_empty() or not keeper.met.is_empty()):
		result = "an older save didn't start with no names met"
	keeper.free()
	return result


## A Callable that presses the controller's `button`.
static func _pad_closer(book: CodexBook, button: JoyButton) -> Callable:
	return FlowInput.press_pad.bind(book, button)


static func _escape(book: CodexBook) -> void:
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	book.get_viewport().push_input(cancel)
