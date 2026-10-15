class_name SaveStore
extends RefCounted
## Where the profile is saved on this device (#37): one JSON file in the user data folder, written
## so that a crash never loses the last good save.

const PROFILE_PATH: String = "user://profile.json"


## The saved profile, or a new one when there's no save yet. Its `problem` says why when the save
## exists but can't be read.
static func load_profile(path: String = PROFILE_PATH) -> Profile:
	if not FileAccess.file_exists(path):
		return Profile.new()
	return Profile.parse(FileAccess.get_file_as_string(path))


## Saves the profile; returns why it couldn't, or "".
static func save_profile(profile: Profile, path: String = PROFILE_PATH) -> String:
	return write_atomic(path, profile.to_text() + "
")


## Writes `text` to `path`; returns why it couldn't, or "". The new file is written next to the old
## one first and only then takes its place, so a crash or a full disk mid-write never loses the last
## good save.
static func write_atomic(path: String, text: String) -> String:
	var temporary: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null or not file.store_string(text):
		return "couldn't write %s" % temporary
	file.close()
	var moved: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path),
	)
	if moved != OK:
		return "couldn't replace %s with the new save" % path
	return ""
