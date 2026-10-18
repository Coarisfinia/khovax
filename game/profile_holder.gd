class_name ProfileHolder
extends Node
## Holds this machine's player's profile through a session (#37, #132): loaded at boot, every
## domination of that player and their loot from every chest opened (#124) taken over at once and
## saved debounced (ProfileKeeper, #73), and whatever is pending saved when the game quits or goes
## to the background. The same dominations and chests advance the player's quests (#184), in the
## profile, and so do the places they step into (#339) and the region pieces and instances they
## enter (#350, #370). The player's personal color (#391) is kept in it too, saved the same way.
## Other players' dominations go into their own profiles on their own machines (#74). A save that
## can't be read is reported and left alone, never overwritten.

## Where this machine's player's dominations and finds come from (#184).
@export var bus: EventBus
## Whose dominations are this machine's player's.
@export var input: LocalInput

## Where the profile is saved; tests point it elsewhere before the holder enters the tree.
var save_path: String = SaveStore.PROFILE_PATH
## Null when the save couldn't be read: nothing is taken or saved then.
var keeper: ProfileKeeper


## Loads the profile on entering the tree, before any node's _ready: the driver starts the session
## in its own, with this player's companion from the profile (#338).
func _enter_tree() -> void:
	if keeper != null:
		return
	SaveStore.keep_web_storage()
	var profile: Profile = SaveStore.load_profile(save_path)
	if profile.loaded_generation > 0:
		push_warning("the newest profile saves were damaged; loaded the one %d back" % [
			profile.loaded_generation,
		])
	if profile.problem.is_empty():
		var quests: Content = QuestContent.load_quests()
		if not quests.problem.is_empty():
			push_warning("the quests can't be read, so none advance: " + quests.problem)
		profile.quest_book = quest_book_of(quests)
		keeper = ProfileKeeper.new(profile, save_path)
	else:
		push_warning("the profile save can't be read, so nothing is saved: " + profile.problem)


func _ready() -> void:
	bus.subscribe(&"WildMonsterDominated", _on_event)
	bus.subscribe(&"ChestOpened", _on_event)
	bus.subscribe(&"LootFound", _on_event)
	bus.subscribe(&"DominationLoot", _on_event)
	bus.subscribe(&"PlaceReached", _on_event)
	bus.subscribe(&"PieceEntered", _on_event)
	bus.subscribe(&"InstanceEntered", _on_event)


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


## This machine's player's chosen personal color (#391), as 0xRRGGBB, or Profile.AUTO_COLOR, also
## while the save can't be read.
func personal_color() -> int:
	return keeper.profile.personal_color if keeper != null else Profile.AUTO_COLOR


## Keeps `color` (0xRRGGBB, or Profile.AUTO_COLOR) as this machine's player's personal color.
func choose_color(color: int) -> void:
	if keeper != null:
		_report(keeper.choose_color(color, Time.get_ticks_msec()))


## Moves the dominated monster `monster_id` to `place` in this player's order (#430).
func move_monster(monster_id: int, place: int) -> void:
	if keeper != null:
		_report(keeper.move_monster(monster_id, place, Time.get_ticks_msec()))


## The quests the profile advances from `content`: none when any quest file couldn't be read, so
## progress waits for whole, sound data rather than advancing on part of it.
static func quest_book_of(content: Content) -> Dictionary[String, QuestDefinition]:
	var none: Dictionary[String, QuestDefinition] = {}
	return content.quests if content.problem.is_empty() else none


## What this machine's player gains from `event`, or null when it isn't theirs: their domination, or
## their own roll from an opened chest (every player rolls their own, owner, #124), which counts
## as a chest they opened for quests even when it rolled nothing, or from loot found on the ground
## (#203), which is no chest; a place they stepped into (#339), or a region piece or an instance
## they entered (#350, #370).
func _gain_of(event: RefCounted) -> Gain:
	var gain: Gain = Gain.new()
	if event is WildMonsterDominated:
		var dominated: WildMonsterDominated = event as WildMonsterDominated
		if dominated.dominator_slot == input.slot:
			gain.dominated_species.append(dominated.species)
	elif event is ChestOpened and (event as ChestOpened).loot.has(input.slot):
		gain.chests_opened = 1
		_add_loot(gain, (event as ChestOpened).loot[input.slot])
	elif event is LootFound and (event as LootFound).loot.has(input.slot):
		_add_loot(gain, (event as LootFound).loot[input.slot])
	elif event is DominationLoot and (event as DominationLoot).loot.has(input.slot):
		_add_loot(gain, (event as DominationLoot).loot[input.slot])
	elif event is PlaceReached and (event as PlaceReached).slot == input.slot:
		gain.places_reached.append((event as PlaceReached).place)
	elif event is PieceEntered and (event as PieceEntered).slot == input.slot:
		gain.pieces_entered.append((event as PieceEntered).piece)
	elif event is InstanceEntered and (event as InstanceEntered).slot == input.slot:
		gain.instances_entered.append((event as InstanceEntered).instance)
	var empty: bool = gain.dominated_species.is_empty() and gain.chests_opened == 0
	empty = empty and gain.materials.is_empty() and gain.places_reached.is_empty()
	empty = empty and gain.pieces_entered.is_empty() and gain.instances_entered.is_empty()
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
