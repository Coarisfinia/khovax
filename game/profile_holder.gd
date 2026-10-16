class_name ProfileHolder
extends Node
## Holds this machine's player's profile through a session (#37, #132): loaded at boot, every catch
## of that player and their loot from every chest opened (#124) taken over at once and saved
## debounced (ProfileKeeper, #73), and whatever is pending saved when the game quits or goes to the
## background. The same catches and chests advance the player's quests (#184), in the profile.
## Other players' catches go into their own profiles on their own machines (#74). A save that can't
## be read is reported and left alone, never overwritten.

## Where this machine's player's catches and finds come from (#184).
@export var bus: EventBus
## Whose catches are this machine's player's.
@export var input: LocalInput

## Where the profile is saved; tests point it elsewhere before the holder enters the tree.
var save_path: String = SaveStore.PROFILE_PATH
## Null when the save couldn't be read: nothing is taken or saved then.
var keeper: ProfileKeeper


func _ready() -> void:
	SaveStore.keep_web_storage()
	var profile: Profile = SaveStore.load_profile(save_path)
	if profile.loaded_generation > 0:
		push_warning("the newest profile saves were damaged; loaded the one %d back" % [
			profile.loaded_generation,
		])
	if profile.problem.is_empty():
		var quests: Content = Content.load_quests()
		if not quests.problem.is_empty():
			push_warning("the quests can't be read, so none advance: " + quests.problem)
		profile.quest_book = quest_book_of(quests)
		keeper = ProfileKeeper.new(profile, save_path)
	else:
		push_warning("the profile save can't be read, so nothing is saved: " + profile.problem)
	bus.subscribe(&"WildMonsterCaught", _on_event)
	bus.subscribe(&"ChestOpened", _on_event)
	bus.subscribe(&"LootFound", _on_event)
	bus.subscribe(&"CatchLoot", _on_event)


func _process(_delta: float) -> void:
	if keeper != null:
		_report(keeper.save_if_due(Time.get_ticks_msec()))


func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	var backgrounded: bool = what == NOTIFICATION_APPLICATION_PAUSED
	if keeper != null and (leaving or backgrounded):
		# Events still queued would otherwise be lost with the game.
		bus.flush()
		_report(keeper.flush())


func _on_event(event: RefCounted) -> void:
	if keeper == null:
		return
	var gain: Gain = _gain_of(event)
	if gain != null:
		_report(keeper.take(gain, Time.get_ticks_msec()))


## The quests the profile advances from `content`: none when any quest file couldn't be read, so
## progress waits for whole, sound data rather than advancing on part of it.
static func quest_book_of(content: Content) -> Dictionary[String, QuestDefinition]:
	var none: Dictionary[String, QuestDefinition] = {}
	return content.quests if content.problem.is_empty() else none


## What this machine's player gains from `event`, or null when it isn't theirs: their catch, or
## their own roll from an opened chest (every player rolls their own, owner, #124), which counts
## as a chest they opened for quests even when it rolled nothing, or from loot found on the ground
## (#203), which is no chest.
func _gain_of(event: RefCounted) -> Gain:
	var gain: Gain = Gain.new()
	if event is WildMonsterCaught:
		var caught: WildMonsterCaught = event as WildMonsterCaught
		if caught.catcher_slot == input.slot:
			gain.caught_species.append(caught.species)
	elif event is ChestOpened and (event as ChestOpened).loot.has(input.slot):
		gain.chests_opened = 1
		_add_loot(gain, (event as ChestOpened).loot[input.slot])
	elif event is LootFound and (event as LootFound).loot.has(input.slot):
		_add_loot(gain, (event as LootFound).loot[input.slot])
	elif event is CatchLoot and (event as CatchLoot).loot.has(input.slot):
		_add_loot(gain, (event as CatchLoot).loot[input.slot])
	var empty: bool = gain.caught_species.is_empty() and gain.chests_opened == 0
	empty = empty and gain.materials.is_empty()
	return null if empty else gain


## Adds a roll of loot, {item id: amount}, to `gain`'s materials.
static func _add_loot(gain: Gain, loot: Dictionary) -> void:
	for item: Variant in loot:
		var amount: int = loot[item]
		gain.materials[str(item)] = amount


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the profile couldn't be saved: " + problem)
