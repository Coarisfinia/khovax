extends RefCounted
## Quest flow (#184): quests advance from what this machine's player obtains. A fresh profile has
## the first domination open, asking for the beach of the starting instance first (#321); another
## player's domination leaves it so, and this player's domination, through the event bus, finishes
## it; its progress is on disk at once and survives loading. A chest counts for the player who
## got loot from it. Steps count up and hand over to the next, one fact at a time, and only what a
## step asks for counts toward it. Quests finished together are listed in id order;
## saved progress that no longer fits its quest settles at the next fact; and quest data with a
## broken file advances no quest at all. Every open quest has a marker over the nearest thing it
## asks for (#300), and a finished one has none. The list at the side of the screen (#340) shows
## each open quest's step and count, follows a step counting up, and drops a finished quest once
## it has faded out; the menu's Quests tab (#388) shows the same quests with every step, done,
## current or later. A player stepping into a place from outside it raises that the place was
## reached, for that player only (#339); it finishes this player's quest to reach it, not another
## player's arrival, and the quest's marker points at the place's nearest tile. In the glade, a
## player raises that they entered each region piece they come to stand in, once each time it
## changes, starting in one too (#350); entering the thicket finishes this player's quest to enter
## it, not another player's, and the quest's marker points at the thicket's nearest tile. Entering
## the glade finishes this player's quest to enter it, not another player's or another instance,
## and its marker points at the exit leading there (#370). A side quest stays hidden until this
## player enters the area it starts in, and is listed from then on (#473). Finishing a quest moves
## the standing with the faction it names, held on the scale (#532): the first domination raises
## the Cartographer's Guild by one, saved with the profile, and a quest naming a faction that
## doesn't exist is refused; finishing a path-marked quest leans the player toward its path
## (#658). A quest chain with a choice (#573) marks every way on, goes on by the
## one this player takes, keeps the way taken through saving and loading, and ends where that way
## ends, moving its standing there too. The way taken and the chain's end emit events (#575), each
## starting the side quests waiting on it, and so does an event that changed the world (#707),
## also one the world already had as the session started (#756): it starts the side quest waiting
## on it, but none already started or done again.
## Choosing an answer in a dialog finishes this player's quest asking for it, not another player's
## choice nor another answer, and takes the way on of a choice asking for it (#636); a quest naming
## a dialog or an answer that no dialog file has is refused, and one that names an existing answer
## words it as the dialog does.
## Finishing a territory quest hands its instance to its faction in the world (#638). A step asking
## for an item counts each one this player obtains (#686), one gain finishing a step and counting on
## toward the next, and has no marker; one asking for an item no loot or harvest table drops is
## refused (#766). A region's legend can mark one wild monster as a quest target (#625): a quest
## asking for it is marked over that one monster, not over another of its species, and only
## dominating it counts.

const SAVE_PATH: String = "user://test_quest_profile.json"
## A quest with two steps, for the counting: two Ombulumo, then a chest.
const TWO_STEPS: String = (
	"{\"id\": \"toads_then_chest\", \"name\": \"Two toads, then a chest\", \"steps\": ["
	+ "{\"condition\": \"dominated\", \"species\": \"ombulumo\", \"count\": 2}, "
	+ "{\"condition\": \"opened\", \"ends\": \"toads_then_chest\"}]}"
)
## A quest that asks to enter the glade's thicket.
const ENTER_THICKET: String = (
	"{\"id\": \"enter_thicket\", \"name\": \"Into the thicket\", \"steps\": ["
	+ "{\"condition\": \"entered\", \"piece\": \"thicket\", \"ends\": \"enter_thicket\"}]}"
)
## A quest that asks to enter the glade.
const ENTER_GLADE: String = (
	"{\"id\": \"enter_glade\", \"name\": \"Into the glade\", \"steps\": ["
	+ "{\"condition\": \"entered\", \"instance\": \"glade\", \"ends\": \"enter_glade\"}]}"
)
## A quest that asks to reach the beach.
const REACH_BEACH: String = (
	"{\"id\": \"reach_beach\", \"name\": \"Go to the beach\", \"steps\": ["
	+ "{\"condition\": \"reached\", \"place\": \"beach\", \"ends\": \"reach_beach\"}]}"
)
## The dialog the answered steps ask about (#636).
const SCOUT: String = "guild_scout_greeting"
## A quest that asks to promise the scout to look at the glade, in the scout's dialog; its dialog
## and answer are left open.
const PROMISE: String = (
	"{\"id\": \"promise\", \"name\": \"A promise\", \"steps\": [{\"condition\": \"answered\", "
	+ "\"dialog\": \"%s\", \"answer\": \"%s\", \"ends\": \"promise\"}]}"
)
## A side quest that starts once the glade is purified (#707), a world event, not a quest's.
const AFTER_PURIFIED: String = (
	"{\"id\": \"after_purified\", \"name\": \"After the glade\", "
	+ "\"starts_on\": {\"condition\": \"emitted\", \"event\": \"glade_purified\"}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"after_purified\"}]}"
)
## A side quest that starts once the beacon is lit (#756).
const AFTER_BEACON: String = (
	"{\"id\": \"after_beacon\", \"name\": \"After the beacon\", "
	+ "\"starts_on\": {\"condition\": \"emitted\", \"event\": \"beacon_lit\"}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"after_beacon\"}]}"
)
## A quest whose chest turns the player against the Cartographer's Guild, further than its scale.
const BETRAYAL: String = (
	"{\"id\": \"betrayal\", \"name\": \"Betray the guild\", "
	+ "\"standing\": {\"faction\": \"cartographers_guild\", \"change\": -10}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"betrayal\"}]}"
)
## A quest asking for feathers twice over (#686): five, then three more.
const FEATHERS: String = (
	"{\"id\": \"feathers\", \"name\": \"Feathers\", \"steps\": ["
	+ "{\"condition\": \"obtained\", \"item\": \"feather\", \"count\": 5}, "
	+ "{\"condition\": \"obtained\", \"item\": \"feather\", \"count\": 3, "
	+ "\"ends\": \"feathers\"}]}"
)
## A quest's standing with a faction that doesn't exist.
const STRANGER_STANDING: String = "\"standing\": {\"faction\": \"strangers\", \"change\": 1}"
## The faction whose standing the first domination raises (#532).
const GUILD: String = "cartographers_guild"
## A small region with the beach on its east, `🐚`; players 1 and 2 start west of it.
const BEACH_REGION: String = (
	"# Beach\n\n## Tiles\n\n```\n 🟫🟫🐚🐚\n🟫🔴🔵🟫🐚\n 🟫🟫🐚🐚\n```\n\n## Legend\n\n"
	+ "- `🟫`: ground\n- `🔴`: where player 1 starts\n- `🔵`: where player 2 starts\n"
	+ "- `🐚`: the beach; stepping here reaches the place beach\n"
)
## A region whose legend marks one Ombulumo, wounded on sand, as the quest target old_toad (#625),
## east of player 1, and another Ombulumo, next to player 1, as none.
const TARGET_REGION: String = (
	"# Pond\n\n## Tiles\n\n```\n 🟫🟫🟫🟫\n🔴🐸🟫🟫🎯\n 🟫🟫🟫🟫\n```\n\n## Legend\n\n"
	+ "- `🟫`: ground\n- `🔴`: where player 1 starts\n- `🐸`: a wild monster, always ombulumo\n"
	+ "- `🎯`: a wild monster, always ombulumo, wounded, the quest target old_toad, on sand\n"
)
## A quest that asks to dominate the quest target old_toad.
const OLD_TOAD: String = (
	"{\"id\": \"old_toad\", \"name\": \"The old toad\", \"steps\": ["
	+ "{\"condition\": \"dominated\", \"target\": \"old_toad\", \"ends\": \"old_toad\"}]}"
)


func run(tree: SceneTree) -> String:
	var result: String = _check_counted()
	if result.is_empty():
		result = _check_settled()
	if result.is_empty():
		result = _check_broken_data()
	if result.is_empty():
		result = _check_places()
	if result.is_empty():
		result = _check_pieces()
	if result.is_empty():
		result = _check_side_quest()
	if result.is_empty():
		result = _check_branching()
	if result.is_empty():
		result = _check_obtained()
	result = result if not result.is_empty() else _check_target()
	if result.is_empty():
		result = await _check_tracked(tree)
	SaveStore.remove(SAVE_PATH)
	return result


