class_name ProfileStore
extends RefCounted
## Where the profile is kept on this device, and loading and saving it there through SaveStore's
## envelopes and generations (#37, #179). It lives in the profile slice (#506): the core's SaveStore
## never names the profile.

const PATH: String = "user://profile.json"

## Which of the save's generations the last `load_from` read the profile from: 0 the newest, more
## when newer ones were damaged (SaveStore).
static var loaded_generation: int = 0


## The saved profile, or a new one when there's no save yet. Its `problem` says why when no
## generation can be read, and `loaded_generation` which one was when it wasn't the newest.
static func load_from(path: String = PATH) -> Profile:
	loaded_generation = 0
	if not SaveStore.exists(path):
		return Profile.new()
	var saved: SaveRead = SaveStore.read_save(path)
	if not saved.problem.is_empty():
		var refused: Profile = Profile.new()
		refused.problem = saved.problem
		return refused
	var profile: Profile = ProfileSave.parse(saved.text)
	loaded_generation = saved.generation
	return profile


## Saves the profile, and syncs it into the browser's storage on the web; returns why it couldn't,
## or "".
static func save(profile: Profile, path: String = PATH) -> String:
	var problem: String = SaveStore.write_save(path, ProfileSave.to_text(profile))
	if problem.is_empty():
		WebStorage.sync()
	return problem
