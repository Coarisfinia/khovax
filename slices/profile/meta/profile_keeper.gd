class_name ProfileKeeper
extends RefCounted
## Keeps the profile and its save in step (#37). Every gain is taken over at once, and saved to
## disk at most once per SAVE_INTERVAL_MSEC (owner, #73): the first gain after a quiet spell is
## saved right away, and gains coming quickly after it are saved together when the interval has
## passed, so obtaining fifty things in a few seconds doesn't mean fifty saves. Ending the session
## (the game quitting) or going to the background flushes whatever is pending. A crash loses at most
## the gains of the last interval.
##
## Times are passed in, in milliseconds of any steady clock, so the keeper itself stays testable;
## the game calls `save_if_due` regularly with Time.get_ticks_msec().

## At most one save per this long.
const SAVE_INTERVAL_MSEC: int = 30_000

var profile: Profile
var path: String = ProfileStore.PATH
## What later slices keep in the profile's file, saved with it (#855).
var companions: Array[ProfileCompanion] = []
## Whether the profile has changes the save doesn't have yet.
var _pending: bool = false
var _last_save_msec: int = -SAVE_INTERVAL_MSEC


func _init(
		kept: Profile,
		save_path: String = ProfileStore.PATH,
		kept_beside: Array[ProfileCompanion] = [],
) -> void:
	profile = kept
	path = save_path
	companions = kept_beside


## Takes over `gain` at time `now_msec` and saves if one is due; returns why it couldn't, or "". A
## refused gain changes nothing.
func take(gain: Gain, now_msec: int) -> String:
	var problem: String = profile.apply(gain)
	if not problem.is_empty():
		return problem
	_pending = true
	return save_if_due(now_msec)


## Runs `changing` on the profile at time `now_msec`, a companion's part changing with it (#855),
## and saves like a gain; returns why it couldn't be saved, or "".
func change(changing: Callable, now_msec: int) -> String:
	changing.call(profile)
	_pending = true
	return save_if_due(now_msec)


## Takes over the player's choice of personal color (#391), `color` as 0xRRGGBB or
## Profile.AUTO_COLOR, at time `now_msec`, saved debounced like a gain; returns why it couldn't be
## taken or saved, or "". A color the save can't hold changes nothing.
func choose_color(color: int, now_msec: int) -> String:
	if color < Profile.AUTO_COLOR or color > Profile.MAX_COLOR:
		return "not a personal color: %d" % color
	profile.personal_color = color
	_pending = true
	return save_if_due(now_msec)


## Moves the dominated monster `monster_id` to `place` in the player's order (#430) and saves it
## like any choice; returns why it can't, or "".
func move_monster(monster_id: int, place: int, now_msec: int) -> String:
	var problem: String = profile.move_monster(monster_id, place)
	if not problem.is_empty():
		return problem
	_pending = true
	return save_if_due(now_msec)


## Puts the gear `gear_id` into the player's `slot`, or empties it with "" (#690), and posts the
## request that tells the world, if it needs to know (GearRequests, #818), in one change, saved like
## any choice; returns why it can't, or "".
func equip(slot: String, gear_id: String, now_msec: int) -> String:
	var problem: String = profile.gear.equip(slot, gear_id)
	if not problem.is_empty():
		return problem
	var _posted: bool = GearRequests.post_change(profile.gear, profile.outbox, slot)
	_pending = true
	return save_if_due(now_msec)


## Posts the request that tells a world whose store entry `stored` of the player's trap
## (SpikesFeature) isn't what's equipped (GearRequests.catch_up, #818), saved like any change;
## returns why it couldn't be saved, or "".
func catch_up_gear(stored: Dictionary, now_msec: int) -> String:
	if not GearRequests.catch_up(profile.gear, profile.outbox, stored):
		return ""
	_pending = true
	return save_if_due(now_msec)


## Names the player's character `typed` (#399), its spaces at either end dropped, and saves it like
## any choice; returns why it can't, in words, or "".
func choose_name(typed: String, now_msec: int) -> String:
	var problem: String = Profile.name_problem(typed)
	if not problem.is_empty():
		return problem
	profile.character_name = typed.strip_edges()
	_pending = true
	return save_if_due(now_msec)


## Posts the run of requests that tells a world whose party entry `stored` (CompanionFeature) isn't
## who the player carries (PartyRequests.catch_up, #818), saved like any change; returns why it
## couldn't be saved, or "".
func catch_up_party(stored: Dictionary, now_msec: int) -> String:
	var party: CarriedMonsters = CarriedMonsters.new()
	for monster: DominatedMonster in profile.carried_monsters():
		party = party.add(monster.short_id, monster.species)
	if not PartyRequests.catch_up(party, profile.outbox, stored):
		return ""
	_pending = true
	return save_if_due(now_msec)


## Spends one of the item `item` the player holds and posts a request of `kind` (OutboxEntry.KINDS)
## with its `data` to the outbox (#771, #818), in one change, so a save never has one without the
## other, and saves it like any change; returns why it can't, or "".
func spend_on(item: String, kind: int, data: int, now_msec: int) -> String:
	var problem: String = profile.spend(item)
	if not problem.is_empty():
		return problem
	var _posted: OutboxEntry = profile.outbox.post(kind, data)
	_pending = true
	return save_if_due(now_msec)


## Drops the request `request` the world acknowledged (#771) from the outbox, and saves it like
## any change; returns why it couldn't be saved, or "". One not in the outbox changes nothing.
func acknowledge(request: String, now_msec: int) -> String:
	if not profile.outbox.drop(request):
		return ""
	_pending = true
	return save_if_due(now_msec)


## Saves pending changes if the last save is at least SAVE_INTERVAL_MSEC old; returns why it
## couldn't, or "".
func save_if_due(now_msec: int) -> String:
	if not _pending or now_msec - _last_save_msec < SAVE_INTERVAL_MSEC:
		return ""
	_last_save_msec = now_msec
	return flush()


## Saves pending changes now (the session ends or the game goes to the background); returns why it
## couldn't, or "".
func flush() -> String:
	if not _pending:
		return ""
	var problem: String = ProfileStore.save(profile, path, companions)
	_pending = not problem.is_empty()
	return problem


## Saves everything pending when a session ends.
func end_session() -> String:
	_pending = true
	return flush()
