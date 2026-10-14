class_name SaveStore
extends RefCounted
## Where the profile is saved on this device (#37): one JSON file in the user data folder.

const PROFILE_PATH: String = "user://profile.json"


## The saved profile, or a new one when there's no save yet. Its `problem` says why when the save
## exists but can't be read.
static func load_profile(path: String = PROFILE_PATH) -> Profile:
	if not FileAccess.file_exists(path):
		return Profile.new()
	return Profile.parse(FileAccess.get_file_as_string(path))


## Saves the profile; returns why it couldn't, or "".
static func save_profile(profile: Profile, path: String = PROFILE_PATH) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null or not file.store_string(profile.to_text() + "\n"):
		return "couldn't write %s" % path
	return ""
