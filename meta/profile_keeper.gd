class_name ProfileKeeper
extends RefCounted
## Keeps the profile and its save in step (#37): every gain is taken over and saved to disk right
## away, atomically (SaveStore), so a crash at any moment keeps everything obtained before it
## (owner, #73). The run calls `take` whenever something is caught or found.

var profile: Profile
var path: String = SaveStore.PROFILE_PATH


func _init(kept: Profile, save_path: String = SaveStore.PROFILE_PATH) -> void:
	profile = kept
	path = save_path


## Takes over `gain` and saves; returns why it couldn't, or "". A refused gain changes nothing.
func take(gain: Gain) -> String:
	var problem: String = profile.apply(gain)
	if problem.is_empty():
		problem = SaveStore.save_profile(profile, path)
	return problem


## Counts a finished run and saves.
func finish_run() -> String:
	profile.runs_finished += 1
	return SaveStore.save_profile(profile, path)