## Through the main scene: the first domination asks for the beach, then a domination (#321); only
## this player's domination, handed out by the bus, finishes it, and it's saved and loads back; a
## chest counts for whoever got loot from it.
func _check_tracked(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree, SAVE_PATH)
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	var bus: EventBus = main.get_node("EventBus") as EventBus
	var profile: Profile = holder.keeper.profile
	var result: String = ""
	if not profile.quests.book.has("first_domination") or not profile.quests.finished.is_empty():
		result = "a fresh profile doesn't have the first domination open"
	var markers: QuestMarkerView = main.get_node("Instance/QuestMarkerView") as QuestMarkerView
	var list: QuestListView = main.get_node("Hud/QuestList") as QuestListView
	if result.is_empty():
		result = _check_beach_first(driver, bus, profile, markers, list)
	_emit(driver, bus, WildMonsterDominated.new(90, 9, 1, Vector2i.ZERO, "ombulumo"))
	if result.is_empty() and not profile.quests.finished.is_empty():
		result = "another slot's domination finished this player's quest"
	_emit(driver, bus, WildMonsterDominated.new(91, 1, 0, Vector2i.ZERO, "tikazzir"))
	# Reaching the beach was the gain saved at once; the domination right after it waits for the
	# debounce (ProfileKeeper.SAVE_INTERVAL_MSEC), so it's flushed as ending the session would.
	result += holder.keeper.flush()
	var expected: Array[String] = ["first_domination"]
	var loaded: Profile = ProfileStore.load_from(SAVE_PATH)
	if (result.is_empty()
			and (profile.quests.finished != expected or loaded.quests.finished != expected)):
		result = "this player's domination didn't finish the first domination on disk"
	if result.is_empty() and loaded.standings.of(GUILD) != 1:
		result = "finishing the first domination didn't raise the guild on disk (#532)"
	markers.show_quests()
	if result.is_empty() and markers.markers.has("first_domination"):
		result = "the finished first domination still has a marker"
	if result.is_empty():
		result = await _check_list_follows(tree, driver, bus, list)
	if result.is_empty():
		result = _check_finds(driver, bus, profile, list)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## This player dominating the quest target old_toad (#625), handed out by the bus, finishes the
## quest asking for it.
func _check_target_tracked(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	profile.quests.book["old_toad"] = QuestDefinition.parse("old_toad", OLD_TOAD, {})
	var dominated: WildMonsterDominated = WildMonsterDominated.new(
		93,
		1,
		0,
		Vector2i.ZERO,
		"ombulumo",
	)
	dominated.target = "old_toad"
	_emit(driver, bus, dominated)
	if not profile.quests.finished.has("old_toad"):
		return "this player dominating the quest target old_toad didn't finish its quest"
	return ""


## The fresh first domination asks for the beach: it's marked there and listed as going there;
## once this player reaches it, it asks for a domination, marked over the nearest wild monster.
func _check_beach_first(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	markers: QuestMarkerView,
	list: QuestListView,
) -> String:
	var result: String = _check_marked(driver, markers, profile)
	if result.is_empty():
		result = _check_listed(list, {
			"first_domination": "Go to the beach",
			"three_ombulumo": "Dominate an Ombulumo  0/3",
		})
	if result.is_empty():
		result = _check_card_scene(list, profile.quests.book["first_domination"].shown_name())
	var menu: GameMenu = list.get_parent().get_node("GameMenu") as GameMenu
	if result.is_empty():
		result = _check_quests_tab(menu, profile, "Now: Go to the beach\nLater: Dominate a monster")
	_emit(driver, bus, PlaceReached.new("beach", 1, 0))
	if result.is_empty():
		result = _check_marked_monster(driver, markers, profile)
	if result.is_empty():
		result = _check_listed(list, { "first_domination": "Dominate a monster" })
	if result.is_empty():
		result = _check_quests_tab(menu, profile, "Done: Go to the beach\nNow: Dominate a monster")
	return result


## The open first domination asks for the beach first (#321): it's marked over the beach's tile
## nearest to this player, the sand of the starting instance, and the markers follow the open
## quests.
func _check_marked(driver: GameDriver, markers: QuestMarkerView, profile: Profile) -> String:
	var state: GameState = driver.state
	var from: Vector2i = state.player(0).tile
	var nearest: int = -1
	for trigger: TileTrigger in state.region.triggers:
		var beach: bool = trigger.action == TileTrigger.REACH and trigger.place == "beach"
		# Sand, or sand with crates on it (#446).
		var kind: int = state.region.terrain[trigger.tile]
		var sand: bool = kind in [TileKinds.number_of("sand"), TileKinds.number_of("crates")]
		if beach and not sand:
			return "the starting instance's beach isn't sand"
		var distance: int = Hex.distance(trigger.tile, from)
		nearest = distance if beach and (nearest < 0 or distance < nearest) else nearest
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(state, profile.quests, 0)
	if (nearest < 0 or not targets.has("first_domination")
			or Hex.distance(targets["first_domination"], from) != nearest):
		return "the first domination isn't marked over the starting instance's nearest beach tile"
	markers.show_quests()
	if not markers.markers.has("first_domination"):
		return "the open first domination has no marker"
	return ""


## Once the beach is reached, the first domination is marked over the wild monster nearest to this
## player, and a quest asking for a species nobody here is has no marker.
func _check_marked_monster(
	driver: GameDriver,
	markers: QuestMarkerView,
	profile: Profile,
) -> String:
	var state: GameState = driver.state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null or wild.monsters.is_empty():
		return "the starting instance needs wild monsters to mark"
	var from: Vector2i = state.player(0).tile
	var nearest: int = Hex.distance(state.entity(wild.monsters[0]).tile, from)
	for entity_id: int in wild.monsters:
		nearest = mini(nearest, Hex.distance(state.entity(entity_id).tile, from))
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(state, profile.quests, 0)
	if (not targets.has("first_domination")
			or Hex.distance(targets["first_domination"], from) != nearest):
		return "after the beach, the first domination isn't marked over the nearest wild monster"
	markers.show_quests()
	if not markers.markers.has("first_domination"):
		return "the open first domination has no marker after the beach"
	return _check_unmarked(state, wild, profile)


## A quest asking for a species is marked only when one of that species is here.
func _check_unmarked(state: GameState, wild: WildMonsterFeature, profile: Profile) -> String:
	var text: String = "{\"id\": \"absent\", \"name\": \"Absent\", \"steps\": "
	text += "[{\"condition\": \"dominated\", \"species\": \"tikazzir\", \"ends\": \"absent\"}]}"
	var known: Dictionary[String, Species] = SpeciesContent.load_species().species
	var absent: QuestDefinition = QuestDefinition.parse("absent", text, known)
	profile.quests.book[absent.id] = absent
	var any_finch: bool = false
	for entity_id: int in wild.monsters:
		any_finch = any_finch or wild.species_of(entity_id) == "tikazzir"
	var marked: bool = QuestTargets.of(state, profile.quests, 0).has("absent")
	var _dropped: bool = profile.quests.book.erase("absent")
	if marked != any_finch:
		return "a quest is marked although nothing it asks for is here, or the other way round"
	return ""


## The list shows each of `expected`'s quests with the line under its name, by quest id.
func _check_listed(list: QuestListView, expected: Dictionary[String, String]) -> String:
	list.show_quests()
	for id: String in expected:
		if list.shown.get(id, "") != expected[id] or not list.cards.has(id):
			return "the quest list shows %s for %s, not %s" % [list.shown.get(id), id, expected[id]]
	return ""


## Laid out in scenes (#437): the list and its cards let touches through to the world, and the
## first domination's card has its name above its step, both wrapping.
func _check_card_scene(list: QuestListView, quest_name: String) -> String:
	var card: PanelContainer = list.cards["first_domination"]
	var name_label: Label = card.get_node("Lines/Name") as Label
	var step: Label = card.get_node("Lines/Step") as Label
	if (list.mouse_filter != Control.MOUSE_FILTER_IGNORE
			or card.mouse_filter != Control.MOUSE_FILTER_IGNORE
			or name_label.get_index() != 0 or name_label.text != quest_name
			or name_label.autowrap_mode != TextServer.AUTOWRAP_WORD_SMART
			or step.autowrap_mode != TextServer.AUTOWRAP_WORD_SMART):
		return "the quest list's scenes don't lay out a card as its name above its step"
	return ""


## The menu's Quests tab lists every open quest with all its steps, each worded and marked done,
## now or later in words: the first domination's as `first` says, and quests to enter a region piece
## and an instance, which it's given for a moment.
func _check_quests_tab(menu: GameMenu, profile: Profile, first: String) -> String:
	var entered: Dictionary[String, String] = {
		"enter_thicket": ENTER_THICKET,
		"enter_glade": ENTER_GLADE,
	}
	for id: String in entered:
		profile.quests.book[id] = QuestDefinition.parse(id, entered[id], {})
	menu.quests_tab().refresh()
	var expected: Dictionary[String, String] = {
		"enter_glade": "Now: Enter the glade",
		"enter_thicket": "Now: Enter the thicket",
		"first_domination": first,
		"three_ombulumo": "Now: Dominate an Ombulumo  0/3",
	}
	var shown: Dictionary[String, String] = menu.quests_tab().shown
	# Laid out in its scene (#437): it scrolls only up and down.
	if menu.quests_tab().horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return "the Quests tab's scene scrolls sideways"
	for id: String in entered:
		var _unbooked: bool = profile.quests.book.erase(id)
	if shown != expected:
		return "the Quests tab shows %s, not %s" % [shown, expected]
	return ""


## The finished first domination's card fades out and is gone; the open toads' quest stays.
func _check_dropped(tree: SceneTree, list: QuestListView) -> String:
	var fading: float = QuestListView.DONE_SECONDS + QuestListView.FADE_SECONDS
	await tree.create_timer(fading + 0.2).timeout
	list.show_quests()
	if list.cards.has("first_domination") or list.order.has("first_domination"):
		return "the finished first domination stayed on the quest list"
	if not list.cards.has("three_ombulumo"):
		return "an open quest left the quest list"
	return ""


## The list follows: another Ombulumo counts the toads' quest up, the finished first domination
## shows done and then drops out.
func _check_list_follows(
	tree: SceneTree,
	driver: GameDriver,
	bus: EventBus,
	list: QuestListView,
) -> String:
	_emit(driver, bus, WildMonsterDominated.new(92, 1, 0, Vector2i.ZERO, "ombulumo"))
	var result: String = _check_listed(list, {
		"first_domination": QuestListView.DONE_TEXT,
		"three_ombulumo": "Dominate an Ombulumo  1/3",
	})
	if result.is_empty():
		result = await _check_dropped(tree, list)
	return result


## Chests, places, region pieces and instances count for whoever opened, reached or entered them;
## the pond's side quest (#473) is listed once this player entered the pond, not before.
func _check_finds(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	list: QuestListView,
) -> String:
	var result: String = _check_chests(driver, bus, profile, list)
	if result.is_empty():
		result = _check_reached(driver, bus, profile)
	list.show_quests()
	if result.is_empty() and list.cards.has("pond_chest"):
		result = "the pond's side quest is listed before this player entered the pond"
	if result.is_empty():
		result = _check_entered(driver, bus, profile)
	if result.is_empty():
		result = _check_listed(list, { "pond_chest": "Open a chest" })
	if result.is_empty():
		result = _check_entered_glade(driver, bus, profile)
	if result.is_empty():
		result = _check_answered(driver, bus, profile)
	if result.is_empty():
		result = _check_territory(driver, bus, profile)
	return result if not result.is_empty() else _check_world_event(driver, bus, profile)


## A chest counts for this player when they got loot from it, not when only another player did,
## and the list asks to open one meanwhile.
func _check_chests(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	list: QuestListView,
) -> String:
	var text: String = "{\"id\": \"open_one\", \"name\": \"Open a chest\", "
	text += "\"steps\": [{\"condition\": \"opened\", \"ends\": \"open_one\"}]}"
	var chest: QuestDefinition = QuestDefinition.parse("open_one", text, {})
	profile.quests.book[chest.id] = chest
	var listed: String = _check_listed(list, { "open_one": "Open a chest" })
	if not listed.is_empty():
		return listed
	var others: Dictionary[int, Dictionary] = { 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 9, others))
	if profile.quests.finished.has("open_one"):
		return "another player's loot counted as this player's chest"
	var mine: Dictionary[int, Dictionary] = { 0: { }, 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 1, mine))
	if not profile.quests.finished.has("open_one"):
		return "a chest this player got their roll from didn't count"
	return ""


