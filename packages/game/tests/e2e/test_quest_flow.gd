extends RefCounted
## Quest flow (#184): quests advance from what this machine's player obtains. A fresh profile has
## the first domination open, asking for the beach of the starting instance first (#321); another
## player's domination leaves it so, and this player's domination, through the event bus, finishes
## it; its progress is on disk at once and survives loading. A chest counts for the player who
## got loot from it. Steps count up and hand over to the next, one fact at a time, and only what a
## step asks for counts toward it. Quests finished together are listed in id order;
## saved progress that no longer fits its quest settles at the next fact; and quest data with a
## broken file advances no quest at all. Every open quest has a marker over the nearest thing it
## asks for (#300), and a finished one has none. The player follows one open quest (#1298): the
## one they picked, else the side quest they started last, else the first open one, kept through
## saving and loading. The list at the side of the screen (#340) shows only the followed quest's
## step and count, follows a step counting up, and drops a finished quest once it has faded out;
## the menu's Quests tab (#388) shows the same quests with every step, done,
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
## the Amvrel Velmarai by one, saved with the profile, and a quest naming a faction that
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
	+ "{\"condition\": \"entered\", \"instance\": \""
	+ FlowSteps.GLADE
	+ "\", \"ends\": \"enter_glade\"}]}"
)
## A quest that asks to reach the beach.
const REACH_BEACH: String = (
	"{\"id\": \"reach_beach\", \"name\": \"Go to the beach\", \"steps\": ["
	+ "{\"condition\": \"reached\", \"place\": \"beach\", \"ends\": \"reach_beach\"}]}"
)
## The dialog the answered steps ask about (#636).
const SCOUT: String = "teska_na_amvrel_greeting"
## A quest that asks to promise the scout to look at the glade, in the scout's dialog; its dialog
## and answer are left open.
const PROMISE: String = (
	"{\"id\": \"promise\", \"name\": \"A promise\", \"steps\": [{\"condition\": \"answered\", "
	+ "\"dialog\": \"%s\", \"answer\": \"%s\", \"ends\": \"promise\"}]}"
)
## A side quest that starts once the glade is purified (#707), a world event, not a quest's.
const AFTER_PURIFIED: String = (
	"{\"id\": \"after_purified\", \"name\": \"After the glade\", "
	+ "\"starts_on\": {\"condition\": \"emitted\", \"event\": \""
	+ FlowSteps.GLADE_PURIFIED
	+ "\"}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"after_purified\"}]}"
)
## A side quest that starts once the beacon is lit (#756).
const AFTER_BEACON: String = (
	"{\"id\": \"after_beacon\", \"name\": \"After the beacon\", "
	+ "\"starts_on\": {\"condition\": \"emitted\", \"event\": \"beacon_lit\"}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"after_beacon\"}]}"
)
## A quest whose chest turns the player against the Amvrel Velmarai, further than its scale.
const BETRAYAL: String = (
	"{\"id\": \"betrayal\", \"name\": \"Betray the guild\", "
	+ "\"standing\": {\"faction\": \"amvrel_velmarai\", \"change\": -10}, "
	+ "\"materials\": {\"moss\": 2}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"betrayal\"}]}"
)
## A quest raising the Odun Kragothai by one, the Sorn Lumawenai's enemy (#1323).
const SWORN: String = (
	"{\"id\": \"sworn\", \"name\": \"Sworn\", "
	+ "\"standing\": {\"faction\": \"odun_kragothai\", \"change\": 1}, "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"sworn\"}]}"
)
## A story choice enforcing alignment (#1326): the Odun Kragothai at least at their second rank,
## the Sorn Lumawenai at most hostile.
const CHOSEN: String = (
	"{\"id\": \"chosen\", \"name\": \"Chosen\", \"alignment\": ["
	+ "{\"faction\": \"odun_kragothai\", \"at_least\": 2}, "
	+ "{\"faction\": \"sorn_lumawenai\", \"at_most\": -1}], "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"chosen\"}]}"
)
## Floors for two factions that are enemies of each other (#1326): both at least at their first
## rank.
const TRUCE: String = (
	"{\"id\": \"truce\", \"name\": \"Truce\", \"alignment\": ["
	+ "{\"faction\": \"odun_kragothai\", \"at_least\": 1}, "
	+ "{\"faction\": \"sorn_lumawenai\", \"at_least\": 1}], "
	+ "\"steps\": [{\"condition\": \"opened\", \"ends\": \"truce\"}]}"
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
const GUILD: String = "amvrel_velmarai"
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
	result = result if not result.is_empty() else _check_facts()
	result = result if not result.is_empty() else _check_target()
	result = result if not result.is_empty() else _check_instances()
	if result.is_empty():
		result = await _check_tracked(tree)
	result = result if not result.is_empty() else _check_cache_untouched()
	SaveStore.remove(SAVE_PATH)
	return result


## Through the main scene: the first domination asks for the beach, then a domination (#321); only
## this player's domination, handed out by the bus, finishes it, and it's saved and loads back; a
## chest counts for whoever got loot from it.
func _check_tracked(tree: SceneTree) -> String:
	# In the glade, where the content's quests count (#1282); the runner puts the playground back.
	GameDriver.start_instance = FlowSteps.GLADE
	var main: Node = await FlowGame.start_held(tree, SAVE_PATH)
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	var bus: EventBus = main.get_node("EventBus") as EventBus
	var profile: Profile = holder.keeper.profile
	var quests: QuestTracker = FlowGame.quests(main).tracker
	var result: String = ""
	if not quests.book.has("first_domination") or not quests.finished.is_empty():
		result = "a fresh profile doesn't have the first domination open"
	var markers: QuestMarkerView = main.get_node("Instance/QuestMarkerView") as QuestMarkerView
	var list: QuestListView = main.get_node("Hud/QuestList") as QuestListView
	if result.is_empty():
		result = _check_beach_first(driver, bus, quests, markers, list)
	_emit(driver, bus, WildMonsterDominated.new(90, 9, 1, Vector2i.ZERO, "ombulumo"))
	if result.is_empty() and not quests.finished.is_empty():
		result = "another slot's domination finished this player's quest"
	_emit(driver, bus, WildMonsterDominated.new(91, 1, 0, Vector2i.ZERO, "tikazzir"))
	if result.is_empty():
		result = _check_on_disk(holder, quests)
	markers.show_quests()
	if result.is_empty() and markers.markers.has("first_domination"):
		result = "the finished first domination still has a marker"
	if result.is_empty():
		result = await _check_list_follows(tree, driver, bus, list)
	if result.is_empty():
		result = _check_finds(driver, bus, profile, quests, list)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## The first domination this player finished is on disk, and so is the guild it raised (#532).
## Reaching the beach was the gain saved at once; the domination right after it waits for the
## debounce (ProfileKeeper.SAVE_INTERVAL_MSEC), so it's flushed as ending the session would.
func _check_on_disk(holder: ProfileHolder, quests: QuestTracker) -> String:
	var flushed: String = holder.keeper.flush()
	var expected: Array[String] = ["first_domination"]
	var loaded_quests: QuestKeeper = QuestKeeper.new()
	var loaded: Profile = ProfileStore.load_from(SAVE_PATH, [loaded_quests])
	var finished_on_disk: Array[String] = loaded_quests.tracker.finished
	loaded_quests.free()
	if not flushed.is_empty() or quests.finished != expected or finished_on_disk != expected:
		return "this player's domination didn't finish the first domination on disk: " + flushed
	if loaded.standings.of(GUILD) != 1:
		return "finishing the first domination didn't raise the guild on disk (#532)"
	return ""


## This player dominating the quest target old_toad (#625), handed out by the bus, finishes the
## quest asking for it.
func _check_target_tracked(driver: GameDriver, bus: EventBus, quests: QuestTracker) -> String:
	quests.book["old_toad"] = QuestDefinition.parse("old_toad", OLD_TOAD, {})
	var dominated: WildMonsterDominated = WildMonsterDominated.new(
		93,
		1,
		0,
		Vector2i.ZERO,
		"ombulumo",
	)
	dominated.target = "old_toad"
	_emit(driver, bus, dominated)
	if not quests.finished.has("old_toad"):
		return "this player dominating the quest target old_toad didn't finish its quest"
	return ""


## The fresh first domination asks for the beach: it's marked there and listed as going there;
## once this player reaches it, it asks for a domination, marked over the nearest wild monster.
func _check_beach_first(
	driver: GameDriver,
	bus: EventBus,
	quests: QuestTracker,
	markers: QuestMarkerView,
	list: QuestListView,
) -> String:
	var result: String = _check_marked(driver, markers, quests)
	if result.is_empty():
		result = _check_listed(list, {
			"first_domination": "Go to the beach",
			"three_ombulumo": "Dominate an Ombulumo  0/3",
		})
	if result.is_empty():
		result = _check_card_scene(list, quests.book["first_domination"].shown_name())
	var menu: GameMenu = list.get_parent().get_node("GameMenu") as GameMenu
	if result.is_empty():
		result = _check_quests_tab(menu, quests, "Now: Go to the beach\nLater: Dominate a monster")
	_emit(driver, bus, PlaceReached.new("beach", 1, 0))
	if result.is_empty():
		result = _check_marked_monster(driver, markers, quests)
	if result.is_empty():
		result = _check_listed(list, { "first_domination": "Dominate a monster" })
	if result.is_empty():
		result = _check_quests_tab(menu, quests, "Done: Go to the beach\nNow: Dominate a monster")
	return result


## The open first domination asks for the beach first (#321): it's marked over the beach's tile
## nearest to this player, the sand of the starting instance, and the markers follow the open
## quests.
func _check_marked(driver: GameDriver, markers: QuestMarkerView, quests: QuestTracker) -> String:
	var state: GameState = driver.state
	var from: Vector2i = state.player(0).tile
	var nearest: int = -1
	for trigger: TileTrigger in TileTrigger.all_in(state.region):
		var beach: bool = trigger.action == TileTrigger.REACH and trigger.place == "beach"
		# Sand, or sand with crates on it (#446).
		var kind: String = state.region.terrain[trigger.tile]
		var sand: bool = kind in ["sand", "crates"]
		if beach and not sand:
			return "the starting instance's beach isn't sand"
		var distance: int = Hex.distance(trigger.tile, from)
		nearest = distance if beach and (nearest < 0 or distance < nearest) else nearest
	var here: String = driver.local_instance_name()
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(state, quests, 0, here)
	if (nearest < 0 or not targets.has("first_domination")
			or Hex.distance(targets["first_domination"], from) != nearest):
		return "the first domination isn't marked over the starting instance's nearest beach tile"
	return _check_followed_markers(markers, quests)


## Only the followed quest's marker in the world (#1328), the first domination's once followed, is
## drawn as followed, in the followed color at full size; every other one grey and smaller.
func _check_followed_markers(markers: QuestMarkerView, quests: QuestTracker) -> String:
	quests.focus = "first_domination"
	markers.show_quests()
	if not markers.markers.has("first_domination"):
		return "the open first domination has no marker"
	# Another quest's marker too, so the grey, smaller look is checked, not skipped.
	if markers.markers.size() < 2:
		return "no other open quest has a marker to check as not followed"
	# A long frame settles every marker at its size.
	markers._process(10.0)
	for id: String in markers.followed:
		var big: bool = id == "first_domination"
		var fill: MeshInstance3D = markers.markers[id].get_child(1) as MeshInstance3D
		var color: Color = (fill.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color
		var size: float = 1.0 if big else QuestMarkerView.OTHER_SHARE
		var looks: bool = color == (QuestMarkerView.COLOR if big else QuestMarkerView.OTHER_COLOR)
		var sized: bool = markers.markers[id].scale.is_equal_approx(Vector3.ONE * size)
		if markers.followed[id] != big or not looks or not sized:
			return "the world's marker of %s isn't drawn as followed or not as it is (#1328)" % id
	return ""


## Once the beach is reached, the first domination is marked over the wild monster nearest to this
## player, and a quest asking for a species nobody here is has no marker.
func _check_marked_monster(
	driver: GameDriver,
	markers: QuestMarkerView,
	quests: QuestTracker,
) -> String:
	var state: GameState = driver.state
	var wild: WildMonsterFeature = state.feature(WildMonsterFeature.ID) as WildMonsterFeature
	if wild == null or wild.monsters.is_empty():
		return "the starting instance needs wild monsters to mark"
	var from: Vector2i = state.player(0).tile
	var nearest: int = Hex.distance(state.entity(wild.monsters[0]).tile, from)
	for entity_id: int in wild.monsters:
		nearest = mini(nearest, Hex.distance(state.entity(entity_id).tile, from))
	var here: String = driver.local_instance_name()
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(state, quests, 0, here)
	if (not targets.has("first_domination")
			or Hex.distance(targets["first_domination"], from) != nearest):
		return "after the beach, the first domination isn't marked over the nearest wild monster"
	markers.show_quests()
	if not markers.markers.has("first_domination"):
		return "the open first domination has no marker after the beach"
	return _check_unmarked(state, wild, quests)


## A quest asking for a species is marked only when one of that species is here.
func _check_unmarked(state: GameState, wild: WildMonsterFeature, quests: QuestTracker) -> String:
	var text: String = "{\"id\": \"absent\", \"name\": \"Absent\", \"steps\": "
	text += "[{\"condition\": \"dominated\", \"species\": \"tikazzir\", \"ends\": \"absent\"}]}"
	var known: Dictionary[String, Species] = SpeciesContent.load_species().species
	var absent: QuestDefinition = QuestDefinition.parse("absent", text, known)
	quests.book[absent.id] = absent
	var any_finch: bool = false
	for entity_id: int in wild.monsters:
		any_finch = any_finch or wild.species_of(entity_id) == "tikazzir"
	var marked: bool = QuestTargets.of(state, quests, 0).has("absent")
	var _dropped: bool = quests.book.erase("absent")
	if marked != any_finch:
		return "a quest is marked although nothing it asks for is here, or the other way round"
	return ""


## The list shows each of `expected`'s quests with the line under its name, by quest id, while
## the player follows it (#1298), and no other open quest.
func _check_listed(list: QuestListView, expected: Dictionary[String, String]) -> String:
	var quests: QuestTracker = list.keeper.quests()
	for id: String in expected:
		quests.focus = id
		list.show_quests()
		if list.shown.get(id, "") != expected[id] or not list.cards.has(id):
			return "the quest list shows %s for %s, not %s" % [list.shown.get(id), id, expected[id]]
		for other: String in list.shown:
			var open: bool = quests.open_steps().has(other)
			if other != quests.focused() and open and not list.leaving.has(other):
				return "the quest list shows %s while %s is followed" % [other, quests.focused()]
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
func _check_quests_tab(menu: GameMenu, quests: QuestTracker, first: String) -> String:
	var entered: Dictionary[String, String] = {
		"enter_thicket": ENTER_THICKET,
		"enter_glade": ENTER_GLADE,
	}
	for id: String in entered:
		quests.book[id] = QuestDefinition.parse(id, entered[id], {})
	menu.quests_tab().refresh()
	var expected: Dictionary[String, String] = {
		"enter_glade": "Now: Enter Lumwen Hoal",
		"enter_thicket": "Now: Enter the thicket",
		"first_domination": first,
		"three_ombulumo": "Now: Dominate an Ombulumo  0/3",
	}
	var shown: Dictionary[String, String] = menu.quests_tab().shown
	# Laid out in its scene (#437): it scrolls only up and down.
	if menu.quests_tab().horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return "the Quests tab's scene scrolls sideways"
	for id: String in entered:
		var _unbooked: bool = quests.book.erase(id)
	if shown != expected:
		return "the Quests tab shows %s, not %s" % [shown, expected]
	return _check_tab_follows(menu.quests_tab(), quests)


## The Quests tab's button beside the followed quest says so with its star and takes no press, and
## pressing another's follows that quest (#1298), a pick the profile keeps.
func _check_tab_follows(tab: QuestsTab, quests: QuestTracker) -> String:
	tab.refresh()
	var followed: Button = tab.follow_buttons.get(quests.focused())
	if followed == null or followed.text != QuestsTab.FOLLOWED_TEXT or not followed.disabled:
		return "the Quests tab doesn't mark the followed quest %s" % quests.focused()
	# Another open quest's button offers to follow it, and pressing it does.
	var other_id: String = ""
	for id: String in tab.follow_buttons:
		if id != quests.focused():
			other_id = id
	var other: Button = tab.follow_buttons.get(other_id)
	if other == null or other.text != QuestsTab.FOLLOW_TEXT or other.disabled:
		return "the Quests tab doesn't offer to follow an open quest besides %s" % quests.focused()
	other.pressed.emit()
	tab.refresh()
	var now: Button = tab.follow_buttons[other_id]
	if quests.focus != other_id or now.text != QuestsTab.FOLLOWED_TEXT:
		return "pressing %s's button in the Quests tab didn't follow it" % other_id
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
	quests: QuestTracker,
	list: QuestListView,
) -> String:
	var result: String = _check_chests(driver, bus, quests, list)
	if result.is_empty():
		result = _check_reached(driver, bus, quests)
	list.show_quests()
	if result.is_empty() and list.cards.has("pond_chest"):
		result = "the pond's side quest is listed before this player entered the pond"
	# Following the newest quest, which the pond's side quest is once it starts (#1298).
	quests.focus = ""
	if result.is_empty():
		result = _check_entered(driver, bus, quests)
	list.show_quests()
	if result.is_empty() and (quests.focused() != "pond_chest" or not list.cards.has("pond_chest")):
		result = "the pond's side quest, started last, isn't followed and listed"
	if result.is_empty():
		result = _check_listed(list, { "pond_chest": "Open a chest" })
	if result.is_empty():
		result = _check_entered_glade(driver, bus, quests)
	if result.is_empty():
		result = _check_answered(driver, bus, quests)
	if result.is_empty():
		result = _check_territory(driver, bus, profile, quests, list)
	return result if not result.is_empty() else _check_world_event(driver, bus, quests)


## A chest counts for this player when they got loot from it, not when only another player did,
## and the list asks to open one meanwhile.
func _check_chests(
	driver: GameDriver,
	bus: EventBus,
	quests: QuestTracker,
	list: QuestListView,
) -> String:
	var text: String = "{\"id\": \"open_one\", \"name\": \"Open a chest\", "
	text += "\"steps\": [{\"condition\": \"opened\", \"ends\": \"open_one\"}]}"
	var chest: QuestDefinition = QuestDefinition.parse("open_one", text, {})
	quests.book[chest.id] = chest
	var listed: String = _check_listed(list, { "open_one": "Open a chest" })
	if not listed.is_empty():
		return listed
	var others: Dictionary[int, Dictionary] = { 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 9, others))
	if quests.finished.has("open_one"):
		return "another player's loot counted as this player's chest"
	var mine: Dictionary[int, Dictionary] = { 0: { }, 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 1, mine))
	if not quests.finished.has("open_one"):
		return "a chest this player got their roll from didn't count"
	return ""


