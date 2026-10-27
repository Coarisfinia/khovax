class_name ProfileHolder
extends Node
## Holds this machine's player's profile through a session (#37, #132): loaded at boot, what it
## gains taken over at once and saved debounced (ProfileKeeper, #73), and whatever is pending saved
## when the game quits or goes to the background. Its outbox (#771) and revive items (#656) change
## through what it's handed (ProfileTie, which ties it to the session, #831). The player's personal
## color (#391) is kept in it too, saved the same way. What later slices keep in the profile's file,
## like the player's quests, its `companions` read and write with it (#855). A save that can't be
## read is reported and left alone, never overwritten.

## A change (`change`), like finishing a quest, changing gear or a session's start posted a
## request to the profile's outbox (#771, #818), for the session to send.
signal outbox_posted

## What later slices keep in the profile's file, beside it.
@export var companions: Array[ProfileCompanion] = []

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
	var profile: Profile = ProfileStore.load_from(save_path, companions)
	if ProfileStore.loaded_generation > 0:
		push_warning("the newest profile saves were damaged; loaded the one %d back" % [
			ProfileStore.loaded_generation,
		])
	if profile.problem.is_empty():
		var gear: GearContent = GearContent.cached()
		if not gear.problem.is_empty():
			push_warning("the gear can't be read, so gear found counts as materials: %s" % [
				gear.problem,
			])
		else:
			_gear_ids.assign(gear.items.keys())
		keeper = ProfileKeeper.new(profile, save_path, companions)
		_drop_lost_nodes()
	else:
		push_warning("the profile save can't be read, so nothing is saved: " + profile.problem)


func _process(_delta: float) -> void:
	if keeper != null:
		_report(keeper.save_if_due(Time.get_ticks_msec()))


func _notification(what: int) -> void:
	var leaving: bool = what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE
	if leaving or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()


## Gives back the picks of the development nodes a later web dropped (#1435). Unread webs drop
## nothing: a monster's nodes are never given back over a web that couldn't be read.
func _drop_lost_nodes() -> void:
	var development: DevelopmentContent = DevelopmentContent.cached()
	if not development.problem.is_empty():
		push_warning("the development webs can't be read: " + development.problem)
		return
	keeper.drop_lost_nodes(development.webs)


## Saves whatever is pending now.
func flush() -> void:
	if keeper != null:
		_report(keeper.flush())


## Takes `gain` into the profile (#73).
func take(gain: Gain) -> void:
	if keeper != null:
		_report(keeper.take(gain, Time.get_ticks_msec()))


## Runs `changing` on this player's profile, a companion's part changing with it (like a quest
## finished, QuestKeeper, #855), saves it like a gain, and tells when it posted a request to the
## outbox (#771).
func change(changing: Callable) -> void:
	if keeper == null:
		return
	var posted: int = keeper.profile.outbox.entries.size()
	_report(keeper.change(changing, Time.get_ticks_msec()))
	_tell_posted(posted)


## Runs `changing` on this player's profile, a companion's part changing with it, without asking
## for a save: it goes with the next one (ProfileKeeper.note), like what they learn about a species
## (#1173).
func note(changing: Callable) -> void:
	if keeper != null:
		keeper.note(changing)


## Drops the outbox's request `request` the world acknowledged (#771).
func acknowledge(request: String) -> void:
	if keeper != null:
		_report(keeper.acknowledge(request, Time.get_ticks_msec()))


## The code up to which this player's profile saw every request of `kind` it sent acknowledged
## (Outbox.confirmed, #942, #968), for a command carrying one of that kind, or Command.NO_REQUEST
## without a profile.
func confirmed(kind: int) -> int:
	return keeper.profile.outbox.confirmed(kind) if keeper != null else Command.NO_REQUEST


## Draws the outbox's next ids above the request code `highest` the world holds for this player as
## a session starts (Outbox.catch_up, #942).
func catch_up_outbox(highest: int) -> void:
	if keeper != null:
		keeper.profile.outbox.catch_up(highest)


