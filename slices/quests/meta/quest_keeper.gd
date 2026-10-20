class_name QuestKeeper
extends ProfileCompanion
## Keeps this machine's player's quests (#184, #855): their QuestTracker, with the quest book it
## advances them against, kept in their profile's file beside the profile (QuestSave), whose
## companion it is (ProfileHolder.companions), so the two are saved together. What their facts
## (QuestTie) finish gives the player through the profile (QuestRewards), in the same change, so a
## save never has one without the other.

## The profile the quests are kept with.
@export var holder: ProfileHolder

## The quests, the book included. Read them through `quests`, which has none while the profile's
## save can't be read.
var tracker: QuestTracker = QuestTracker.new()
var _book_loaded: bool = false


## Loads the quest book once, on entering the tree.
func _enter_tree() -> void:
	if _book_loaded:
		return
	_book_loaded = true
	var content: QuestData = QuestContent.load_quests()
	if not content.problem.is_empty():
		push_warning("the quests can't be read, so none advance: " + content.problem)
	tracker.book = book_of(content)


## This player's quests, or null while their profile's save can't be read: nothing shows or
## advances then.
func quests() -> QuestTracker:
	return tracker if holder != null and holder.keeper != null else null


## Counts `facts` on this player's quests (#817), in order, and gives what finishing each gives,
## saved with the profile like a gain.
func count(facts: Array[QuestFact]) -> void:
	if quests() != null:
		holder.change(advance.bind(tracker, facts))


## Counts `facts` on the quests `kept`, in order, and gives `profile` what finishing each quest
## they finish gives (QuestRewards), in the same change.
static func advance(profile: Profile, kept: QuestTracker, facts: Array[QuestFact]) -> void:
	for fact: QuestFact in facts:
		for quest: QuestDefinition in kept.advance(fact):
			QuestRewards.give(quest, profile)


## The quests the player advances from `content`: none when any quest file couldn't be read, so
## progress waits for whole, sound data rather than advancing on part of it.
static func book_of(content: QuestData) -> Dictionary[String, QuestDefinition]:
	var none: Dictionary[String, QuestDefinition] = {}
	return content.quests if content.problem.is_empty() else none


func migrate(data: Dictionary, format: int) -> void:
	QuestSave.migrate(data, format)


func read(data: Dictionary) -> String:
	var loaded: QuestTracker = QuestTracker.new()
	var problem: String = QuestSave.read(loaded, data)
	if problem.is_empty():
		loaded.book = tracker.book
		tracker = loaded
	return problem


func started() -> void:
	var fresh: QuestTracker = QuestTracker.new()
	fresh.book = tracker.book
	tracker = fresh


func beside() -> Dictionary:
	return QuestSave.beside(tracker)