## Reaching the beach counts for this player when they reached it, not when another player did.
func _check_reached(driver: GameDriver, bus: EventBus, quests: QuestTracker) -> String:
	var beach: QuestDefinition = QuestDefinition.parse("reach_beach", REACH_BEACH, {})
	quests.book[beach.id] = beach
	_emit(driver, bus, PlaceReached.new("beach", 9, 1))
	_emit(driver, bus, PlaceReached.new("pond", 1, 0))
	if quests.finished.has("reach_beach"):
		return "another player's arrival, or another place, counted as reaching the beach"
	_emit(driver, bus, PlaceReached.new("beach", 1, 0))
	if not quests.finished.has("reach_beach"):
		return "this player reaching the beach didn't finish the quest to reach it"
	return ""


## Entering the thicket counts for this player when they entered it, not when another player did.
func _check_entered(driver: GameDriver, bus: EventBus, quests: QuestTracker) -> String:
	var thicket: QuestDefinition = QuestDefinition.parse("enter_thicket", ENTER_THICKET, {})
	quests.book[thicket.id] = thicket
	_emit(driver, bus, PieceEntered.new("thicket", 9, 1))
	_emit(driver, bus, PieceEntered.new("pond", 1, 0))
	if quests.finished.has("enter_thicket"):
		return "another player entering, or another piece, counted as entering the thicket"
	_emit(driver, bus, PieceEntered.new("thicket", 1, 0))
	if not quests.finished.has("enter_thicket"):
		return "this player entering the thicket didn't finish the quest to enter it"
	return ""


