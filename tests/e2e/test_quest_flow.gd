extends RefCounted
## Quest flow (#184): quests advance from what this machine's player obtains. A fresh profile has
## the first catch open; another player's catch leaves it so, and this player's catch, through the
## event bus, finishes it; its progress is on disk at once and survives loading. A chest counts for
## the player who got loot from it. Steps count up and hand over to the next, one fact at a time,
## and only what a step asks for counts toward it.

const SAVE_PATH: String = "user://test_quest_profile.json"
## A quest with two steps, for the counting: two moss toads, then a chest.
const TWO_STEPS: String = (
	"{\"id\": \"toads_then_chest\", \"name\": \"Two toads, then a chest\", \"steps\": ["
	+ "{\"condition\": \"caught\", \"species\": \"moss_toad\", \"count\": 2}, "
	+ "{\"condition\": \"opened\"}]}"
)


func run(tree: SceneTree) -> String:
	var result: String = _check_counted()
	if result.is_empty():
		result = await _check_tracked(tree)
	SaveStore.remove(SAVE_PATH)
	return result


## Through the main scene: only this player's catch, handed out by the bus, finishes the first
## catch, and it's saved at once and loads back; a chest counts for whoever got loot from it.
func _check_tracked(tree: SceneTree) -> String:
	SaveStore.remove(SAVE_PATH)
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	var holder: ProfileHolder = main.get_node("ProfileHolder") as ProfileHolder
	holder.save_path = SAVE_PATH
	tree.root.add_child(main)
	await tree.process_frame
	var driver: GameDriver = main.get_node("Driver") as GameDriver
	driver.set_process(false)
	var bus: EventBus = main.get_node("EventBus") as EventBus
	var profile: Profile = holder.keeper.profile
	var result: String = ""
	if not profile.quest_book.has("first_catch") or not profile.quests_done.is_empty():
		result = "a fresh profile doesn't have the first catch open"
	_emit(driver, bus, WildMonsterCaught.new(90, 9, 1, Vector2i.ZERO, "moss_toad"))
	if result.is_empty() and not profile.quests_done.is_empty():
		result = "another slot's catch finished this player's quest"
	_emit(driver, bus, WildMonsterCaught.new(91, 1, 0, Vector2i.ZERO, "storm_finch"))
	var expected: Array[String] = ["first_catch"]
	var loaded: Profile = SaveStore.load_profile(SAVE_PATH)
	if result.is_empty() and (profile.quests_done != expected or loaded.quests_done != expected):
		result = "this player's catch didn't finish the first catch on disk"
	if result.is_empty():
		result = _check_chests(driver, bus, profile)
	main.queue_free()
	await tree.process_frame
	SaveStore.remove(SAVE_PATH)
	return result


## A chest counts for this player when they got loot from it, not when only another player did.
func _check_chests(driver: GameDriver, bus: EventBus, profile: Profile) -> String:
	var text: String = "{\"id\": \"open_one\", \"name\": \"Open a chest\", "
	text += "\"steps\": [{\"condition\": \"opened\"}]}"
	var chest: QuestDefinition = QuestDefinition.parse("open_one", text, {})
	profile.quest_book[chest.id] = chest
	var others: Dictionary[int, Dictionary] = { 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 9, others))
	if profile.quests_done.has("open_one"):
		return "another player's loot counted as this player's chest"
	var mine: Dictionary[int, Dictionary] = { 0: { }, 1: { "moss": 1 } }
	_emit(driver, bus, ChestOpened.new(Vector2i.ZERO, 1, mine))
	if not profile.quests_done.has("open_one"):
		return "a chest this player got their roll from didn't count"
	return ""


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
	if toads == null or toads.count != 1 or profile.quests_done != ["first_catch"]:
		return "the toads' quest didn't count up, or the first catch didn't finish"
	applied = profile.apply(_gain(["moss_toad", "moss_toad"], 1))
	if not applied.is_empty() or profile.quests_done != ["first_catch", "three_moss_toads", two.id]:
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
	if not applied.is_empty() or loaded.to_text() != fresh.to_text():
		return "quest progress didn't survive saving and loading: " + applied + loaded.problem
	loaded.quest_book = book
	applied = loaded.apply(_gain(["moss_toad", "moss_toad"], 0))
	if not applied.is_empty() or not loaded.quests_done.has("three_moss_toads"):
		return "loaded progress didn't count on to the toads' quest's end"
	return ""


func _gain(species: Array[String], chests: int) -> Gain:
	var gain: Gain = Gain.new()
	gain.caught_species = species
	gain.chests_opened = chests
	return gain