## Reaching the beach counts for this player when they reached it, not when another player did.
func _check_reached(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var beach: QuestDefinition = QuestDefinition.parse("reach_beach", REACH_BEACH, {})
	profile.quests.book[beach.id] = beach
	_emit(driver, bus, PlaceReached.new("beach", 9, 1))
	_emit(driver, bus, PlaceReached.new("pond", 1, 0))
	if profile.quests.finished.has("reach_beach"):
		return "another player's arrival, or another place, counted as reaching the beach"
	_emit(driver, bus, PlaceReached.new("beach", 1, 0))
	if not profile.quests.finished.has("reach_beach"):
		return "this player reaching the beach didn't finish the quest to reach it"
	return ""


## Entering the thicket counts for this player when they entered it, not when another player did.
func _check_entered(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var thicket: QuestDefinition = QuestDefinition.parse("enter_thicket", ENTER_THICKET, {})
	profile.quests.book[thicket.id] = thicket
	_emit(driver, bus, PieceEntered.new("thicket", 9, 1))
	_emit(driver, bus, PieceEntered.new("pond", 1, 0))
	if profile.quests.finished.has("enter_thicket"):
		return "another player entering, or another piece, counted as entering the thicket"
	_emit(driver, bus, PieceEntered.new("thicket", 1, 0))
	if not profile.quests.finished.has("enter_thicket"):
		return "this player entering the thicket didn't finish the quest to enter it"
	return ""


## The quest to enter the glade is marked on the forest's nearest exit leading there, and counts
## for this player when they entered the glade, not when another player did, nor for another
## instance, nor for a piece of the same name.
func _check_entered_glade(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var glade: QuestDefinition = QuestDefinition.parse("enter_glade", ENTER_GLADE, {})
	profile.quests.book[glade.id] = glade
	var forest: GameState = InstanceBlueprints.create(InstanceBlueprints.FOREST, 3, 1)
	var ways: Array[Vector2i] = []
	for i: int in forest.region.exits.size():
		if forest.region.exit_blueprints[i] == "glade":
			ways.append(Vector2i(forest.region.exits[i].x, forest.region.exits[i].y))
	var from: Vector2i = forest.player(0).tile
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(forest, profile.quests, 0)
	var target: Vector2i = targets.get("enter_glade", -Vector2i.ONE)
	if not ways.has(target) or Hex.distance(target, from) != _nearest(ways, from):
		return "the quest to enter the glade isn't marked on the nearest exit leading there"
	_emit(driver, bus, InstanceEntered.new("glade", 9, 1))
	_emit(driver, bus, InstanceEntered.new("basic", 1, 0))
	_emit(driver, bus, PieceEntered.new("glade", 1, 0))
	if profile.quests.finished.has("enter_glade"):
		return "another player entering, another instance or a piece counted as entering the glade"
	_emit(driver, bus, InstanceEntered.new("glade", 1, 0))
	if not profile.quests.finished.has("enter_glade"):
		return "this player entering the glade didn't finish the quest to enter it"
	return ""


## Promising the scout to look counts for this player when they chose that answer, not when another
## player did, nor for another answer of the same dialog (#636). Then a quest target (#625).
func _check_answered(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var promise: QuestDefinition = QuestDefinition.parse(
		"promise",
		PROMISE % [SCOUT, "promise_to_look"],
		{},
	)
	profile.quests.book[promise.id] = promise
	_emit(driver, bus, DialogAnswered.new(SCOUT, "promise_to_look", 9, 1))
	_emit(driver, bus, DialogAnswered.new(SCOUT, "leave_scout", 1, 0))
	if not promise.problem.is_empty() or profile.quests.finished.has("promise"):
		return "another player's or another answer counted as the promise: " + promise.problem
	_emit(driver, bus, DialogAnswered.new(SCOUT, "promise_to_look", 1, 0))
	if not profile.quests.finished.has("promise"):
		return "this player promising the scout didn't finish the quest asking for it"
	return _check_target_tracked(driver, bus, profile)


## Finishing a territory quest hands its instance to its faction (#638): the forest's, once this
## player walked its stream, grove and felling, not when another player entered the last one, nor
## when this player entered a felling in another instance, since its steps count only in the
## forest (#769); meanwhile its marker in the glade points at an exit leading there. The
## hand-over waits in the profile's outbox (#771) and goes in this player's next command, which the
## replay records, and the world clears the forest's old holder in the same tick as it hands the
## forest to the guild. The world records the request applied and acknowledges it, and the outbox
## drops it; the same request sent again, as at the start of a session after a crash, is
## acknowledged but not handed over twice.
func _check_territory(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var forest: String = InstanceBlueprints.FOREST
	var quest: String = "guild_charts_the_forest"
	driver.world.set_flag(Territory.flag(forest, "rivals"))
	_emit(driver, bus, InstanceEntered.new(forest, 1, 0))
	_emit_in(driver, bus, PieceEntered.new("stream", 1, 0), forest)
	_emit_in(driver, bus, PieceEntered.new("grove", 1, 0), forest)
	_emit_in(driver, bus, PieceEntered.new("felling", 9, 1), forest)
	_emit_in(driver, bus, PieceEntered.new("felling", 1, 0), InstanceBlueprints.GLADE)
	_emit(driver, bus, PieceEntered.new("felling", 1, 0))
	if (profile.quests.finished.has(quest)
			or Territory.holder(driver.world.flags, forest) != "rivals"):
		return "another player, or this one outside the forest, finished its territory quest"
	var marked: String = _check_territory_marked(profile, quest)
	if not marked.is_empty():
		return marked
	_emit_in(driver, bus, PieceEntered.new("felling", 1, 0), forest)
	if profile.outbox.entries.size() != 1:
		return "finishing the forest's territory quest didn't post its hand-over to the outbox"
	var request: OutboxEntry = profile.outbox.entries[0]
	_tick(driver, bus)
	var held: Array[String] = []
	for flag: String in driver.world.flags:
		if flag.begins_with(Territory.flag(forest, "")):
			held.append(flag)
	var to_guild: bool = held.size() == 1 and held[0] == Territory.flag(forest, GUILD)
	if not profile.quests.finished.has(quest) or not to_guild:
		return "finishing the forest's territory quest left its holders at %s" % [held]
	if not driver.recording.changes.has(Territory.code(forest, GUILD)):
		return "the replay didn't record the forest handed over"
	return _check_territory_resent(driver, bus, profile, request)


## Why the territory quest `quest`, open in `profile`, isn't marked in the glade on an exit leading
## to the forest it counts in (#769), or "".
func _check_territory_marked(profile: Profile, quest: String) -> String:
	var glade: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 3, 1)
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(
		glade,
		profile.quests,
		0,
		InstanceBlueprints.GLADE,
	)
	var marked: Vector2i = targets.get(quest, -Vector2i.ONE)
	for i: int in glade.region.exits.size():
		if Vector2i(glade.region.exits[i].x, glade.region.exits[i].y) == marked:
			if glade.region.exit_blueprints[i] == InstanceBlueprints.FOREST:
				return ""
	return "the forest's territory quest isn't marked on an exit from the glade leading there"


## The territory quest's hand-over `request`, applied and acknowledged, is out of the outbox and
## recorded as applied; sent again, it's acknowledged once more but not handed over twice, so the
## forest stays with the holder it has meanwhile.
func _check_territory_resent(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	request: OutboxEntry,
) -> String:
	var forest: String = InstanceBlueprints.FOREST
	var applied: Array = driver.world.stored(0, TerritoryFeature.ID).get(OutboxReceipts.APPLIED, [])
	if not profile.outbox.entries.is_empty() or applied != [request.id]:
		return "the applied hand-over stayed in the outbox, or wasn't recorded: %s" % [applied]
	driver.world.set_flag(Territory.flag(forest, GUILD), false)
	driver.world.set_flag(Territory.flag(forest, "rivals"))
	var acknowledged: Array = []
	var heard: Callable = func(event: RequestApplied) -> void: acknowledged.append(event.request)
	bus.subscribe(RequestApplied, heard)
	driver.input.send(request)
	_tick(driver, bus)
	if Territory.holder(driver.world.flags, forest) != "rivals" or acknowledged != [request.id]:
		return "the hand-over sent again was handed over twice, or not acknowledged"
	return ""


## Runs a few ticks and hands their events out.
func _tick(driver: GameDriver, bus: EventBus) -> void:
	for _step: int in 3:
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	bus.flush()


## An event that changed the world (#707) reaches this player's profile, wherever they are, and
## starts the side quest waiting on it; another world event doesn't.
func _check_world_event(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var waiting: QuestDefinition = QuestDefinition.parse("after_purified", AFTER_PURIFIED, {})
	profile.quests.book[waiting.id] = waiting
	_emit(driver, bus, WorldChanged.new("glade_corrupted", World.EVENT_FLAG + "glade_corrupted"))
	if profile.quests.open_steps().has(waiting.id):
		return "another world event started the side quest waiting on the glade's purifying"
	_emit(driver, bus, WorldChanged.new("glade_purified", World.EVENT_FLAG + "glade_purified"))
	if not profile.quests.open_steps().has(waiting.id):
		return "the glade's purifying didn't start the side quest waiting on it"
	return _check_caught_up(driver.holder, profile)


## As a session starts, the profile gains the events that already changed the world (#756), from
## its flags, and no other flag: the beacon lit before starts the side quest waiting on it, while
## the side quest the glade's purifying started already keeps its progress and one done stays done.
func _check_caught_up(holder: ProfileHolder, profile: Profile) -> String:
	var lit: QuestDefinition = QuestDefinition.parse("after_beacon", AFTER_BEACON, {})
	profile.quests.book[lit.id] = lit
	profile.quests.finished.append("after_done")
	var done: QuestDefinition = QuestDefinition.parse("after_beacon", AFTER_BEACON, {})
	done.id = "after_done"
	profile.quests.book[done.id] = done
	var purified: QuestProgress = profile.quests.progress["after_purified"]
	var flags: Array[String] = [
		World.EVENT_FLAG + "beacon_lit",
		World.EVENT_FLAG + "glade_purified",
		"TERRITORY_after_beacon",
	]
	holder.catch_up(flags)
	var result: String = ""
	if not profile.quests.open_steps().has(lit.id):
		result = "catching up with the world's events didn't start the side quest waiting on one"
	elif profile.quests.progress.has(done.id):
		result = "catching up with the world's events started a side quest already done again"
	elif profile.quests.progress["after_purified"] != purified:
		result = "catching up with the world's events started a side quest again"
	for id: String in [lit.id, done.id]:
		var _unbooked: bool = profile.quests.book.erase(id)
	profile.quests.finished.erase(done.id)
	return result


## On a region with a beach: player 1 walking onto it from outside raises that they reached it,
## walking on along it doesn't again, and player 2 stepping onto it raises it for player 2. The
## quest to reach the beach points at the beach tile nearest to player 1. A player arriving on the
## beach (through an exit, or starting there) reaches it too (#348).
func _check_places() -> String:
	var region: Region = RegionDocument.parse(BEACH_REGION)
	var ordered: Array[Feature] = [MovementFeature.new(), FogFeature.new(), TriggerFeature.new()]
	var state: GameState = GameState.new(region, 3, ordered)
	if not region.problem.is_empty() or not state.problem.is_empty():
		return "the beach region didn't read: " + region.problem + state.problem
	for slot: int in 2:
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	var profile: Profile = Profile.new()
	profile.quests.book["reach_beach"] = QuestDefinition.parse("reach_beach", REACH_BEACH, {})
	var result: String = _check_place_marker(state, profile)
	var east: int = Hex.DIRECTIONS.find(Vector2i(1, 0))
	var reached: Array[PlaceReached] = _reached(FlowSteps.step(state, east, 2))
	reached.append_array(_reached(FlowSteps.step(state, east, 2)))
	if result.is_empty() and not reached.is_empty():
		result = "walking on ground short of the beach reached it"
	reached = _reached(FlowSteps.step(state, east, 2))
	var reached_by_one: bool = reached.size() == 1 and reached[0].slot == 0
	if result.is_empty() and not (reached_by_one and reached[0].place == "beach"):
		result = "player 1 stepping onto the beach didn't reach it, once"
	reached = _reached(FlowSteps.step(state, Hex.DIRECTIONS.find(Vector2i(0, -1)), 2))
	if result.is_empty() and not reached.is_empty():
		result = "walking along the beach reached it again"
	reached = []
	for tick: int in MovementFeature.MOVE_TICKS:
		var south: int = Hex.DIRECTIONS.find(Vector2i(0, 1)) if tick == 0 else Command.NO_MOVE
		Simulation.step(state, FlowSteps.commands([Command.NO_MOVE, south]))
		reached.append_array(_reached(state.events))
	if result.is_empty() and (reached.size() != 1 or reached[0].slot != 1):
		result = "player 2 stepping onto the beach didn't reach it for player 2"
	return result if not result.is_empty() else _check_arrival(state)


## A player who appears on the beach, as they do arriving through an exit or starting there,
## reaches it on the next tick, once, and not again while they stay.
func _check_arrival(state: GameState) -> String:
	var _arrived: Entity = state.add_entity(2, state.region.triggers[0].tile)
	var stay: Array[int] = [Command.NO_MOVE, Command.NO_MOVE, Command.NO_MOVE]
	var still: Array[Command] = FlowSteps.commands(stay)
	Simulation.step(state, still)
	var reached: Array[PlaceReached] = _reached(state.events)
	if reached.size() != 1 or reached[0].slot != 2 or reached[0].place != "beach":
		return "a player arriving on the beach didn't reach it, once"
	Simulation.step(state, still)
	if not _reached(state.events).is_empty():
		return "a player staying on the beach reached it again"
	return ""


## The quest to reach the beach is marked on the beach tile nearest to player 1.
func _check_place_marker(state: GameState, profile: Profile) -> String:
	var from: Vector2i = state.player(0).tile
	var beach: Array[Vector2i] = []
	for trigger: TileTrigger in state.region.triggers:
		beach.append(trigger.tile)
	var target: Vector2i = QuestTargets.of(state, profile.quests, 0).get("reach_beach", from)
	if not beach.has(target) or Hex.distance(target, from) != _nearest(beach, from):
		return "the quest to reach the beach isn't marked on its nearest tile"
	return ""


## The region's quest target old_toad (#625) is its marked Ombulumo's, kept through a save, and
## not the other's, which is nearer the player.
func _check_target() -> String:
	var region: Region = RegionDocument.parse(TARGET_REGION)
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		TrailFeature.new(),
		WildMonsterFeature.new(),
	]
	var state: GameState = GameState.new(region, 3, ordered)
	if not region.problem.is_empty() or not state.problem.is_empty():
		return "the region with a quest target didn't read: " + region.problem + state.problem
	var _player: Entity = state.add_entity(0, region.starts[0])
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	wild.load_values(state, DataReader.new(wild.save_values()))
	var marked: Vector2i = Vector2i.ZERO
	var unmarked: int = 0
	for monster: int in wild.monsters:
		if wild.target_of(monster) == "old_toad":
			marked = state.entity(monster).tile
		elif wild.target_of(monster).is_empty():
			unmarked += 1
	if marked != Vector2i(2, 0) or unmarked != 1:
		return "the legend's quest target isn't the one Ombulumo it marks, after a save"
	return _check_target_quest(state, marked)


## The quest asking for old_toad is marked over it on `state`'s `marked` tile and listed as
## dominating it; dominating an Ombulumo leaves it open, and dominating the target finishes it.
func _check_target_quest(state: GameState, marked: Vector2i) -> String:
	var profile: Profile = Profile.new()
	profile.quests.book["old_toad"] = QuestDefinition.parse("old_toad", OLD_TOAD, {})
	var step: QuestStep = profile.quests.book["old_toad"].steps[0]
	if QuestTargets.of(state, profile.quests, 0).get("old_toad", Vector2i.ZERO) != marked:
		return "the quest asking for old_toad isn't marked over it"
	if QuestListView.step_line(step, 0) != "Dominate the old toad":
		return "the quest asking for old_toad reads %s" % QuestListView.step_line(step, 0)
	var applied: String = profile.apply(_gain(["ombulumo"], 0))
	if not applied.is_empty() or profile.quests.finished.has("old_toad"):
		return "dominating another Ombulumo counted toward old_toad: " + applied
	var targeted: Gain = _gain(["ombulumo"], 0)
	targeted.targets_dominated.append("old_toad")
	applied = profile.apply(targeted)
	var done: Array[String] = ["old_toad"]
	if not applied.is_empty() or profile.quests.finished != done:
		return "dominating old_toad didn't finish the quest asking for it: " + applied
	return ""


## In the glade: the player starting in the start piece enters it on the first tick, once. The
## quest to enter the thicket is marked on the thicket's nearest tile, and walking there enters
## every piece on the way, once each time the piece changes, ending in the thicket.
func _check_pieces() -> String:
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 3, 1)
	var still: Array[Command] = FlowSteps.commands([Command.NO_MOVE])
	Simulation.step(state, still)
	var entered: Array[String] = _pieces_entered(state.events)
	Simulation.step(state, still)
	entered.append_array(_pieces_entered(state.events))
	if entered.size() != 1 or entered[0] != "start":
		return "the player starting in the glade didn't enter its start piece, once"
	var profile: Profile = Profile.new()
	profile.quests.book["enter_thicket"] = QuestDefinition.parse("enter_thicket", ENTER_THICKET, {})
	var from: Vector2i = state.player(0).tile
	var thicket: Array[Vector2i] = []
	for tile: Vector2i in state.region.piece_of:
		if state.region.piece_of[tile] == "thicket":
			thicket.append(tile)
	var target: Vector2i = QuestTargets.of(state, profile.quests, 0).get("enter_thicket", from)
	if not thicket.has(target) or Hex.distance(target, from) != _nearest(thicket, from):
		return "the quest to enter the thicket isn't marked on its nearest tile"
	return _check_walk_into_thicket(state)


## Walking to the nearest walkable tile of the thicket enters each piece on the way once, in the
## order the walk comes to them, the thicket last.
func _check_walk_into_thicket(state: GameState) -> String:
	var from: Vector2i = state.player(0).tile
	var directions: Array[int] = []
	for tile: Vector2i in state.region.reachable(from):
		if state.region.piece_of[tile] == "thicket":
			directions = FlowSteps.shortest_path(state, from, tile)
		if not directions.is_empty():
			break
	if directions.is_empty():
		return "no walk leads from the glade's start into the thicket"
	var expected: Array[String] = []
	var walked: Vector2i = from
	var events: Array[RefCounted] = []
	for direction: int in directions:
		var piece: String = state.region.piece_of[walked + Hex.DIRECTIONS[direction]]
		if piece != state.region.piece_of[walked]:
			expected.append(piece)
		walked += Hex.DIRECTIONS[direction]
		events.append_array(FlowSteps.step(state, direction))
	var entered: Array[String] = _pieces_entered(events)
	if entered != expected or not entered.has("thicket"):
		return "walking into the thicket entered %s, not %s" % [entered, expected]
	return ""


## A side quest (#473) is hidden and counts nothing until this player enters the area it starts in:
## the pond's chest isn't open and a chest doesn't finish it, entering another piece doesn't start
## it, and entering the pond does, open at its first step, listed and on the Quests tab, through
## saving and loading; a chest then finishes it. One fact can start a side quest and count toward
## its first step.
func _check_side_quest() -> String:
	var profile: Profile = Profile.new()
	profile.quests.book = QuestContent.load_quests().quests
	var applied: String = profile.apply(_gain([], 1))
	applied += profile.apply(_entering("thicket"))
	if not applied.is_empty() or profile.quests.open_steps().has("pond_chest"):
		return "the pond's side quest started before the pond was entered: " + applied
	if profile.quests.finished.has("pond_chest") or profile.quests.progress.has("pond_chest"):
		return "a chest counted toward the pond's side quest before it started"
	applied = profile.apply(_entering("pond"))
	var loaded: Profile = ProfileSave.parse(ProfileSave.to_text(profile))
	loaded.quests.book = profile.quests.book
	var step: QuestStep = loaded.quests.open_steps().get("pond_chest")
	if (not applied.is_empty() or step == null
			or QuestsTab.quest_lines(loaded, "pond_chest") != ["Now: Open a chest"]):
		return "entering the pond didn't open its side quest, kept through loading: " + applied
	applied = loaded.apply(_gain([], 1))
	if not applied.is_empty() or not loaded.quests.finished.has("pond_chest"):
		return "a chest didn't finish the started pond side quest: " + applied
	var text: String = "{\"id\": \"in_one\", \"name\": \"N\", \"starts_on\": %s, \"steps\": [%s]}"
	var enter: String = "{\"condition\": \"entered\", \"piece\": \"pond\"}"
	var at_once: Profile = Profile.new()
	var ending: String = enter.replace("}", ", \"ends\": \"in_one\"}")
	at_once.quests.book["in_one"] = QuestDefinition.parse("in_one", text % [enter, ending], {})
	applied = at_once.apply(_entering("pond"))
	if not applied.is_empty() or at_once.quests.finished != ["in_one"]:
		return "entering the pond didn't both start and finish a side quest asking for it"
	return ""


## The glade's fork (#573): entering the glade starts it on its choice, listed as both ways on and
## marked over the pond and the thicket, each its nearest tile. Entering the thicket takes that way:
## the tab shows the way taken, done, then a domination, which ends the chain; the pond's chest
## never counts toward it. The pond's way, kept through saving and loading, ends at a chest.
func _check_branching() -> String:
	var book: Dictionary[String, QuestDefinition] = QuestContent.load_quests().quests
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 3, 1)
	var thicket: Profile = Profile.new()
	thicket.quests.book = book
	var entered: Gain = Gain.new()
	entered.instances_entered = ["glade"]
	var applied: String = thicket.apply(entered)
	var choosing: Array[String] = ["Now: Enter the pond or enter the thicket"]
	if not applied.is_empty() or QuestsTab.quest_lines(thicket, "glade_fork") != choosing:
		return "entering the glade didn't open its fork on its choice: %s" % [
			QuestsTab.quest_lines(thicket, "glade_fork"),
		]
	var result: String = _check_fork_marked(state, thicket)
	applied = thicket.apply(_entering("thicket"))
	var way: Array[String] = ["Done: Enter the thicket", "Now: Dominate a monster"]
	if result.is_empty() and QuestsTab.quest_lines(thicket, "glade_fork") != way:
		result = "the thicket's way isn't shown taken: %s" % [
			QuestsTab.quest_lines(thicket, "glade_fork"),
		]
	applied += thicket.apply(_gain([], 1))
	if result.is_empty() and thicket.quests.finished.has("glade_fork"):
		result = "the pond's chest counted on the thicket's way"
	applied += thicket.apply(_gain(["ombulumo"], 0))
	if (result.is_empty()
			and (not applied.is_empty() or not thicket.quests.finished.has("glade_fork"))):
		result = "a domination didn't end the thicket's way: " + applied
	return result if not result.is_empty() else _check_pond_way(book, entered)


## The glade's fork, on its choice, is marked over the pond's and the thicket's nearest tiles, one
## marker each, and not as a whole.
func _check_fork_marked(state: GameState, profile: Profile) -> String:
	var from: Vector2i = state.player(0).tile
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(state, profile.quests, 0)
	var pieces: Array[String] = ["pond", "thicket"]
	for index: int in pieces.size():
		var tiles: Array[Vector2i] = []
		for tile: Vector2i in state.region.piece_of:
			if state.region.piece_of[tile] == pieces[index]:
				tiles.append(tile)
		var target: Vector2i = targets.get("glade_fork/%d" % index, -Vector2i.ONE)
		if not tiles.has(target) or Hex.distance(target, from) != _nearest(tiles, from):
			return "the glade's fork isn't marked over the nearest tile of the %s" % pieces[index]
	if targets.has("glade_fork"):
		return "the glade's fork is marked as a whole besides its choices"
	return ""


## Entering the pond takes the pond's way, kept through saving and loading, and a chest ends it.
func _check_pond_way(book: Dictionary[String, QuestDefinition], entered: Gain) -> String:
	var pond: Profile = Profile.new()
	pond.quests.book = book
	var applied: String = pond.apply(entered) + pond.apply(_entering("pond"))
	var loaded: Profile = ProfileSave.parse(ProfileSave.to_text(pond))
	loaded.quests.book = book
	var way: Array[String] = ["Done: Enter the pond", "Now: Open a chest"]
	if not applied.is_empty() or QuestsTab.quest_lines(loaded, "glade_fork") != way:
		return "the pond's way wasn't kept through loading: %s" % [
			QuestsTab.quest_lines(loaded, "glade_fork"),
		]
	applied = loaded.apply(_gain([], 1))
	if not applied.is_empty() or not loaded.quests.finished.has("glade_fork"):
		return "a chest didn't end the pond's way: " + applied
	return _check_branch_standing()


## A chain that ends on the way chosen, past the other way's steps, moves the standing it names
## (#532) like any finished quest.
func _check_branch_standing() -> String:
	var text: String = "{\"id\": \"fork\", \"name\": \"N\", %s, \"steps\": [{\"choices\": ["
	text += "{\"condition\": \"entered\", \"piece\": \"pond\", \"next\": \"won\"}, "
	text += "{\"condition\": \"entered\", \"piece\": \"thicket\", \"next\": \"lost\"}]}, "
	text += "{\"id\": \"won\", \"condition\": \"opened\", \"ends\": \"fork\"}, "
	text += "{\"id\": \"lost\", \"condition\": \"dominated\", \"ends\": \"fork\"}]}"
	var profile: Profile = Profile.new()
	var standing: String = STRANGER_STANDING.replace("strangers", GUILD)
	profile.quests.book["fork"] = QuestDefinition.parse("fork", text % standing, {})
	var applied: String = profile.quests.book["fork"].problem
	applied += profile.apply(_entering("pond")) + profile.apply(_gain([], 1))
	if (not applied.is_empty() or profile.quests.finished != ["fork"]
			or profile.standings.of(GUILD) != 1):
		return "a chain ending on its chosen way didn't move its standing: " + applied
	return _check_emitted()


## Steps and choices emit events (#575): taking the thicket's way, which leads to the same end as
## the pond's, emits its own event, which starts the side quest waiting on it but not the one
## waiting on the pond's; the end emits its own, which starts another side quest only once the
## chain ends. A step can't wait on an event itself.
func _check_emitted() -> String:
	var text: String = "{\"id\": \"fork\", \"name\": \"N\", \"steps\": [{\"choices\": ["
	text += "{\"condition\": \"entered\", \"piece\": \"pond\", \"next\": \"won\", "
	text += "\"emits\": \"took_pond\"}, "
	text += "{\"condition\": \"entered\", \"piece\": \"thicket\", \"next\": \"won\", "
	text += "\"emits\": \"took_thicket\"}]}, "
	text += "{\"id\": \"won\", \"condition\": \"opened\", \"ends\": \"fork\", \"emits\": \"won\"}]}"
	var waiting: String = "{\"id\": \"%s\", \"name\": \"N\", "
	waiting += "\"starts_on\": {\"condition\": \"emitted\", \"event\": \"%s\"}, "
	waiting += "\"steps\": [{\"condition\": \"%s\", \"ends\": \"%s\"}]}"
	var starts: Dictionary[String, Array] = {
		"after_pond": ["took_pond", "opened"],
		"after_thicket": ["took_thicket", "opened"],
		"after_won": ["won", "dominated"],
	}
	var profile: Profile = Profile.new()
	profile.quests.book["fork"] = QuestDefinition.parse("fork", text, {})
	for id: String in starts:
		var side_text: String = waiting % ([id] + starts[id] + [id])
		profile.quests.book[id] = QuestDefinition.parse(id, side_text, {})
	var applied: String = ""
	for id: String in profile.quests.book:
		applied += profile.quests.book[id].problem
	applied += profile.apply(_entering("thicket"))
	if not applied.is_empty() or profile.quests.open_steps().keys() != ["after_thicket", "fork"]:
		return "taking the thicket's way didn't start just its side quest: " + applied
	applied = profile.apply(_gain([], 1))
	if not applied.is_empty() or profile.quests.open_steps().keys() != ["after_won"]:
		return "the chain's end didn't start the side quest waiting on it: " + applied
	applied = profile.apply(_gain(["ombulumo"], 0))
	if not applied.is_empty() or profile.quests.finished != ["after_thicket", "fork", "after_won"]:
		return "the side quests an event started didn't go on: %s" % profile.quests.finished
	var step_waits: String = text.replace("\"condition\": \"opened\"", "\"condition\": \"emitted\"")
	step_waits = step_waits.replace("\"ends\"", "\"event\": \"took_pond\", \"ends\"")
	if QuestDefinition.parse("fork", step_waits, {}).problem.is_empty():
		return "a step waiting on an event wasn't refused"
	return _check_answered_choice()


## A choice taken by an answer (#636): leaving the scout takes the way to a domination, past the
## chest that asking about the glade leads to, and the tab shows both ways as answers.
func _check_answered_choice() -> String:
	var choice: String = "{\"condition\": \"answered\", \"dialog\": \"%s\", " % SCOUT
	choice += "\"answer\": \"%s\", \"next\": \"%s\"}"
	var text: String = "{\"id\": \"fork\", \"name\": \"N\", \"steps\": [{\"choices\": "
	text += "[%s, %s]}, " % [
		choice % ["ask_about_glade", "won"],
		choice % ["leave_scout", "lost"],
	]
	text += "{\"id\": \"won\", \"condition\": \"opened\", \"ends\": \"fork\"}, "
	text += "{\"id\": \"lost\", \"condition\": \"dominated\", \"ends\": \"fork\"}]}"
	var profile: Profile = Profile.new()
	profile.quests.book["fork"] = QuestDefinition.parse("fork", text, {})
	var choosing: Array[String] = ["Now: Answer ask about glade or answer leave scout"]
	var applied: String = profile.quests.book["fork"].problem
	if not applied.is_empty() or QuestsTab.quest_lines(profile, "fork") != choosing:
		return "a choice between answers isn't shown as one: %s %s" % [
			applied,
			QuestsTab.quest_lines(profile, "fork"),
		]
	var left: Gain = Gain.new()
	left.answers_chosen = [QuestStep.answer_key(SCOUT, "leave_scout")]
	applied = profile.apply(left) + profile.apply(_gain([], 1))
	if not applied.is_empty() or not profile.quests.finished.is_empty():
		return "leaving the scout didn't take the way to a domination: " + applied
	applied = profile.apply(_gain(["ombulumo"], 0))
	if not applied.is_empty() or profile.quests.finished != ["fork"]:
		return "a domination didn't end the way leaving the scout took: " + applied
	return ""


## A step asking for feathers (#686) counts each feather obtained, not a bone, nor a chest opened
## that rolled none: three show 3/5, and four more finish it and count the two left over toward the
## next step. It has no marker, and an item is asked for only on an obtained step, and only one that
## a loot or harvest table drops (#766).
func _check_obtained() -> String:
	var profile: Profile = Profile.new()
	profile.quests.book["feathers"] = QuestDefinition.parse("feathers", FEATHERS, {})
	var applied: String = profile.quests.book["feathers"].problem
	applied += profile.apply(_gain([], 1)) + profile.apply(_obtaining({ "feather": 3, "bone": 1 }))
	if not applied.is_empty() or QuestsTab.quest_lines(profile, "feathers")[0] != (
		"Now: Collect feather  3/5"
	):
		return "three feathers didn't count three toward five: %s %s" % [
			applied,
			QuestsTab.quest_lines(profile, "feathers"),
		]
	applied = profile.apply(_obtaining({ "feather": 4 }))
	var lines: Array[String] = ["Done: Collect feather  5/5", "Now: Collect feather  2/3"]
	if not applied.is_empty() or QuestsTab.quest_lines(profile, "feathers") != lines:
		return "four more feathers didn't finish five and count on: %s" % [
			QuestsTab.quest_lines(profile, "feathers"),
		]
	if profile.materials.get("feather", 0) != 7:
		return "the feathers obtained weren't all kept: %s" % profile.materials
	var state: GameState = InstanceBlueprints.create(InstanceBlueprints.GLADE, 3, 1)
	if QuestTargets.of(state, profile.quests, 0).has("feathers"):
		return "a step asking for an item is marked in the world"
	var stray: String = FEATHERS.replace("\"condition\": \"obtained\"", "\"condition\": \"opened\"")
	if QuestDefinition.parse("feathers", stray, {}).problem.is_empty():
		return "a step naming an item without asking for it wasn't refused"
	var dropped: QuestData = _load_written({ "feathers": FEATHERS })
	var typo: QuestData = _load_written({ "feathers": FEATHERS.replace("feather\"", "feathre\"") })
	if not dropped.problem.is_empty() or not typo.problem.contains("drops the item feathre"):
		return "only an item no table drops should be refused: %s / %s" % [
			dropped.problem,
			typo.problem,
		]
	return ""


## A gain of this player obtaining `items`, {item id: amount}.
static func _obtaining(items: Dictionary[String, int]) -> Gain:
	var gain: Gain = Gain.new()
	gain.materials = items
	return gain


## A gain of this player entering the region piece `piece`.
static func _entering(piece: String) -> Gain:
	var gain: Gain = Gain.new()
	gain.pieces_entered = [piece]
	return gain


## How far the nearest of `tiles` is from `from`.
static func _nearest(tiles: Array[Vector2i], from: Vector2i) -> int:
	var nearest: int = Hex.distance(tiles[0], from)
	for tile: Vector2i in tiles:
		nearest = mini(nearest, Hex.distance(tile, from))
	return nearest


## The region pieces entered among `events`, in order, by the player in slot 0.
static func _pieces_entered(events: Array[RefCounted]) -> Array[String]:
	var pieces: Array[String] = []
	for event: RefCounted in events:
		if event is PieceEntered and (event as PieceEntered).slot == 0:
			pieces.append((event as PieceEntered).piece)
	return pieces


## The places reached among `events`.
static func _reached(events: Array[RefCounted]) -> Array[PlaceReached]:
	var reached: Array[PlaceReached] = []
	for event: RefCounted in events:
		if event is PlaceReached:
			reached.append(event as PlaceReached)
	return reached


## Raises `event` in a tick and has the bus hand it out at once.
func _emit(driver: GameDriver, bus: EventBus, event: RefCounted) -> void:
	var events: Array[RefCounted] = [event]
	driver.ticked.emit(driver.state.tick, events)
	bus.flush()


## Hands `event` to the bus as one the instance `instance_name` raised (#769), then flushes it.
func _emit_in(driver: GameDriver, bus: EventBus, event: RefCounted, instance_name: String) -> void:
	driver.world.instance(instance_name).events.append(event)
	_emit(driver, bus, event)


## Steps count up one fact at a time: only the species a step asks for counts, a step at its count
## hands over to the next even within one gain, and the last one finishes the quest. The toads'
## quest counts to three. The first domination asks for the beach first (#321): dominations before
## it don't count, and reaching it hands over to dominating.
func _check_counted() -> String:
	var content: QuestData = QuestContent.load_quests()
	var profile: Profile = Profile.new()
	profile.quests.book = content.quests
	var two: QuestDefinition = QuestDefinition.parse("toads_then_chest", TWO_STEPS, content.species)
	profile.quests.book[two.id] = two
	var at_beach: Gain = _gain(["tikazzir", "ombulumo"], 0)
	at_beach.places_reached = ["beach"]
	var applied: String = profile.apply(at_beach)
	var progress: QuestProgress = profile.quests.progress.get(two.id)
	var first: QuestProgress = profile.quests.progress.get("first_domination")
	var toads: QuestProgress = profile.quests.progress.get("three_ombulumo")
	if not applied.is_empty() or progress == null or progress.step != 0 or progress.count != 1:
		return "one Ombulumo didn't count one toward its step: " + applied
	if toads == null or toads.count != 1 or first == null or first.step != 1:
		return "the toads' quest didn't count up, or the beach didn't hand over to dominating"
	if not profile.quests.finished.is_empty() or profile.standings.of(GUILD) != 0:
		return "a domination before the beach finished the first domination"
	applied = profile.apply(_gain(["ombulumo", "ombulumo"], 1))
	if (not applied.is_empty()
			or profile.quests.finished != ["first_domination", "three_ombulumo", two.id]):
		return "a gain didn't hand a full step to the next one: %s" % profile.quests.finished
	if not profile.quests.progress.is_empty():
		return "finished quests kept their progress"
	var result: String = _check_standing(profile)
	return result if not result.is_empty() else _check_kept(profile.quests.book)


## Finishing a quest moves the standing with the faction it names (#532): the first domination
## raised the guild by one, and a quest lowering it further than its scale holds it at the lowest.
## Finishing a path-marked quest leans the player toward its path (#658): the toads' quest, marked
## supremacy, leans them one toward it, and the unmarked ones toward neither.
func _check_standing(profile: Profile) -> String:
	if profile.standings.of(GUILD) != 1:
		return "finishing the first domination didn't raise the guild by one"
	var betrayal: QuestDefinition = QuestDefinition.parse("betrayal", BETRAYAL, {})
	profile.quests.book[betrayal.id] = betrayal
	var applied: String = betrayal.problem + profile.apply(_gain([], 1))
	var _unbooked: bool = profile.quests.book.erase(betrayal.id)
	if not applied.is_empty() or profile.standings.of(GUILD) != Standings.LOWEST:
		return "a quest lowering the guild past its scale didn't hold it at the lowest: " + applied
	var leaning: PathLeaning = profile.leaning
	if leaning.supremacy != 1 or leaning.harmony != 0 or leaning.toward() != PathMark.SUPREMACY:
		return "the quests finished didn't lean the player one toward supremacy: %d, %d" % [
			leaning.harmony,
			leaning.supremacy,
		]
	return ""


## Progress within a step survives saving and loading, and counts on from there.
func _check_kept(book: Dictionary[String, QuestDefinition]) -> String:
	var fresh: Profile = Profile.new()
	fresh.quests.book = book
	var applied: String = fresh.apply(_gain(["ombulumo"], 0))
	applied += ProfileStore.save(fresh, SAVE_PATH)
	var loaded: Profile = ProfileStore.load_from(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not applied.is_empty() or ProfileSave.to_text(loaded) != ProfileSave.to_text(fresh):
		return "quest progress didn't survive saving and loading: " + applied + loaded.problem
	loaded.quests.book = book
	applied = loaded.apply(_gain(["ombulumo", "ombulumo"], 0))
	if not applied.is_empty() or not loaded.quests.finished.has("three_ombulumo"):
		return "loaded progress didn't count on to the toads' quest's end"
	return ""


## Two quests finished by one fact land in id order, whatever order the book holds them in. Saved
## progress whose step is already at its count, or past the quest's last step, settles at the next
## fact of any kind.
func _check_settled() -> String:
	var any_domination: String = "{\"id\": \"%s\", \"name\": \"N\", "
	any_domination += "\"steps\": [{\"condition\": \"dominated\", \"ends\": \"%s\"}]}"
	var profile: Profile = Profile.new()
	for id: String in ["zz_last", "aa_first"]:
		profile.quests.book[id] = QuestDefinition.parse(id, any_domination % [id, id], {})
	var applied: String = profile.apply(_gain(["ombulumo"], 0))
	var sorted: Array[String] = ["aa_first", "zz_last"]
	if not applied.is_empty() or profile.quests.finished != sorted:
		return "quests finished together weren't listed in id order: %s" % profile.quests.finished
	var save: Profile = Profile.new()
	save.quests.progress["three_ombulumo"] = QuestProgress.new(0, 3)
	save.quests.progress["first_domination"] = QuestProgress.new(4, 0)
	var stale: Profile = ProfileSave.parse(ProfileSave.to_text(save))
	stale.quests.book = QuestContent.load_quests().quests
	applied = stale.problem + stale.apply(_gain([], 1))
	var settled: Array[String] = ["first_domination", "three_ombulumo"]
	if not applied.is_empty() or stale.quests.finished != settled:
		return "saved progress that no longer fits didn't settle at the next fact: " + applied
	return ""


## Quest data with one broken file gives an empty quest book, so no quest advances on part of it,
## and so does a quest moving the standing with a faction that doesn't exist (#532), or handing its
## territory to one (#638).
func _check_broken_data() -> String:
	var good: String = "{\"id\": \"a_good\", \"name\": \"N\", "
	good += "\"steps\": [{\"condition\": \"opened\", \"ends\": \"a_good\"}]}"
	var content: QuestData = _load_written({
		"a_good": good,
		"b_broken": "{\"id\": \"b_broken\", \"name\": \"N\", \"steps\": []}",
	})
	if content.problem.is_empty() or not ProfileHolder.quest_book_of(content).is_empty():
		return "quest data with a broken file still gave quests to advance"
	var stranger: String = good.replace("\"steps\"", STRANGER_STANDING + ", \"steps\"")
	content = _load_written({ "a_good": stranger })
	if not content.problem.ends_with("its standing's faction must be one that exists"):
		return "a quest moving the standing with no faction that exists wasn't refused"
	var astray: String = "\"territory\": {\"instance\": \"forest\", \"faction\": \"strangers\"}"
	# Its step counts in its territory, as every territory quest's does (#769).
	var in_forest: String = good.replace("\"opened\"", "\"opened\", \"instance\": \"forest\"")
	content = _load_written({ "a_good": in_forest.replace("\"steps\"", astray + ", \"steps\"") })
	if not content.problem.ends_with("its territory's faction must be one that exists"):
		return "a quest handing its territory to no faction that exists wasn't refused (#638)"
	return _check_dialog_ids()


## A quest naming a dialog or an answer that no dialog file has is refused (#636), and one naming
## the scout's promise reads, worded as the scout's dialog has it.
func _check_dialog_ids() -> String:
	var unknown: Dictionary[String, String] = {
		"no_dialog": PROMISE % ["no_such_dialog", "promise_to_look"],
		"no_answer": PROMISE % [SCOUT, "no_such_answer"],
	}
	for case: String in unknown:
		var refused: QuestData = _load_written({ "promise": unknown[case] })
		if not refused.problem.contains("step 0: the dialog"):
			return "a quest naming %s wasn't refused: %s" % [case, refused.problem]
	var content: QuestData = _load_written({ "promise": PROMISE % [SCOUT, "promise_to_look"] })
	var line: String = ""
	if content.problem.is_empty():
		line = QuestListView.step_line(content.quests["promise"].steps[0], 0)
	if line != "Tell the Guild Scout: \"I'll take a look.\"":
		return "the scout's promise didn't read as the dialog words it: %s %s" % [
			content.problem,
			line,
		]
	return ""


## The quests read from a directory holding `files`, quest text by id; the directory is gone after.
static func _load_written(files: Dictionary[String, String]) -> QuestData:
	var directory: String = "user://written_quests_test/"
	var _made: Error = DirAccess.make_dir_recursive_absolute(directory)
	for id: String in files:
		var file: FileAccess = FileAccess.open(directory + id + ".jsonc", FileAccess.WRITE)
		var _stored: bool = file.store_string(files[id])
		file.close()
	var content: QuestData = QuestContent.load_quests(directory)
	for id: String in files:
		var _removed: Error = DirAccess.remove_absolute(directory + id + ".jsonc")
	var _gone: Error = DirAccess.remove_absolute(directory)
	return content


func _gain(species: Array[String], chests: int) -> Gain:
	var gain: Gain = Gain.new()
	gain.dominated_species = species
	gain.chests_opened = chests
	return gain
