class_name ProfileHolder
extends Node
## Holds this machine's player's profile through a session (#37, #132): loaded at boot, what it
## gains taken over at once and saved debounced (ProfileKeeper, #73), and whatever is pending saved
## when the game quits or goes to the background. Its quests advance (#184) and its outbox (#771)
## and revive items (#656) change through what it's handed (ProfileTie, which ties it to the
## session, #831). The player's personal color (#391) is kept in it too, saved the same way. A save
## that can't be read is reported and left alone, never overwritten.

## Where the profile is saved; tests point it elsewhere before the holder enters the tree.
var save_path: String = ProfileStore.PATH
## Null when the save couldn't be read: nothing is taken or saved then.
var keeper: ProfileKeeper
## Every piece of gear's id (#694): loot with one of these ids is gear, the rest materials.
var _gear_ids: Array[String] = []


## Loads the profile on entering the tree, before any node's _ready: the driver starts the session
## in its own, with this player's companion from the profile (#338).
func _enter_tree() -> void:
	if keeper != null:
		return
	WebStorage.keep()
	var profile: Profile = ProfileStore.load_from(save_path)
	if ProfileStore.loaded_generation > 0:
		push_warning("the newest profile saves were damaged; loaded the one %d back" % [
			ProfileStore.loaded_generation,
		])
	if profile.problem.is_empty():
		var quests: QuestData = QuestContent.load_quests()
		if not quests.problem.is_empty():
			push_warning("the quests can't be read, so none advance: " + quests.problem)
		profile.quests.book = quest_book_of(quests)
		var gear: GearContent = GearContent.load_gear()
		if not gear.problem.is_empty():
			push_warning("the gear can't be read, so gear found counts as materials: %s" % [
				gear.problem,
			])
		else:
			_gear_ids.assign(gear.items.keys())
		keeper = ProfileKeeper.new(profile, save_path)
	else:
		push_warning("the profile save can't be read, so nothing is saved: " + profile.problem)


func _process(_delta: float) -> void:
	if keeper != null:
		_report(keeper.save_if_due(Time.get_ticks_msec()))


func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	if leaving or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()


## Saves whatever is pending now.
func flush() -> void:
	if keeper != null:
		_report(keeper.flush())


## Takes `gain` into the profile (#73).
func take(gain: Gain) -> void:
	if keeper != null:
		_report(keeper.take(gain, Time.get_ticks_msec()))


## Drops the outbox's request `request` the world acknowledged (#771).
func acknowledge(request: String) -> void:
	if keeper != null:
		_report(keeper.acknowledge(request, Time.get_ticks_msec()))


## Spends one `item` the player uses, like a revive item (#656), and posts the request of `kind`
## (OutboxEntry.KINDS) with its `data` that uses it to the outbox, in one change (#818).
func spend_on(item: String, kind: int, data: int) -> void:
	if keeper != null:
		_report(keeper.spend_on(item, kind, data, Time.get_ticks_msec()))


## Whether loot with the id `item` is gear (#694) rather than a material.
func is_gear(item: String) -> bool:
	return _gear_ids.has(item)


## This machine's player's chosen personal color (#391), as 0xRRGGBB, or Profile.AUTO_COLOR, also
## while the save can't be read.
func personal_color() -> int:
	return keeper.profile.personal_color if keeper != null else Profile.AUTO_COLOR


## Keeps `color` (0xRRGGBB, or Profile.AUTO_COLOR) as this machine's player's personal color.
## Names this player's character (#399); returns why the name was refused, in words, or "".
func choose_name(typed: String) -> String:
	if keeper == null:
		return ""
	var problem: String = keeper.choose_name(typed, Time.get_ticks_msec())
	if Profile.name_problem(typed).is_empty():
		_report(problem)
	return problem


func choose_color(color: int) -> void:
	if keeper != null:
		_report(keeper.choose_color(color, Time.get_ticks_msec()))


## Moves the dominated monster `monster_id` to `place` in this player's order (#430).
func move_monster(monster_id: int, place: int) -> void:
	if keeper != null:
		_report(keeper.move_monster(monster_id, place, Time.get_ticks_msec()))


## Puts the gear `gear_id` into this player's `slot`, or empties it with "" (#690).
func equip(slot: String, gear_id: String) -> void:
	if keeper != null:
		_report(keeper.equip(slot, gear_id, Time.get_ticks_msec()))


## The quests the profile advances from `content`: none when any quest file couldn't be read, so
## progress waits for whole, sound data rather than advancing on part of it.
static func quest_book_of(content: QuestData) -> Dictionary[String, QuestDefinition]:
	var none: Dictionary[String, QuestDefinition] = {}
	return content.quests if content.problem.is_empty() else none


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the profile couldn't be saved: " + problem)
