extends RefCounted
## Quest flow (#184): quests advance from what this machine's player obtains. A fresh profile has
## the first domination open; another player's domination leaves it so, and this player's
## domination, through the event bus, finishes it; its progress is on disk at once and survives
## loading. A chest counts for the player who got loot from it. Steps count up and hand over to the
## next, one fact at a time, and only what a step asks for counts toward it. Quests finished
## together are listed in id order;
## saved progress that no longer fits its quest settles at the next fact; and quest data with a
## broken file advances no quest at all. Every open quest has a marker over the nearest thing it
## asks for (#300), and a finished one has none. The list at the side of the screen (#340) shows
## each open quest's step and count, follows a step counting up, and drops a finished quest once
## it has faded out. A player stepping into a place from outside it raises that the place was
## reached, for that player only (#339); it finishes this player's quest to reach it, not another
## player's arrival, and the quest's marker points at the place's nearest tile.

const SAVE_PATH: String = "user://test_quest_profile.json"
## A quest with two steps, for the counting: two moss toads, then a chest.
const TWO_STEPS: String = (
	"{\"id\": \"toads_then_chest\", \"name\": \"Two toads, then a chest\", \"steps\": ["
	+ "{\"condition\": \"dominated\", \"species\": \"moss_toad\", \"count\": 2}, "
	+ "{\"condition\": \"opened\"}]}"
)
## A quest that asks to reach the beach.
const REACH_BEACH: String = (
	"{\"id\": \"reach_beach\", \"name\": \"Go to the beach\", \"steps\": ["
	+ "{\"condition\": \"reached\", \"place\": \"beach\"}]}"
)
## A small region with the beach on its east, `b`; players 1 and 2 start west of it.
const BEACH_REGION: String = (
	"# Beach\n\n## Tiles\n\n```\n . . b b\n. 1 2 . b\n . . b b\n```\n\n## Legend\n\n"
	+ "- `b`: the beach; stepping here reaches the place beach\n"
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
		result = await _check_tracked(tree)
	SaveStore.remove(SAVE_PATH)
	return result


## Through the main scene: only this player's domination, handed out by the bus, finishes the first
## domination, and it's saved at once and loads back; a chest counts for whoever got loot from it.
func _check_tracked(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree, SAVE_PATH)
	var holder: ProfileHolder = FlowGame.holder(main)
	var driver: GameDriver = FlowGame.held_driver(main)
	var bus: EventBus = main.get_node("EventBus") as EventBus
	var profile: Profile = holder.keeper.profile
	var result: String = ""
	if not profile.quest_book.has("first_domination") or not profile.quests_done.is_empty():
		result = "a fresh profile doesn't have the first domination open"
	var markers: QuestMarkerView = main.get_node("Instance/QuestMarkerView") as QuestMarkerView
	if result.is_empty():
		result = _check_marked(driver, markers, profile)
	var list: QuestListView = main.get_node("Hud/QuestList") as QuestListView
	if result.is_empty():
		result = _check_listed(list, {
			"first_domination": "Dominate a monster",
			"three_moss_toads": "Dominate a Moss Toad  0/3",
		})
	_emit(driver, bus, WildMonsterDominated.new(90, 9, 1, Vector2i.ZERO, "moss_toad"))
	if result.is_empty() and not profile.quests_done.is_empty():
		result = "another slot's domination finished this player's quest"
	_emit(driver, bus, WildMonsterDominated.new(91, 1, 0, Vector2i.ZERO, "storm_finch"))
	var expected: Array[String] = ["first_domination"]
	var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
	if result.is_empty() and (profile.quests_done != expected or loaded.quests_done != expected):
		result = "this player's domination didn't finish the first domination on disk"
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


## The open first domination is marked over the wild monster nearest to this player, a quest asking
## for a species nobody here is has no marker, and the markers follow the open quests.
func _check_marked(driver: GameDriver, markers: QuestMarkerView, profile: Profile) -> String:
	var state: GameState = driver.state
	var wild: WildMonsterFeature = state.feature(Features.WILD_MONSTERS) as WildMonsterFeature
	if wild == null or wild.monsters.is_empty():
		return "the starting instance needs wild monsters to mark"
	var from: Vector2i = state.player(0).tile
	var nearest: int = Hex.distance(state.entity(wild.monsters[0]).tile, from)
	for entity_id: int in wild.monsters:
		nearest = mini(nearest, Hex.distance(state.entity(entity_id).tile, from))
	var targets: Dictionary[String, Vector2i] = QuestMarkerView.targets_of(state, profile, 0)
	if (not targets.has("first_domination")
			or Hex.distance(targets["first_domination"], from) != nearest):
		return "the first domination isn't marked over the nearest wild monster"
	markers.show_quests()
	if not markers.markers.has("first_domination"):
		return "the open first domination has no marker"
	return _check_unmarked(state, wild, profile)


## A quest asking for a species is marked only when one of that species is here.
func _check_unmarked(state: GameState, wild: WildMonsterFeature, profile: Profile) -> String:
	var text: String = "{\"id\": \"absent\", \"name\": \"Absent\", \"steps\": "
	text += "[{\"condition\": \"dominated\", \"species\": \"storm_finch\"}]}"
	var known: Dictionary[String, Species] = Content.load_species().species
	var absent: QuestDefinition = QuestDefinition.parse("absent", text, known)
	profile.quest_book[absent.id] = absent
	var any_finch: bool = false
	for entity_id: int in wild.monsters:
		any_finch = any_finch or wild.species_of(entity_id) == "storm_finch"
	var marked: bool = QuestMarkerView.targets_of(state, profile, 0).has("absent")
	var _dropped: bool = profile.quest_book.erase("absent")
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


## The finished first domination's card fades out and is gone; the open toads' quest stays.
func _check_dropped(tree: SceneTree, list: QuestListView) -> String:
	var fading: float = QuestListView.DONE_SECONDS + QuestListView.FADE_SECONDS
	await tree.create_timer(fading + 0.2).timeout
	list.show_quests()
	if list.cards.has("first_domination") or list.order.has("first_domination"):
		return "the finished first domination stayed on the quest list"
	if not list.cards.has("three_moss_toads"):
		return "an open quest left the quest list"
	return ""


## The list follows: another moss toad counts the toads' quest up, the finished first domination
## shows done and then drops out.
func _check_list_follows(
	tree: SceneTree,
	driver: GameDriver,
	bus: EventBus,
	list: QuestListView,
) -> String:
	_emit(driver, bus, WildMonsterDominated.new(92, 1, 0, Vector2i.ZERO, "moss_toad"))
	var result: String = _check_listed(list, {
		"first_domination": QuestListView.DONE_TEXT,
		"three_moss_toads": "Dominate a Moss Toad  1/3",
	})
	if result.is_empty():
		result = await _check_dropped(tree, list)
	return result


## Chests and places count for whoever opened or reached them.
func _check_finds(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	list: QuestListView,
) -> String:
	var result: String = _check_chests(driver, bus, profile, list)
	return result if not result.is_empty() else _check_reached(driver, bus, profile)


## A chest counts for this player when they got loot from it, not when only another player did,
## and the list asks to open one meanwhile.
func _check_chests(
	driver: GameDriver,
	bus: EventBus,
	profile: Profile,
	list: QuestListView,
) -> String:
	var text: String = "{\"id\": \"open_one\", \"name\": \"Open a chest\", "
	text += "\"steps\": [{\"condition\": \"opened\"}]}"
	var chest: QuestDefinition = QuestDefinition.parse("open_one", text, {})
	profile.quest_book[chest.id] = chest
	var listed: String = _check_listed(list, { "open_one": "Open a chest" })
	if not listed.is_empty():
		return listed
	var others: Dictionary[int, Dictionary] = { 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 9, others))
	if profile.quests_done.has("open_one"):
		return "another player's loot counted as this player's chest"
	var mine: Dictionary[int, Dictionary] = { 0: { }, 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 1, mine))
	if not profile.quests_done.has("open_one"):
		return "a chest this player got their roll from didn't count"
	return ""


