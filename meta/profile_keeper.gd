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
var path: String = SaveStore.PROFILE_PATH
## Whether the profile has changes the save doesn't have yet.
var _pending: bool = false
var _last_save_msec: int = -SAVE_INTERVAL_MSEC


func _init(kept: Profile, save_path: String = SaveStore.PROFILE_PATH) -> void:
	profile = kept
	path = save_path


## Takes over `gain` at time `now_msec` and saves if one is due; returns why it couldn't, or "". A
## refused gain changes nothing.
func take(gain: Gain, now_msec: int) -> String:
	var problem: String = profile.apply(gain)
	if not problem.is_empty():
		return problem
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
	var problem: String = SaveStore.save_profile(profile, path)
	_pending = not problem.is_empty()
	return problem


## Saves everything pending when a session ends.
func end_session() -> String:
	_pending = true
	return flush()