## Spends one `item` the player uses, like a revive item (#656), and posts the request of `kind`
## (OutboxEntry.KINDS) with its `data` that uses it to the outbox, in one change (#818), and tells
## when it posted it.
func spend_on(item: String, kind: int, data: int) -> void:
	if keeper == null:
		return
	var posted: int = keeper.profile.outbox.entries.size()
	_report(keeper.spend_on(item, kind, data, Time.get_ticks_msec()))
	_tell_posted(posted)


## Whether loot with the id `item` is gear (#694) rather than a material.
func is_gear(item: String) -> bool:
	return _gear_ids.has(item)


## This machine's player's chosen personal color (#391), as 0xRRGGBB, or Profile.AUTO_COLOR, also
## while the save can't be read.
func personal_color() -> int:
	return keeper.profile.personal_color if keeper != null else Profile.AUTO_COLOR


## Whether this machine's player chose a personal color (#391) rather than Auto: the players slice
## asks this, so it needn't name the profile's Auto (#851).
func chose_personal_color() -> bool:
	return personal_color() != Profile.AUTO_COLOR


## The path this machine's player leans toward (PathLeaning.toward), PathMark.NONE also while the
## save can't be read: their companion's eyes show it (#1063).
func leaning() -> String:
	return keeper.profile.leaning.toward() if keeper != null else PathMark.NONE


## Names this player's character (#399); returns why the name was refused, in words, or "".
func choose_name(typed: String) -> String:
	if keeper == null:
		return ""
	var problem: String = keeper.choose_name(typed, Time.get_ticks_msec())
	if Profile.name_problem(typed).is_empty():
		_report(problem)
	return problem


## Keeps `color` (0xRRGGBB, or Profile.AUTO_COLOR) as this machine's player's personal color.
func choose_color(color: int) -> void:
	if keeper != null:
		_report(keeper.choose_color(color, Time.get_ticks_msec()))


## Moves the dominated monster `short_id` to `place` in this player's order (#430).
func move_monster(short_id: String, place: int) -> void:
	if keeper != null:
		_report(keeper.move_monster(short_id, place, Time.get_ticks_msec()))


## Puts the gear `gear_id` into this player's `slot`, or empties it with "" (#690), and tells when
## that posted a request to the outbox for the world (GearRequests, #818).
func equip(slot: String, gear_id: String) -> void:
	if keeper == null:
		return
	var posted: int = keeper.profile.outbox.entries.size()
	_report(keeper.equip(slot, gear_id, Time.get_ticks_msec()))
	_tell_posted(posted)


## Catches the world up with this player's gear as a session starts (#818): `stored` is their
## trap's entry in its store (SpikesFeature), and a request goes to the outbox if it's behind.
func catch_up_gear(stored: Dictionary) -> void:
	if keeper == null:
		return
	var posted: int = keeper.profile.outbox.entries.size()
	_report(keeper.catch_up_gear(stored, Time.get_ticks_msec()))
	_tell_posted(posted)


## Catches the world up with who this player carries as a session starts (#818): `stored` is their
## party's entry in its store (CompanionFeature), and a run of requests goes to the outbox if it's
## behind.
func catch_up_party(stored: Dictionary) -> void:
	if keeper == null:
		return
	var posted: int = keeper.profile.outbox.entries.size()
	_report(keeper.catch_up_party(stored, Time.get_ticks_msec()))
	_tell_posted(posted)


## Tells when the outbox holds more requests than the `posted` it held before.
func _tell_posted(posted: int) -> void:
	if keeper.profile.outbox.entries.size() > posted:
		outbox_posted.emit()


## A save that failed is a warning, not an error: the game goes on, and the next save tries again.
func _report(problem: String) -> void:
	if not problem.is_empty():
		push_warning("the profile couldn't be saved: " + problem)