## Reaching the beach counts for this player when they reached it, not when another player did.
func _check_reached(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var beach: QuestDefinition = QuestDefinition.parse("reach_beach", REACH_BEACH, {})
	profile.quest_book[beach.id] = beach
	_emit(driver, bus, PlaceReached.new("beach", 9, 1))
	_emit(driver, bus, PlaceReached.new("pond", 1, 0))
	if profile.quests_done.has("reach_beach"):
		return "another player's arrival, or another place, counted as reaching the beach"
	_emit(driver, bus, PlaceReached.new("beach", 1, 0))
	if not profile.quests_done.has("reach_beach"):
		return "this player reaching the beach didn't finish the quest to reach it"
	return ""


## On a region with a beach: player 1 walking onto it from outside raises that they reached it,
## walking on along it doesn't again, and player 2 stepping onto it raises it for player 2. The
## quest to reach the beach points at the beach tile nearest to player 1.
func _check_places() -> String:
	var region: Region = RegionDocument.parse(BEACH_REGION)
	var ordered: Array[Feature] = [MovementFeature.new(), FogFeature.new(), TriggerFeature.new()]
	var state: GameState = GameState.new(region, 3, ordered)
	if not region.problem.is_empty() or not state.problem.is_empty():
		return "the beach region didn't read: " + region.problem + state.problem
	for slot: int in 2:
		var _player: Entity = state.add_entity(slot, region.starts[slot])
	var profile: Profile = Profile.new()
	profile.quest_book["reach_beach"] = QuestDefinition.parse("reach_beach", REACH_BEACH, {})
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
	return result


## The quest to reach the beach is marked on the beach tile nearest to player 1.
func _check_place_marker(state: GameState, profile: Profile) -> String:
	var from: Vector2i = state.player(0).tile
	var nearest: int = -1
	var beach: Array[Vector2i] = []
	for trigger: TileTrigger in state.region.triggers:
		beach.append(trigger.tile)
		var distance: int = Hex.distance(trigger.tile, from)
		nearest = distance if nearest < 0 else mini(nearest, distance)
	var target: Vector2i = QuestMarkerView.targets_of(state, profile, 0).get("reach_beach", from)
	if not beach.has(target) or Hex.distance(target, from) != nearest:
		return "the quest to reach the beach isn't marked on its nearest tile"
	return ""


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


## Steps count up one fact at a time: only the species a step asks for counts, a step at its count
## hands over to the next even within one gain, and the last one finishes the quest. The toads'
## quest counts to three.
func _check_counted() -> String:
	var content: Content = Content.load_quests()
	var profile: Profile = Profile.new()
	profile.quest_book = content.quests
	var two: QuestDefinition = QuestDefinition.parse("toads_then_chest", TWO_STEPS, content.species)
	profile.quest_book[two.id] = two
	var applied: String = profile.apply(_gain(["storm_finch", "moss_toad"], 0))
	var progress: QuestProgress = profile.quest_progress.get(two.id)
	var toads: QuestProgress = profile.quest_progress.get("three_moss_toads")
	if not applied.is_empty() or progress == null or progress.step != 0 or progress.count != 1:
		return "one moss toad didn't count one toward its step: " + applied
	if toads == null or toads.count != 1 or profile.quests_done != ["first_domination"]:
		return "the toads' quest didn't count up, or the first domination didn't finish"
	applied = profile.apply(_gain(["moss_toad", "moss_toad"], 1))
	if (not applied.is_empty()
			or profile.quests_done != ["first_domination", "three_moss_toads", two.id]):
		return "a gain didn't hand a full step to the next one: %s" % profile.quests_done
	if not profile.quest_progress.is_empty():
		return "finished quests kept their progress"
	return _check_kept(profile.quest_book)


## Progress within a step survives saving and loading, and counts on from there.
func _check_kept(book: Dictionary[String, QuestDefinition]) -> String:
	var fresh: Profile = Profile.new()
	fresh.quest_book = book
	var applied: String = fresh.apply(_gain(["moss_toad"], 0))
	applied += SaveStore.save_profile(fresh, SAVE_PATH)
	var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
	SaveStore.remove(SAVE_PATH)
	if not applied.is_empty() or ProfileSave.to_text(loaded) != ProfileSave.to_text(fresh):
		return "quest progress didn't survive saving and loading: " + applied + loaded.problem
	loaded.quest_book = book
	applied = loaded.apply(_gain(["moss_toad", "moss_toad"], 0))
	if not applied.is_empty() or not loaded.quests_done.has("three_moss_toads"):
		return "loaded progress didn't count on to the toads' quest's end"
	return ""


## Two quests finished by one fact land in id order, whatever order the book holds them in. Saved
## progress whose step is already at its count, or past the quest's last step, settles at the next
## fact of any kind.
func _check_settled() -> String:
	var any_domination: String = "{\"id\": \"%s\", \"name\": \"N\", "
	any_domination += "\"steps\": [{\"condition\": \"dominated\"}]}"
	var profile: Profile = Profile.new()
	for id: String in ["zz_last", "aa_first"]:
		profile.quest_book[id] = QuestDefinition.parse(id, any_domination % id, {})
	var applied: String = profile.apply(_gain(["moss_toad"], 0))
	var sorted: Array[String] = ["aa_first", "zz_last"]
	if not applied.is_empty() or profile.quests_done != sorted:
		return "quests finished together weren't listed in id order: %s" % profile.quests_done
	var save: Profile = Profile.new()
	save.quest_progress["three_moss_toads"] = QuestProgress.new(0, 3)
	save.quest_progress["first_domination"] = QuestProgress.new(4, 0)
	var stale: Profile = ProfileSave.parse(ProfileSave.to_text(save))
	stale.quest_book = Content.load_quests().quests
	applied = stale.problem + stale.apply(_gain([], 1))
	var settled: Array[String] = ["first_domination", "three_moss_toads"]
	if not applied.is_empty() or stale.quests_done != settled:
		return "saved progress that no longer fits didn't settle at the next fact: " + applied
	return ""


## Quest data with one broken file gives an empty quest book, so no quest advances on part of it.
func _check_broken_data() -> String:
	var directory: String = "user://broken_quests_test/"
	var _made: Error = DirAccess.make_dir_recursive_absolute(directory)
	var files: Dictionary[String, String] = {
		"a_good": "{\"id\": \"a_good\", \"name\": \"N\", \"steps\": [{\"condition\": \"opened\"}]}",
		"b_broken": "{\"id\": \"b_broken\", \"name\": \"N\", \"steps\": []}",
	}
	for id: String in files:
		var file: FileAccess = FileAccess.open(directory + id + ".jsonc", FileAccess.WRITE)
		var _stored: bool = file.store_string(files[id])
		file.close()
	var content: Content = Content.load_quests(directory)
	for id: String in files:
		var _removed: Error = DirAccess.remove_absolute(directory + id + ".jsonc")
	var _gone: Error = DirAccess.remove_absolute(directory)
	if content.problem.is_empty() or not ProfileHolder.quest_book_of(content).is_empty():
		return "quest data with a broken file still gave quests to advance"
	return ""


func _gain(species: Array[String], chests: int) -> Gain:
	var gain: Gain = Gain.new()
	gain.dominated_species = species
	gain.chests_opened = chests
	return gain