## The quest to enter the glade is marked on the forest's nearest exit leading there, and counts
## for this player when they entered the glade, not when another player did, nor for another
## instance, nor for a piece of the same name.
func _check_entered_glade(driver: GameDriver, bus: EventBus, quests: QuestTracker) -> String:
	var glade: QuestDefinition = QuestDefinition.parse("enter_glade", ENTER_GLADE, {})
	quests.book[glade.id] = glade
	var forest: GameState = InstanceBlueprints.create(FlowSteps.FOREST, 3, 1)
	var ways: Array[Vector2i] = []
	for i: int in forest.region.exits.size():
		if forest.region.exit_blueprints[i] == FlowSteps.GLADE:
			ways.append(Vector2i(forest.region.exits[i].x, forest.region.exits[i].y))
	var from: Vector2i = forest.player(0).tile
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(forest, quests, 0)
	var target: Vector2i = targets.get("enter_glade", -Vector2i.ONE)
	if not ways.has(target) or Hex.distance(target, from) != _nearest(ways, from):
		return "the quest to enter the glade isn't marked on the nearest exit leading there"
	_emit(driver, bus, InstanceEntered.new(FlowSteps.GLADE, 9, 1))
	_emit(driver, bus, InstanceEntered.new(FlowSteps.BASIC, 1, 0))
	_emit(driver, bus, PieceEntered.new(FlowSteps.GLADE, 1, 0))
	if quests.finished.has("enter_glade"):
		return "another player entering, another instance or a piece counted as entering the glade"
	_emit(driver, bus, InstanceEntered.new(FlowSteps.GLADE, 1, 0))
	if not quests.finished.has("enter_glade"):
		return "this player entering the glade didn't finish the quest to enter it"
	return ""


## Promising the scout to look counts for this player when they chose that answer, not when another
## player did, nor for another answer of the same dialog (#636). Then a quest target (#625).
func _check_answered(driver: GameDriver, bus: EventBus, quests: QuestTracker) -> String:
	var promise: QuestDefinition = QuestDefinition.parse(
		"promise",
		PROMISE % [SCOUT, "promise_to_look"],
		{},
	)
	quests.book[promise.id] = promise
	_emit(driver, bus, DialogAnswered.new(SCOUT, "promise_to_look", 9, 1))
	_emit(driver, bus, DialogAnswered.new(SCOUT, "leave_scout", 1, 0))
	if not promise.problem.is_empty() or quests.finished.has("promise"):
		return "another player's or another answer counted as the promise: " + promise.problem
	_emit(driver, bus, DialogAnswered.new(SCOUT, "promise_to_look", 1, 0))
	if not quests.finished.has("promise"):
		return "this player promising the scout didn't finish the quest asking for it"
	return _check_target_tracked(driver, bus, quests)


## Finishing a territory quest hands its instance to its faction (#638): the forest's, once this
## player walked its stream, grove and felling, not when another player entered the last one, nor
## when this player entered a felling in another instance, since its steps count only in the
## forest (#769); meanwhile its marker in the glade points at an exit leading there, and its pill
## names the forest (#794). The
## hand-over waits in the profile's outbox (#771) and goes in this player's next command, which the
## replay records, and the world clears the forest's old holder in the same tick as it hands the
## forest to the guild. The world records the request applied and acknowledges it, and the outbox
## drops it; the same request sent again, as at the start of a session after a crash, is
## acknowledged but not handed over twice.
func _check_territory(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	quests: QuestTracker,
	list: QuestListView,
) -> String:
	var forest: String = FlowSteps.FOREST
	var quest: String = "guild_charts_morwe_wudhen"
	WorldFlags.set_flag(driver.world, Territory.flag(forest, "rivals"))
	_emit(driver, bus, InstanceEntered.new(forest, 1, 0))
	var pilled: String = _check_pills(driver, list, quest)
	if not pilled.is_empty():
		return pilled
	_emit_in(driver, bus, PieceEntered.new("stream", 1, 0), forest)
	_emit_in(driver, bus, PieceEntered.new("grove", 1, 0), forest)
	_emit_in(driver, bus, PieceEntered.new("felling", 9, 1), forest)
	_emit_in(driver, bus, PieceEntered.new("felling", 1, 0), FlowSteps.GLADE)
	_emit(driver, bus, PieceEntered.new("felling", 1, 0))
	if (quests.finished.has(quest)
			or Territory.holder(driver.world.flags, forest) != "rivals"):
		return "another player, or this one outside the forest, finished its territory quest"
	var marked: String = _check_territory_marked(quests, quest)
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
	if not quests.finished.has(quest) or not to_guild:
		return "finishing the forest's territory quest left its holders at %s" % [held]
	if not driver.recording.changes.has(Territory.code(forest, GUILD)):
		return "the replay didn't record the forest handed over"
	return _check_territory_resent(driver, bus, profile, request)


## The instance a quest's step counts in shows as a pill under its name (#794), in the list and on
## the Quests tab alike: the territory quest `quest`'s names the forest, only outlined with an
## arrow while this player is in the glade, filled once they're in the forest; the pond's side
## quest's names the glade (#1282), filled while they're there, outlined once they're in the forest.
func _check_pills(driver: GameDriver, list: QuestListView, quest: String) -> String:
	var tab: QuestsTab = (list.get_parent().get_node("GameMenu") as GameMenu).quests_tab()
	var glade: String = FlowSteps.GLADE
	var forest: String = FlowSteps.FOREST
	tab.refresh()
	var result: String = _check_pill(_list_pill(list, quest), forest, false)
	result = result if not result.is_empty() else _check_pill(tab.pills[quest], forest, false)
	if result.is_empty():
		result = _check_pill(_list_pill(list, "pond_chest"), glade, true)
	if result.is_empty():
		result = _check_pill(tab.pills["pond_chest"], glade, true)
	var there: Elsewhere = Elsewhere.new()
	there.where = FlowSteps.FOREST
	list.driver = there
	tab.driver = there
	tab.refresh()
	result = result if not result.is_empty() else _check_pill(_list_pill(list, quest), forest, true)
	result = result if not result.is_empty() else _check_pill(tab.pills[quest], forest, true)
	if result.is_empty():
		result = _check_pill(_list_pill(list, "pond_chest"), glade, false)
	if result.is_empty():
		result = _check_pill(tab.pills["pond_chest"], glade, false)
	list.driver = driver
	tab.driver = driver
	there.free()
	return result


## The pill on the list's card of quest `id`, once the player follows it (#1298).
static func _list_pill(list: QuestListView, id: String) -> QuestPill:
	list.keeper.quests().focus = id
	list.show_quests()
	return list.pill(id)


## Why `pill` doesn't name the instance `where` as `here` says (filled, or outlined with its
## arrow), or "".
func _check_pill(pill: QuestPill, where: String, here: bool) -> String:
	var style: StyleBoxFlat = pill.get_theme_stylebox("panel") as StyleBoxFlat
	var label: Label = pill.get_node("Row/Name") as Label
	if (not pill.visible or pill.instance_id != where or pill.here != here
			or label.text != Realms.name_of(where) or style.draw_center != here
			or (pill.get_node("Row/Arrow") as Control).visible == here):
		return "a quest's pill shows %s (here: %s), not %s, here: %s" % [
			label.text,
			pill.here,
			where,
			here,
		]
	return ""


## Why the territory quest `quest`, open in `quests`, isn't marked in the glade on an exit leading
## to the forest it counts in (#769), or "".
func _check_territory_marked(quests: QuestTracker, quest: String) -> String:
	var glade: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, 1)
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(
		glade,
		quests,
		0,
		FlowSteps.GLADE,
	)
	var marked: Vector2i = targets.get(quest, -Vector2i.ONE)
	for i: int in glade.region.exits.size():
		if Vector2i(glade.region.exits[i].x, glade.region.exits[i].y) == marked:
			if glade.region.exit_blueprints[i] == FlowSteps.FOREST:
				return ""
	return "the forest's territory quest isn't marked on an exit from the glade leading there"


