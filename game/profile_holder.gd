class_name ProfileHolder
extends Node
## Holds this machine's player's profile through a session (#37, #132): loaded at boot, every catch
## of that player and their loot from every chest opened (#124) taken over at once and saved
## debounced (ProfileKeeper, #73), and whatever is pending saved when the game quits or goes to the
## background. Other players' catches go into their own profiles on their own machines (#74). A save
## that can't be read is reported and left alone, never overwritten.

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
		keeper = ProfileKeeper.new(profile, save_path)
	else:
		push_warning("the profile save can't be read, so nothing is saved: " + profile.problem)
	bus.subscribe(&"WildMonsterCaught", _on_event)
	bus.subscribe(&"ChestOpened", _on_event)


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


## What this machine's player gains from `event`, or null when it isn't theirs: their catch, or
## their own roll from an opened chest (every player rolls their own, owner, #124).
func _gain_of(event: RefCounted) -> Gain:
	var gain: Gain = Gain.new()
	if event is WildMonsterCaught:
		var caught: WildMonsterCaught = event as WildMonsterCaught
		if caught.catcher_slot == input.slot:
			gain.caught_species.append(caught.species)
	elif event is ChestOpened:
		var loot: Dictionary = (event as ChestOpened).loot.get(input.slot, {})
		for item: Variant in loot:
			var amount: int = loot[item]
			gain.materials[str(item)] = amount
	var empty: bool = gain.caught_species.is_empty() and gain.materials.is_empty()
	return null if empty else gain


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the profile couldn't be saved: " + problem)
