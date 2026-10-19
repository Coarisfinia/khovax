class_name ProfileHolder
extends Node
## Holds this machine's player's profile through a session (#37, #132): loaded at boot, every
## domination of that player and their loot from every chest opened (#124) and every wild monster
## felled (#629) taken over at once and saved debounced (ProfileKeeper, #73), and whatever is
## pending saved when the game quits or goes to the background. The same dominations and chests
## advance the player's quests (#184), in the profile, and so do the places they step into (#339),
## the region pieces and instances they enter (#350, #370), the answers they choose in dialogs
## (#636) and the events that change the world (#707), which every player gains. A territory quest
## it finishes hands its territory over in this player's next command (#638), so the world changes
## in a tick, the same on every machine and in the replay. The player's personal color (#391) is
## kept in it too, saved the same way.
## Other players' dominations go into their own profiles on their own machines (#74). A save that
## can't be read is reported and left alone, never overwritten.

## Where this machine's player's dominations and finds come from (#184).
@export var bus: EventBus
## Whose dominations are this machine's player's.
@export var input: LocalInput

## Where the profile is saved; tests point it elsewhere before the holder enters the tree.
var save_path: String = ProfileStore.PATH
## Null when the save couldn't be read: nothing is taken or saved then.
var keeper: ProfileKeeper


## Loads the profile on entering the tree, before any node's _ready: the driver starts the session
## in its own, with this player's companion from the profile (#338).
func _enter_tree() -> void:
	if keeper != null:
		return
	WebStorage.keep()
	var profile: Profile = ProfileStore.load_from(save_path)
	if profile.loaded_generation > 0:
		push_warning("the newest profile saves were damaged; loaded the one %d back" % [
			profile.loaded_generation,
		])
	if profile.problem.is_empty():
		var quests: QuestData = QuestContent.load_quests()
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
	bus.subscribe(&"Harvested", _on_event)
	bus.subscribe(&"PlaceReached", _on_event)
	bus.subscribe(&"PieceEntered", _on_event)
	bus.subscribe(&"InstanceEntered", _on_event)
	bus.subscribe(&"DialogAnswered", _on_event)
	bus.subscribe(&"WorldChanged", _on_event)


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
		var done: int = keeper.profile.quests_done.size()
		_report(keeper.take(gain, Time.get_ticks_msec()))
		_hand_over_since(done)


## Hands over the territory of every territory quest finished after the first `done` ones (#638),
## in the order finished, in this player's next commands.
func _hand_over_since(done: int) -> void:
	var profile: Profile = keeper.profile
	for index: int in range(done, profile.quests_done.size()):
		# A quest is finished only from the book, so the book has it.
		var territory: QuestTerritory = profile.quest_book[profile.quests_done[index]].territory
		if territory != null:
			input.hand_over(Territory.code(territory.instance, territory.faction))


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


## What this machine's player gains from `event`, or null when it isn't theirs: their domination, or
## their own roll from an opened chest (every player rolls their own, owner, #124), which counts
## as a chest they opened for quests even when it rolled nothing, or from loot found on the ground
## (#203), which is no chest, or from a wild monster felled (#629); a place they stepped into
## (#339), a region piece or an instance they entered (#350, #370), or an answer they chose in a
## dialog (#636); or an event that changed the world (#707), which is every player's, wherever they
## are: the world raises it on every machine.
func _gain_of(event: RefCounted) -> Gain:
	var gain: Gain = Gain.new()
	if event is WildMonsterDominated:
		var dominated: WildMonsterDominated = event as WildMonsterDominated
		if dominated.dominator_slot == input.slot:
			gain.dominated_species.append(dominated.species)
			gain.dominated_short_ids.append(dominated.short_id)
	elif event is ChestOpened and (event as ChestOpened).loot.has(input.slot):
		gain.chests_opened = 1
		_add_loot(gain, (event as ChestOpened).loot[input.slot])
	elif _rolls_of(event).has(input.slot):
		_add_loot(gain, _rolls_of(event)[input.slot])
	else:
		_add_quest_fact(gain, event, input.slot)
	var empty: bool = gain.dominated_species.is_empty() and gain.chests_opened == 0
	empty = empty and gain.materials.is_empty() and gain.places_reached.is_empty()
	empty = empty and gain.pieces_entered.is_empty() and gain.instances_entered.is_empty()
	empty = empty and gain.answers_chosen.is_empty()
	empty = empty and gain.world_events.is_empty()
	return null if empty else gain


## Adds to `gain` the fact only quests count that `event` is for the player in `slot`, if any: a
## place they reached, a region piece or an instance they entered, an answer they chose, or an event
## that changed the world, which is every player's.
static func _add_quest_fact(gain: Gain, event: RefCounted, slot: int) -> void:
	if event is PlaceReached and (event as PlaceReached).slot == slot:
		gain.places_reached.append((event as PlaceReached).place)
	elif event is PieceEntered and (event as PieceEntered).slot == slot:
		gain.pieces_entered.append((event as PieceEntered).piece)
	elif event is InstanceEntered and (event as InstanceEntered).slot == slot:
		gain.instances_entered.append((event as InstanceEntered).instance)
	elif event is DialogAnswered and (event as DialogAnswered).slot == slot:
		var answered: DialogAnswered = event as DialogAnswered
		gain.answers_chosen.append(QuestStep.answer_key(answered.dialog, answered.answer))
	elif event is WorldChanged:
		gain.world_events.append((event as WorldChanged).event_name)


## Every player's loot from `event`, by slot, when it's loot that counts as no chest: found on the
## ground (#203), from a domination (#86) or from a felled wild monster (#629). None otherwise.
static func _rolls_of(event: RefCounted) -> Dictionary[int, Dictionary]:
	var none: Dictionary[int, Dictionary] = {}
	if event is LootFound:
		return (event as LootFound).loot
	if event is DominationLoot:
		return (event as DominationLoot).loot
	if event is Harvested:
		return (event as Harvested).loot
	return none


## Adds a roll of loot, {item id: amount}, to `gain`'s materials.
static func _add_loot(gain: Gain, loot: Dictionary) -> void:
	for item: Variant in loot:
		var amount: int = loot[item]
		gain.materials[str(item)] = amount


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the profile couldn't be saved: " + problem)