## The territory quest's hand-over `request`, applied and acknowledged, is out of the outbox and
## recorded as applied; sent again, it's acknowledged once more but not handed over twice, so the
## forest stays with the holder it has meanwhile. The commands meanwhile carry it as acknowledged
## (#942), so the world forgets its receipt and keeps the mark instead, which still refuses it.
func _check_territory_resent(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	request: OutboxEntry,
) -> String:
	var forest: String = FlowSteps.FOREST
	var applied: Array = driver.world.stored(0, TerritoryFeature.ID).get(OutboxReceipts.APPLIED, [])
	if not profile.outbox.entries.is_empty() or applied != [request.id]:
		return "the applied hand-over stayed in the outbox, or wasn't recorded: %s" % [applied]
	WorldFlags.set_flag(driver.world, Territory.flag(forest, GUILD), false)
	WorldFlags.set_flag(driver.world, Territory.flag(forest, "rivals"))
	var acknowledged: Array = []
	var heard: Callable = func(event: RequestApplied) -> void: acknowledged.append(event.request)
	bus.subscribe(RequestApplied, heard)
	driver.input.send(request)
	_tick(driver, bus)
	if Territory.holder(driver.world.flags, forest) != "rivals" or acknowledged != [request.id]:
		return "the hand-over sent again was handed over twice, or not acknowledged"
	var stored: Dictionary = driver.world.stored(0, TerritoryFeature.ID)
	var mark: int = stored.get(OutboxReceipts.MARK, Command.NO_REQUEST)
	if stored.has(OutboxReceipts.APPLIED) or mark != ShortId.code(request.id):
		return "the world kept the acknowledged hand-over's receipt, not its mark: %s" % [stored]
	return _check_receipts_bounded(driver, bus, profile, request)


## A later hand-over, posted after `request` was acknowledged, gets a higher id (#942) and is
## applied, and the world holds its receipt alone: the receipts stay as few as the requests not
## yet acknowledged, however many came before.
func _check_receipts_bounded(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	request: OutboxEntry,
) -> String:
	var forest: String = FlowSteps.FOREST
	var later: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, request.data)
	if ShortId.code(later.id) <= ShortId.code(request.id):
		return "the outbox drew %s after %s, not in order" % [later.id, request.id]
	driver.input.send(later)
	_tick(driver, bus)
	var applied: Array = driver.world.stored(0, TerritoryFeature.ID).get(OutboxReceipts.APPLIED, [])
	if Territory.holder(driver.world.flags, forest) != GUILD or applied != [later.id]:
		return "the later hand-over wasn't applied, or the world kept more receipts: %s" % [applied]
	if not profile.outbox.entries.is_empty():
		return "the later hand-over stayed in the outbox once acknowledged"
	return _check_receipts_past_stuck(driver, bus, profile)


## A hand-over of a territory no quest of this build hands over stays in the outbox, neither
## applied nor acknowledged (TerritoryFeature.step); it holds back only the hand-overs' mark (#968):
## of two later trap changes, the second still makes the world forget the first one's receipt.
func _check_receipts_past_stuck(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	# 1 is no territory's code (Territory.code), so no quest here hands it over.
	var stuck: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, 1)
	driver.input.send(stuck)
	_tick(driver, bus)
	if profile.outbox.entries.size() != 1:
		return "the hand-over of a territory no quest hands over left the outbox"
	var first: OutboxEntry = profile.outbox.post(OutboxEntry.TRAP, CommandCodes.NONE)
	driver.input.send(first)
	_tick(driver, bus)
	var second: OutboxEntry = profile.outbox.post(OutboxEntry.TRAP, CommandCodes.NONE)
	driver.input.send(second)
	_tick(driver, bus)
	var applied: Array = driver.world.stored(0, SpikesFeature.ID).get(OutboxReceipts.APPLIED, [])
	var _dropped: bool = profile.outbox.drop(stuck.id)
	if applied != [second.id]:
		return "a stuck hand-over kept the trap changes' receipts: %s" % [applied]
	if not profile.outbox.entries.is_empty():
		return "the trap changes stayed in the outbox once acknowledged"
	return ""


## Runs a few ticks and hands their events out.
func _tick(driver: GameDriver, bus: EventBus) -> void:
	for _step: int in 3:
		driver.advance(1.0 / Simulation.TICKS_PER_SECOND)
	bus.flush()


## An event that changed the world (#707) reaches this player's profile, wherever they are, and
## starts the side quest waiting on it; another world event doesn't.
func _check_world_event(driver: GameDriver, bus: EventBus, quests: QuestTracker) -> String:
	var waiting: QuestDefinition = QuestDefinition.parse("after_purified", AFTER_PURIFIED, {})
	quests.book[waiting.id] = waiting
	_emit(
		driver,
		bus,
		WorldChanged.new(
			FlowSteps.CORRUPTED_GLADE,
			WorldFlags.EVENT_FLAG + FlowSteps.CORRUPTED_GLADE,
		),
	)
	if quests.open_steps().has(waiting.id):
		return "another world event started the side quest waiting on the glade's purifying"
	_emit(
		driver,
		bus,
		WorldChanged.new(
			FlowSteps.GLADE_PURIFIED,
			WorldFlags.EVENT_FLAG + FlowSteps.GLADE_PURIFIED,
		),
	)
	if not quests.open_steps().has(waiting.id):
		return "the glade's purifying didn't start the side quest waiting on it"
	return _check_caught_up(driver.quest_tie, quests)


## As a session starts, the quests count the events that already changed the world (#756), from
## its flags, and no other flag: the beacon lit before starts the side quest waiting on it, while
## the side quest the glade's purifying started already keeps its progress and one done stays done.
func _check_caught_up(tie: QuestTie, quests: QuestTracker) -> String:
	var lit: QuestDefinition = QuestDefinition.parse("after_beacon", AFTER_BEACON, {})
	quests.book[lit.id] = lit
	quests.finished.append("after_done")
	var done: QuestDefinition = QuestDefinition.parse("after_beacon", AFTER_BEACON, {})
	done.id = "after_done"
	quests.book[done.id] = done
	var purified: QuestProgress = quests.progress["after_purified"]
	var flags: Array[String] = [
		WorldFlags.EVENT_FLAG + "beacon_lit",
		WorldFlags.EVENT_FLAG + FlowSteps.GLADE_PURIFIED,
		"TERRITORY_after_beacon",
	]
	tie.catch_up(flags)
	var result: String = ""
	if not quests.open_steps().has(lit.id):
		result = "catching up with the world's events didn't start the side quest waiting on one"
	elif quests.progress.has(done.id):
		result = "catching up with the world's events started a side quest already done again"
	elif quests.progress["after_purified"] != purified:
		result = "catching up with the world's events started a side quest again"
	for id: String in [lit.id, done.id]:
		var _unbooked: bool = quests.book.erase(id)
	quests.finished.erase(done.id)
	return result


## On a region with a beach: player 1 walking onto it from outside raises that they reached it,
## walking on along it doesn't again, and player 2 stepping onto it raises it for player 2. The
## quest to reach the beach points at the beach tile nearest to player 1. A player arriving on the
## beach (through an exit, or starting there) reaches it too (#348).
func _check_places() -> String:
	var region: Region = InstanceBlueprints.read_region(BEACH_REGION)
	var ordered: Array[Feature] = [MovementFeature.new(), FogFeature.new(), TriggerFeature.new()]
	var state: GameState = GameState.new(region, 3, ordered)
	if not region.problem.is_empty() or not state.problem.is_empty():
		return "the beach region didn't read: " + region.problem + state.problem
	for slot: int in 2:
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	var quests: QuestTracker = QuestTracker.new()
	quests.book["reach_beach"] = QuestDefinition.parse("reach_beach", REACH_BEACH, {})
	var result: String = _check_place_marker(state, quests)
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
	var _arrived: Entity = state.add_entity(2, TileTrigger.all_in(state.region)[0].tile)
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
func _check_place_marker(state: GameState, quests: QuestTracker) -> String:
	var from: Vector2i = state.player(0).tile
	var beach: Array[Vector2i] = []
	for trigger: TileTrigger in TileTrigger.all_in(state.region):
		beach.append(trigger.tile)
	var target: Vector2i = QuestTargets.of(state, quests, 0).get("reach_beach", from)
	if not beach.has(target) or Hex.distance(target, from) != _nearest(beach, from):
		return "the quest to reach the beach isn't marked on its nearest tile"
	return ""


## The region's quest target old_toad (#625) is its marked Ombulumo's, kept through a save, and
## not the other's, which is nearer the player.
func _check_target() -> String:
	var region: Region = InstanceBlueprints.read_region(TARGET_REGION)
	var ordered: Array[Feature] = [
		MovementFeature.new(),
		KnockdownFeature.new(),
		TrailFeature.new(),
		HealthFeature.new(),
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
	var quests: QuestTracker = QuestTracker.new()
	quests.book["old_toad"] = QuestDefinition.parse("old_toad", OLD_TOAD, {})
	var step: QuestStep = quests.book["old_toad"].steps[0]
	if QuestTargets.of(state, quests, 0).get("old_toad", Vector2i.ZERO) != marked:
		return "the quest asking for old_toad isn't marked over it"
	if QuestListView.step_line(step, 0) != "Dominate the old toad":
		return "the quest asking for old_toad reads %s" % QuestListView.step_line(step, 0)
	var applied: String = _count(quests, _gain(["ombulumo"], 0))
	if not applied.is_empty() or quests.finished.has("old_toad"):
		return "dominating another Ombulumo counted toward old_toad: " + applied
	var targeted: Array[QuestFact] = _gain(["ombulumo"], 0)
	targeted.append(QuestFact.new(QuestStep.TARGET_DOMINATED, "old_toad"))
	applied = _count(quests, targeted)
	var done: Array[String] = ["old_toad"]
	if not applied.is_empty() or quests.finished != done:
		return "dominating old_toad didn't finish the quest asking for it: " + applied
	return ""


## In the glade: the player starting in the start piece enters it on the first tick, once. The
## quest to enter the thicket is marked on the thicket's nearest tile, and walking there enters
## every piece on the way, once each time the piece changes, ending in the thicket.
func _check_pieces() -> String:
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, 1)
	var still: Array[Command] = FlowSteps.commands([Command.NO_MOVE])
	Simulation.step(state, still)
	var entered: Array[String] = _pieces_entered(state.events)
	Simulation.step(state, still)
	entered.append_array(_pieces_entered(state.events))
	if entered.size() != 1 or entered[0] != "start":
		return "the player starting in the glade didn't enter its start piece, once"
	var quests: QuestTracker = QuestTracker.new()
	quests.book["enter_thicket"] = QuestDefinition.parse("enter_thicket", ENTER_THICKET, {})
	var from: Vector2i = state.player(0).tile
	var thicket: Array[Vector2i] = []
	for tile: Vector2i in state.region.piece_of:
		if state.region.piece_of[tile] == "thicket":
			thicket.append(tile)
	var target: Vector2i = QuestTargets.of(state, quests, 0).get("enter_thicket", from)
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
	var quests: QuestTracker = QuestTracker.new()
	quests.book = QuestContent.load_quests().quests
	var applied: String = _count(quests, _gain([], 1))
	applied += _count(quests, _entering("thicket"))
	if not applied.is_empty() or quests.open_steps().has("pond_chest"):
		return "the pond's side quest started before the pond was entered: " + applied
	if quests.finished.has("pond_chest") or quests.progress.has("pond_chest"):
		return "a chest counted toward the pond's side quest before it started"
	applied = _count(quests, _entering("pond"))
	var loaded: QuestTracker = _reloaded(quests)
	if loaded == null:
		return "the started pond side quest couldn't be saved and loaded"
	var step: QuestStep = loaded.open_steps().get("pond_chest")
	if (not applied.is_empty() or step == null
			or QuestsTab.quest_lines(loaded, "pond_chest") != ["Now: Open a chest"]):
		return "entering the pond didn't open its side quest, kept through loading: " + applied
	applied = _count(loaded, _gain([], 1))
	if not applied.is_empty() or not loaded.finished.has("pond_chest"):
		return "a chest didn't finish the started pond side quest: " + applied
	var text: String = "{\"id\": \"in_one\", \"name\": \"N\", \"starts_on\": %s, \"steps\": [%s]}"
	var enter: String = "{\"condition\": \"entered\", \"piece\": \"pond\"}"
	var at_once: QuestTracker = QuestTracker.new()
	var ending: String = enter.replace("}", ", \"ends\": \"in_one\"}")
	at_once.book["in_one"] = QuestDefinition.parse("in_one", text % [enter, ending], {})
	applied = _count(at_once, _entering("pond"))
	if not applied.is_empty() or at_once.finished != ["in_one"]:
		return "entering the pond didn't both start and finish a side quest asking for it"
	return _check_followed()


## The player follows one open quest (#1298): with no side quest started and none picked, the
## first open one; the side quest started last, the pond's, once it starts, kept through saving and
## loading; the one they pick, kept too, but not one that isn't open. Once the side quest followed
## finishes, the first open one is followed again.
func _check_followed() -> String:
	var quests: QuestTracker = QuestTracker.new()
	quests.book = QuestContent.load_quests().quests
	var applied: String = _count(quests, _entering("thicket"))
	if quests.focused() != "first_domination":
		return "with no side quest started, %s is followed, not the first open one" % [
			quests.focused(),
		]
	applied += _count(quests, _entering("pond"))
	var loaded: QuestTracker = _reloaded(quests)
	if loaded == null or loaded.focused() != "pond_chest" or loaded.started != ["pond_chest"]:
		return "the side quest started last isn't followed, kept through loading: " + applied
	loaded.focus = "three_ombulumo"
	var picked: QuestTracker = _reloaded(loaded)
	if picked == null or picked.focused() != "three_ombulumo":
		return "the quest picked to follow isn't followed, or not kept through loading"
	loaded.focus = "first_domination_done"
	if loaded.focused() != "pond_chest":
		return "a quest picked that isn't open is followed over the side quest started last"
	loaded.focus = "pond_chest"
	applied = _count(loaded, _gain([], 1))
	if (not applied.is_empty() or not loaded.started.is_empty() or not loaded.focus.is_empty()
			or loaded.focused() != "first_domination"):
		return "the finished side quest followed is still started or followed: %s" % [
			loaded.started,
		]
	return ""


## The glade's fork (#573): entering the glade starts it on its choice, listed as both ways on and
## marked over the pond and the thicket, each its nearest tile. Entering the thicket takes that way:
## the tab shows the way taken, done, then a domination, which ends the chain; the pond's chest
## never counts toward it. The pond's way, kept through saving and loading, ends at a chest.
func _check_branching() -> String:
	var book: Dictionary[String, QuestDefinition] = QuestContent.load_quests().quests
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, 1)
	var thicket: QuestTracker = QuestTracker.new()
	thicket.book = book
	var glade: String = FlowSteps.GLADE
	var entered: Array[QuestFact] = [QuestFact.new(QuestStep.INSTANCE_ENTERED, glade, glade)]
	var applied: String = _count(thicket, entered)
	var choosing: Array[String] = ["Now: Enter the pond or enter the thicket"]
	if not applied.is_empty() or QuestsTab.quest_lines(thicket, "lumwen_hoal_fork") != choosing:
		return "entering the glade didn't open its fork on its choice: %s" % [
			QuestsTab.quest_lines(thicket, "lumwen_hoal_fork"),
		]
	var result: String = _check_fork_marked(state, thicket)
	applied = _count(thicket, _entering("thicket"))
	var way: Array[String] = ["Done: Enter the thicket", "Now: Dominate a monster"]
	if result.is_empty() and QuestsTab.quest_lines(thicket, "lumwen_hoal_fork") != way:
		result = "the thicket's way isn't shown taken: %s" % [
			QuestsTab.quest_lines(thicket, "lumwen_hoal_fork"),
		]
	applied += _count(thicket, _gain([], 1))
	if result.is_empty() and thicket.finished.has("lumwen_hoal_fork"):
		result = "the pond's chest counted on the thicket's way"
	applied += _count(thicket, _gain(["ombulumo"], 0))
	if (result.is_empty()
			and (not applied.is_empty() or not thicket.finished.has("lumwen_hoal_fork"))):
		result = "a domination didn't end the thicket's way: " + applied
	return result if not result.is_empty() else _check_pond_way(book, entered)


## The glade's fork, on its choice, is marked over the pond's and the thicket's nearest tiles, one
## marker each, and not as a whole.
func _check_fork_marked(state: GameState, quests: QuestTracker) -> String:
	var from: Vector2i = state.player(0).tile
	var targets: Dictionary[String, Vector2i] = QuestTargets.of(state, quests, 0, FlowSteps.GLADE)
	var pieces: Array[String] = ["pond", "thicket"]
	for index: int in pieces.size():
		var tiles: Array[Vector2i] = []
		for tile: Vector2i in state.region.piece_of:
			if state.region.piece_of[tile] == pieces[index]:
				tiles.append(tile)
		var target: Vector2i = targets.get("lumwen_hoal_fork/%d" % index, -Vector2i.ONE)
		if not tiles.has(target) or Hex.distance(target, from) != _nearest(tiles, from):
			return "the glade's fork isn't marked over the nearest tile of the %s" % pieces[index]
	if targets.has("lumwen_hoal_fork"):
		return "the glade's fork is marked as a whole besides its choices"
	return ""


## Entering the pond takes the pond's way, kept through saving and loading, and a chest ends it.
func _check_pond_way(
	book: Dictionary[String, QuestDefinition],
	entered: Array[QuestFact],
) -> String:
	var pond: QuestTracker = QuestTracker.new()
	pond.book = book
	var applied: String = _count(pond, entered) + _count(pond, _entering("pond"))
	var loaded: QuestTracker = _reloaded(pond)
	if loaded == null:
		return "the pond's way couldn't be saved and loaded"
	var way: Array[String] = ["Done: Enter the pond", "Now: Open a chest"]
	if not applied.is_empty() or QuestsTab.quest_lines(loaded, "lumwen_hoal_fork") != way:
		return "the pond's way wasn't kept through loading: %s" % [
			QuestsTab.quest_lines(loaded, "lumwen_hoal_fork"),
		]
	applied = _count(loaded, _gain([], 1))
	if not applied.is_empty() or not loaded.finished.has("lumwen_hoal_fork"):
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
	var quests: QuestTracker = QuestTracker.new()
	var standing: String = STRANGER_STANDING.replace("strangers", GUILD)
	quests.book["fork"] = QuestDefinition.parse("fork", text % standing, {})
	var applied: String = quests.book["fork"].problem
	applied += _count(quests, _entering("pond"), profile) + _count(quests, _gain([], 1), profile)
	if (not applied.is_empty() or quests.finished != ["fork"]
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
	var quests: QuestTracker = QuestTracker.new()
	quests.book["fork"] = QuestDefinition.parse("fork", text, {})
	for id: String in starts:
		var side_text: String = waiting % ([id] + starts[id] + [id])
		quests.book[id] = QuestDefinition.parse(id, side_text, {})
	var applied: String = ""
	for id: String in quests.book:
		applied += quests.book[id].problem
	applied += _count(quests, _entering("thicket"))
	if not applied.is_empty() or quests.open_steps().keys() != ["after_thicket", "fork"]:
		return "taking the thicket's way didn't start just its side quest: " + applied
	applied = _count(quests, _gain([], 1))
	if not applied.is_empty() or quests.open_steps().keys() != ["after_won"]:
		return "the chain's end didn't start the side quest waiting on it: " + applied
	applied = _count(quests, _gain(["ombulumo"], 0))
	if not applied.is_empty() or quests.finished != ["after_thicket", "fork", "after_won"]:
		return "the side quests an event started didn't go on: %s" % quests.finished
	var step_waits: String = text.replace("\"condition\": \"opened\"", "\"condition\": \"emitted\"")
	step_waits = step_waits.replace("\"ends\"", "\"event\": \"took_pond\", \"ends\"")
	if QuestDefinition.parse("fork", step_waits, {}).problem.is_empty():
		return "a step waiting on an event wasn't refused"
	return _check_answered_choice()


## A choice taken by an answer (#636): leaving the scout takes the way to a domination, past the
## chest that asking about Lumwen Hoal leads to, and the tab shows both ways as answers.
func _check_answered_choice() -> String:
	var choice: String = "{\"condition\": \"answered\", \"dialog\": \"%s\", " % SCOUT
	choice += "\"answer\": \"%s\", \"next\": \"%s\"}"
	var text: String = "{\"id\": \"fork\", \"name\": \"N\", \"steps\": [{\"choices\": "
	text += "[%s, %s]}, " % [
		choice % ["ask_about_lumwen_hoal", "won"],
		choice % ["leave_scout", "lost"],
	]
	text += "{\"id\": \"won\", \"condition\": \"opened\", \"ends\": \"fork\"}, "
	text += "{\"id\": \"lost\", \"condition\": \"dominated\", \"ends\": \"fork\"}]}"
	var quests: QuestTracker = QuestTracker.new()
	quests.book["fork"] = QuestDefinition.parse("fork", text, {})
	var choosing: Array[String] = ["Now: Answer ask about lumwen hoal or answer leave scout"]
	var applied: String = quests.book["fork"].problem
	if not applied.is_empty() or QuestsTab.quest_lines(quests, "fork") != choosing:
		return "a choice between answers isn't shown as one: %s %s" % [
			applied,
			QuestsTab.quest_lines(quests, "fork"),
		]
	var left: Array[QuestFact] = [
		QuestFact.new(QuestStep.ANSWERED, QuestStep.answer_key(SCOUT, "leave_scout")),
	]
	applied = _count(quests, left) + _count(quests, _gain([], 1))
	if not applied.is_empty() or not quests.finished.is_empty():
		return "leaving the scout didn't take the way to a domination: " + applied
	applied = _count(quests, _gain(["ombulumo"], 0))
	if not applied.is_empty() or quests.finished != ["fork"]:
		return "a domination didn't end the way leaving the scout took: " + applied
	return ""


## The facts quests make of events (#817), for this player in slot 0 only: a domination is its
## species, then its quest target; a chest is opened even when it rolled nothing, then each item
## obtained with its amount; an instance entered happened in it, and a world event everywhere; and
## a world's flags give only its events.
func _check_facts() -> String:
	var targeted: WildMonsterDominated = _dominated("ombulumo")
	targeted.target = "old_toad"
	var loot: Dictionary[int, Dictionary] = { 0: { "feather": 2 }, 1: { "bone": 1 } }
	var empty: Dictionary[int, Dictionary] = { 0: {} }
	var events: Array[RefCounted] = [
		targeted,
		WildMonsterDominated.new(2, 2, 1, Vector2i.ZERO, "tikazzir"),
		ChestOpened.new(Vector2i.ZERO, 1, empty),
		ChestOpened.new(Vector2i.ZERO, 1, loot),
		InstanceEntered.new(FlowSteps.FOREST, 1, 0),
		PlaceReached.new("beach", 2, 1),
		WorldChanged.new(
			FlowSteps.GLADE_PURIFIED,
			WorldFlags.EVENT_FLAG + FlowSteps.GLADE_PURIFIED,
		),
	]
	var seen: Array[String] = []
	for event: RefCounted in events:
		seen.append_array(_described(QuestFacts.of(event, 0, FlowSteps.GLADE)))
	var flags: Array[String] = [
		WorldFlags.EVENT_FLAG + "beacon_lit",
		"TERRITORY_" + FlowSteps.GLADE,
	]
	seen.append_array(_described(QuestFacts.of_world_flags(flags)))
	var expected: Array[String] = [
		"dominated ombulumo %s 1" % FlowSteps.GLADE,
		"dominated_target old_toad %s 1" % FlowSteps.GLADE,
		"opened  %s 1" % FlowSteps.GLADE,
		"opened  %s 1" % FlowSteps.GLADE,
		"obtained feather %s 2" % FlowSteps.GLADE,
		"entered_instance %s %s 1" % [FlowSteps.FOREST, FlowSteps.FOREST],
		"emitted %s  1" % FlowSteps.GLADE_PURIFIED,
		"emitted beacon_lit  1",
	]
	if seen != expected:
		return "the facts made of events are %s" % [seen]
	return ""


## Each of `facts` in words: its condition, what, where and amount.
static func _described(facts: Array[QuestFact]) -> Array[String]:
	var words: Array[String] = []
	for fact: QuestFact in facts:
		words.append("%s %s %s %d" % [fact.condition, fact.what, fact.where, fact.amount])
	return words


## A step asking for feathers (#686) counts each feather obtained, not a bone, nor a chest opened
## that rolled none: three show 3/5, and four more finish it and count the two left over toward the
## next step. It has no marker, and an item is asked for only on an obtained step, and only one that
## a loot or harvest table drops (#766).
func _check_obtained() -> String:
	var quests: QuestTracker = QuestTracker.new()
	quests.book["feathers"] = QuestDefinition.parse("feathers", FEATHERS, {})
	var applied: String = quests.book["feathers"].problem
	applied += _count(quests, _gain([], 1))
	applied += _count(quests, _obtaining({ "feather": 3, "bone": 1 }))
	if not applied.is_empty() or QuestsTab.quest_lines(quests, "feathers")[0] != (
		"Now: Collect feather  3/5"
	):
		return "three feathers didn't count three toward five: %s %s" % [
			applied,
			QuestsTab.quest_lines(quests, "feathers"),
		]
	applied = _count(quests, _obtaining({ "feather": 4 }))
	var lines: Array[String] = ["Done: Collect feather  5/5", "Now: Collect feather  2/3"]
	if not applied.is_empty() or QuestsTab.quest_lines(quests, "feathers") != lines:
		return "four more feathers didn't finish five and count on: %s" % [
			QuestsTab.quest_lines(quests, "feathers"),
		]
	var state: GameState = InstanceBlueprints.create(FlowSteps.GLADE, 3, 1)
	if QuestTargets.of(state, quests, 0).has("feathers"):
		return "a step asking for an item is marked in the world"
	var stray: String = FEATHERS.replace("\"condition\": \"obtained\"", "\"condition\": \"opened\"")
	if QuestDefinition.parse("feathers", stray, {}).problem.is_empty():
		return "a step naming an item without asking for it wasn't refused"
	var dropped: QuestContent = _load_written({ "feathers": FEATHERS })
	var misspelt: String = FEATHERS.replace("feather\"", "feathre\"")
	var typo: QuestContent = _load_written({ "feathers": misspelt })
	if not dropped.problem.is_empty() or not typo.problem.contains("drops the item feathre"):
		return "only an item no table drops should be refused: %s / %s" % [
			dropped.problem,
			typo.problem,
		]
	return ""


## The facts of this player obtaining `items`, {item id: amount}, from a felled wild monster.
static func _obtaining(items: Dictionary[String, int]) -> Array[QuestFact]:
	var loot: Dictionary[int, Dictionary] = { 0: items }
	return QuestFacts.of(Harvested.new(1, "ombulumo", Vector2i.ZERO, loot), 0, "")


## The fact of this player entering the region piece `piece`.
static func _entering(piece: String) -> Array[QuestFact]:
	return [QuestFact.new(QuestStep.ENTERED, piece, FlowSteps.GLADE)]


## Counts `facts` on `quests`, in order, as the quests' keeper does, giving what finishing one
## gives to `profile`, or to a throwaway one; returns "", as taking a gain did.
static func _count(
		quests: QuestTracker,
		facts: Array[QuestFact],
		profile: Profile = null,
) -> String:
	QuestKeeper.advance(profile if profile != null else Profile.new(), quests, facts)
	return ""


## `quests` saved in a profile's file and read back (QuestKeeper, #855), with the same book; null
## when the save can't be read.
static func _reloaded(quests: QuestTracker) -> QuestTracker:
	var saved: QuestKeeper = QuestKeeper.new()
	saved.tracker = quests
	var loaded: QuestKeeper = QuestKeeper.new()
	loaded.tracker.book = quests.book
	var text: String = ProfileSave.to_text(Profile.new(), [saved])
	var problem: String = ProfileSave.parse(text, [loaded]).problem
	var reloaded: QuestTracker = loaded.tracker
	saved.free()
	loaded.free()
	return reloaded if problem.is_empty() else null


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


## Raises `event` in a tick, in the instance this player is in, and has the bus hand it out at once.
func _emit(driver: GameDriver, bus: EventBus, event: RefCounted) -> void:
	_emit_in(driver, bus, event, driver.local_instance_name())


## Hands `event` to the bus as one the instance `instance_name` raised (#769), then flushes it.
func _emit_in(driver: GameDriver, bus: EventBus, event: RefCounted, instance_name: String) -> void:
	driver.world.instance(instance_name).events.append(event)
	var events: Array[RefCounted] = [event]
	driver.ticked.emit(driver.state.tick, events)
	bus.flush()


## Steps count up one fact at a time: only the species a step asks for counts, a step at its count
## hands over to the next even within one gain, and the last one finishes the quest. The toads'
## quest counts to three. The first domination asks for the beach first (#321): dominations before
## it don't count, and reaching it hands over to dominating.
func _check_counted() -> String:
	var content: QuestContent = QuestContent.load_quests()
	var profile: Profile = Profile.new()
	var quests: QuestTracker = QuestTracker.new()
	quests.book = content.quests
	var two: QuestDefinition = QuestDefinition.parse("toads_then_chest", TWO_STEPS, content.species)
	quests.book[two.id] = two
	var at_beach: Array[QuestFact] = _gain(["tikazzir", "ombulumo"], 0)
	at_beach.append(QuestFact.new(QuestStep.REACHED, "beach", FlowSteps.GLADE))
	var applied: String = _count(quests, at_beach, profile)
	var progress: QuestProgress = quests.progress.get(two.id)
	var first: QuestProgress = quests.progress.get("first_domination")
	var toads: QuestProgress = quests.progress.get("three_ombulumo")
	if not applied.is_empty() or progress == null or progress.step != 0 or progress.count != 1:
		return "one Ombulumo didn't count one toward its step: " + applied
	if toads == null or toads.count != 1 or first == null or first.step != 1:
		return "the toads' quest didn't count up, or the beach didn't hand over to dominating"
	if not quests.finished.is_empty() or profile.standings.of(GUILD) != 0:
		return "a domination before the beach finished the first domination"
	applied = _count(quests, _gain(["ombulumo", "ombulumo"], 1), profile)
	if (not applied.is_empty()
			or quests.finished != ["first_domination", "three_ombulumo", two.id]):
		return "a gain didn't hand a full step to the next one: %s" % quests.finished
	if not quests.progress.is_empty():
		return "finished quests kept their progress"
	var result: String = _check_standing(profile, quests)
	return result if not result.is_empty() else _check_kept(quests.book)


## Finishing a quest moves the standing with the faction it names (#532): the first domination
## raised the guild by one, and a quest lowering it holds it at its first rank, since the guild
## stays allied until the postgame (#1324); that quest also gives two moss, which land in the
## player's materials (#1348).
## Finishing a path-marked quest leans the player toward its path (#658): the toads' quest, marked
## supremacy, leans them one toward it, and the unmarked ones toward neither.
func _check_standing(profile: Profile, quests: QuestTracker) -> String:
	if profile.standings.of(GUILD) != 1:
		return "finishing the first domination didn't raise the guild by one"
	var betrayal: QuestDefinition = QuestDefinition.parse("betrayal", BETRAYAL, {})
	quests.book[betrayal.id] = betrayal
	var applied: String = betrayal.problem + _count(quests, _gain([], 1), profile)
	var _unbooked: bool = quests.book.erase(betrayal.id)
	# The guild stays allied until the postgame (#1324): once joined, it never drops below its first
	# rank.
	if not applied.is_empty() or profile.standings.of(GUILD) != 1:
		return "a quest lowering the guild, joined, didn't hold it at its first rank: " + applied
	if profile.materials.get("moss", 0) != 2:
		return "finishing a quest giving two moss gave %d" % profile.materials.get("moss", 0)
	var enemies: String = _check_enemy_loss()
	if not enemies.is_empty():
		return enemies
	var leaning: PathLeaning = profile.leaning
	if leaning.supremacy != 1 or leaning.harmony != 0 or leaning.toward() != PathMark.SUPREMACY:
		return "the quests finished didn't lean the player one toward supremacy: %d, %d" % [
			leaning.harmony,
			leaning.supremacy,
		]
	return ""


## Finishing a quest that raises a faction costs half that with its enemy (#1310, #1323): two
## quests each raising the Odun Kragothai by one lose half a rank, then a whole one, with the Sorn
## Lumawenai.
func _check_enemy_loss() -> String:
	var sworn: QuestDefinition = QuestDefinition.parse("sworn", SWORN, {})
	var profile: Profile = Profile.new()
	QuestRewards.give(sworn, profile)
	var half: Array[String] = ["sorn_lumawenai"]
	# Both start one rank below neutral (#1378).
	if profile.standings.of("sorn_lumawenai") != -1 or profile.standings.half_lost != half:
		return "a quest raising the Odun Kragothai didn't lose half a rank with its enemy: %s" % [
			sworn.problem,
		]
	QuestRewards.give(sworn, profile)
	if profile.standings.of("sorn_lumawenai") != -2 or not profile.standings.half_lost.is_empty():
		return "two quests raising the Odun Kragothai didn't lose a rank with its enemy"
	return _check_enforced()


## A story choice enforces alignment (#1326): a quest raising the Odun Kragothai to at least their
## second rank and holding the Sorn Lumawenai at most hostile sets both from their start (-1), the
## gain of three ranks costing one and a half with the Sorn Lumawenai; finishing it again changes
## nothing, as both are within their bounds by then.
func _check_enforced() -> String:
	var chosen: QuestDefinition = QuestDefinition.parse("chosen", CHOSEN, {})
	var profile: Profile = Profile.new()
	QuestRewards.give(chosen, profile)
	var half: Array[String] = ["sorn_lumawenai"]
	var standings: Standings = profile.standings
	if (standings.of("odun_kragothai") != 2
			or standings.of("sorn_lumawenai") != -2
			or standings.half_lost != half):
		return "a quest enforcing alignment set %d and %d: %s" % [
			standings.of("odun_kragothai"),
			standings.of("sorn_lumawenai"),
			chosen.problem,
		]
	QuestRewards.give(chosen, profile)
	if (standings.of("odun_kragothai") != 2
			or standings.of("sorn_lumawenai") != -2
			or standings.half_lost != half):
		return "finishing a quest enforcing alignment again moved a standing within its bounds"
	# Floors for two enemies of each other: the second's gain costs the first rank, which the quest
	# then holds at its floor again, so both bounds hold whatever their order.
	var truce: QuestDefinition = QuestDefinition.parse("truce", TRUCE, {})
	var held: Profile = Profile.new()
	QuestRewards.give(truce, held)
	if held.standings.of("odun_kragothai") != 1 or held.standings.of("sorn_lumawenai") != 1:
		return "a quest enforcing floors for two enemies left %d and %d: %s" % [
			held.standings.of("odun_kragothai"),
			held.standings.of("sorn_lumawenai"),
			truce.problem,
		]
	return ""


## Progress within a step survives saving and loading, and counts on from there.
func _check_kept(book: Dictionary[String, QuestDefinition]) -> String:
	var fresh: QuestTracker = QuestTracker.new()
	fresh.book = book
	var applied: String = _count(fresh, _gain(["ombulumo"], 0))
	# Through the store, as the holder saves and loads it, its quests beside it (QuestKeeper, #855).
	var saving: QuestKeeper = QuestKeeper.new()
	saving.tracker = fresh
	applied += ProfileStore.save(Profile.new(), SAVE_PATH, [saving])
	var loading: QuestKeeper = QuestKeeper.new()
	loading.tracker.book = book
	applied += ProfileStore.load_from(SAVE_PATH, [loading]).problem
	var loaded: QuestTracker = loading.tracker
	saving.free()
	loading.free()
	SaveStore.remove(SAVE_PATH)
	if (not applied.is_empty()
			or JSON.stringify(QuestSave.beside(loaded)) != JSON.stringify(QuestSave.beside(fresh))):
		return "quest progress didn't survive saving and loading: " + applied
	applied = _count(loaded, _gain(["ombulumo", "ombulumo"], 0))
	if not applied.is_empty() or not loaded.finished.has("three_ombulumo"):
		return "loaded progress didn't count on to the toads' quest's end"
	return ""


## Two quests finished by one fact land in id order, whatever order the book holds them in. Saved
## progress whose step is already at its count, or past the quest's last step, settles at the next
## fact of any kind.
func _check_settled() -> String:
	var any_domination: String = "{\"id\": \"%s\", \"name\": \"N\", "
	any_domination += "\"steps\": [{\"condition\": \"dominated\", \"ends\": \"%s\"}]}"
	var quests: QuestTracker = QuestTracker.new()
	for id: String in ["zz_last", "aa_first"]:
		quests.book[id] = QuestDefinition.parse(id, any_domination % [id, id], {})
	var applied: String = _count(quests, _gain(["ombulumo"], 0))
	var sorted: Array[String] = ["aa_first", "zz_last"]
	if not applied.is_empty() or quests.finished != sorted:
		return "quests finished together weren't listed in id order: %s" % quests.finished
	var save: QuestTracker = QuestTracker.new()
	save.progress["three_ombulumo"] = QuestProgress.new(0, 3)
	save.progress["first_domination"] = QuestProgress.new(4, 0)
	var stale: QuestTracker = _reloaded(save)
	if stale == null:
		return "saved progress that no longer fits didn't load"
	stale.book = QuestContent.load_quests().quests
	applied = _count(stale, _gain([], 1))
	var settled: Array[String] = ["first_domination", "three_ombulumo"]
	if not applied.is_empty() or stale.finished != settled:
		return "saved progress that no longer fits didn't settle at the next fact: " + applied
	return ""


## Every instance a quest's start, step or choice names is an instance blueprint that exists: the
## quests can't check it as they read, since the blueprints come after them (#851). A quest naming
## one that doesn't exist reads, and this check finds it. Every step and choice of the game's quests
## names the instance it counts in, its target (owner, #1282: "each quest step should have a
## target/location"): a quest whose step names none, as the flows' own quests may, is refused.
func _check_instances() -> String:
	var content: QuestContent = QuestContent.load_quests()
	if not content.problem.is_empty():
		return "the quests didn't read: " + content.problem
	for quest: QuestDefinition in content.quests.values():
		var unknown: String = _unknown_instance(quest)
		if not unknown.is_empty():
			return "%s names %s, which isn't an instance blueprint" % [quest.id, unknown]
		var unplaced: int = _unplaced_step(quest)
		if unplaced >= 0:
			return "%s's step %d names no instance it counts in (#1282)" % [quest.id, unplaced]
	var anywhere: QuestDefinition = QuestDefinition.parse("enter_thicket", ENTER_THICKET, {})
	if not anywhere.problem.is_empty() or _unplaced_step(anywhere) != 0:
		return "a quest whose step names no instance wasn't found: " + anywhere.problem
	var placed: QuestDefinition = QuestDefinition.parse("enter_glade", ENTER_GLADE, {})
	if _unplaced_step(placed) >= 0:
		return "a step entering an instance, which names it, was taken for one naming none"
	# Neither counts in one instance, so neither shows a pill (#794).
	if anywhere.steps[0].counts_in() != "" or placed.steps[0].counts_in() != "":
		return "a step counting anywhere, or entering an instance, counts in one"
	var astray: QuestDefinition = QuestDefinition.parse(
		"enter_glade",
		ENTER_GLADE.replace("\"%s\"" % FlowSteps.GLADE, "\"nowhere\""),
		{},
	)
	if not astray.problem.is_empty() or _unknown_instance(astray) != "nowhere":
		return "a quest naming an instance that doesn't exist wasn't found: " + astray.problem
	return ""


## The index of the first step of `quest` that, or one of whose choices, names no instance, or -1.
static func _unplaced_step(quest: QuestDefinition) -> int:
	for index: int in quest.steps.size():
		for step: QuestStep in quest.steps[index].triggers():
			if step.instance.is_empty():
				return index
	return -1


## The first instance a start, step or choice of `quest` names that isn't an instance blueprint, or
## "".
static func _unknown_instance(quest: QuestDefinition) -> String:
	var named: Array[QuestStep] = []
	if quest.starts_on != null:
		named.append(quest.starts_on)
	for step: QuestStep in quest.steps:
		named.append_array(step.triggers())
	for step: QuestStep in named:
		if not step.instance.is_empty() and not InstanceBlueprints.exists(step.instance):
			return step.instance
	return ""


## The quests this flow added to its player's book stay theirs (#1385): the session's cached quest
## content, which every other tracker's book is copied from, has only the quest files' quests.
func _check_cache_untouched() -> String:
	var cached: Dictionary[String, QuestDefinition] = QuestContent.cached().quests
	for id: String in ["old_toad", "reach_beach", "enter_thicket", "enter_glade"]:
		if cached.has(id):
			return "the flow's quest %s reached the session's cached quest content" % id
	return ""


## Quest data with one broken file gives an empty quest book, so no quest advances on part of it,
## and so does a quest moving the standing with a faction that doesn't exist (#532), or handing its
## territory to one (#638).
func _check_broken_data() -> String:
	var good: String = "{\"id\": \"a_good\", \"name\": \"N\", "
	good += "\"steps\": [{\"condition\": \"opened\", \"ends\": \"a_good\"}]}"
	var content: QuestContent = _load_written({
		"a_good": good,
		"b_broken": "{\"id\": \"b_broken\", \"name\": \"N\", \"steps\": []}",
	})
	if content.problem.is_empty() or not QuestKeeper.book_of(content).is_empty():
		return "quest data with a broken file still gave quests to advance"
	var stranger: String = good.replace("\"steps\"", STRANGER_STANDING + ", \"steps\"")
	content = _load_written({ "a_good": stranger })
	if not content.problem.ends_with("its standing's faction must be one that exists"):
		return "a quest moving the standing with no faction that exists wasn't refused"
	var astray: String = "\"territory\": {\"instance\": \"%s\", \"faction\": \"strangers\"}" % [
		FlowSteps.FOREST,
	]
	# Its step counts in its territory, as every territory quest's does (#769).
	var in_forest: String = good.replace(
		"\"opened\"",
		"\"opened\", \"instance\": \"%s\"" % FlowSteps.FOREST,
	)
	content = _load_written({ "a_good": in_forest.replace("\"steps\"", astray + ", \"steps\"") })
	if not content.problem.ends_with("its territory's faction must be one that exists"):
		return "a quest handing its territory to no faction that exists wasn't refused (#638)"
	var cases: Dictionary[String, String] = {
		"{\"mose\": 1}": "it gives mose, which is no material",
		"{\"moss\": 0}": "its materials must give each id a whole count from 1",
		"{\"moss\": 1.5}": "its materials must give each id a whole count from 1",
		"{}": "must name one or more materials, each with a count",
	}
	for given: String in cases:
		var rewarding: String = good.replace("\"steps\"", "\"materials\": %s, \"steps\"" % given)
		content = _load_written({ "a_good": rewarding })
		if not content.problem.ends_with(cases[given]):
			return "a quest giving %s was refused with %s, not %s (#1348)" % [
				given,
				content.problem,
				cases[given],
			]
	return _check_ends_story(good)


## A quest marked as ending the main story (#1333) reads with the mark; one whose mark isn't true or
## false is refused.
func _check_ends_story(good: String) -> String:
	var ending: QuestDefinition = QuestDefinition.parse(
		"a_good",
		good.replace("\"steps\"", "\"ends_story\": true, \"steps\""),
		{},
	)
	var unmarked: QuestDefinition = QuestDefinition.parse("a_good", good, {})
	if not ending.problem.is_empty() or not ending.ends_story or unmarked.ends_story:
		return "a quest's ends_story mark wasn't read: " + ending.problem
	var bad: String = good.replace("\"steps\"", "\"ends_story\": 1, \"steps\"")
	if QuestDefinition.parse("a_good", bad, {}).problem != "its ends_story must be true or false":
		return "a quest whose ends_story isn't true or false wasn't refused"
	return _check_dialog_ids()


## A quest naming a dialog or an answer that no dialog file has is refused (#636), and so is one
## counting an answer that isn't marked as committing (#891); one naming the scout's promise, which
## commits, reads, worded as the scout's dialog has it.
func _check_dialog_ids() -> String:
	var unknown: Dictionary[String, String] = {
		"no_dialog": PROMISE % ["no_such_dialog", "promise_to_look"],
		"no_answer": PROMISE % [SCOUT, "no_such_answer"],
	}
	for case: String in unknown:
		var refused: QuestContent = _load_written({ "promise": unknown[case] })
		if not refused.problem.contains("step 0: the dialog"):
			return "a quest naming %s wasn't refused: %s" % [case, refused.problem]
	var uncommitted: QuestContent = _load_written({ "promise": PROMISE % [SCOUT, "leave_scout"] })
	var refusal: String = "leave_scout of the dialog %s has effects, so it must commit" % SCOUT
	if not uncommitted.problem.ends_with(refusal):
		return "a quest counting an uncommitted answer wasn't refused: " + uncommitted.problem
	var content: QuestContent = _load_written({ "promise": PROMISE % [SCOUT, "promise_to_look"] })
	var line: String = ""
	if content.problem.is_empty():
		line = QuestListView.step_line(content.quests["promise"].steps[0], 0)
	if line != "Tell Teska na Amvrel: \"I'll take a look.\"":
		return "the scout's promise didn't read as the dialog words it: %s %s" % [
			content.problem,
			line,
		]
	return ""


## The quests read from a directory holding `files`, quest text by id; the directory is gone after.
static func _load_written(files: Dictionary[String, String]) -> QuestContent:
	return FlowSteps.written_content(QuestContent.load_quests, files) as QuestContent


## The facts of this player dominating a monster of each of `species`, then opening `chests` chests,
## all in the glade, where the content's quests count (#1282).
func _gain(species: Array[String], chests: int) -> Array[QuestFact]:
	var facts: Array[QuestFact] = []
	for one: String in species:
		facts.append_array(QuestFacts.of(_dominated(one), 0, FlowSteps.GLADE))
	var opened: QuestFact = QuestFact.new(QuestStep.OPENED, "", FlowSteps.GLADE)
	for _chest: int in chests:
		facts.append(opened)
	return facts


## This player's domination of a wild monster of `species`.
static func _dominated(species: String) -> WildMonsterDominated:
	return WildMonsterDominated.new(1, 1, 0, Vector2i.ZERO, species)


## A session whose player is in the instance `where`, for the pills (#794).
class Elsewhere:
	extends Session

	var where: String = ""


	func local_instance_name() -> String:
		return where
