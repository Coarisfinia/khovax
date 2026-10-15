class_name Settings
extends RefCounted
## The player's own settings on this device (#161), kept apart from the profile's game progress:
## every setting the player chose instead of "Auto", by its name. A setting that isn't here is Auto.
## Saved as JSON next to the profile. Settings aren't progress, so a file that can't be read is
## dropped for the defaults rather than refused.

const PATH: String = "user://settings.json"

## Each chosen setting's value, by the setting's name.
var chosen: Dictionary[String, int] = {}


## The settings saved at `path`, or none chosen when there's no file or it can't be read.
static func load_from(path: String = PATH) -> Settings:
	var settings: Settings = Settings.new()
	if not FileAccess.file_exists(path):
		return settings
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return settings
	var saved: Dictionary = parsed
	for setting: Variant in saved:
		var value: Variant = saved[setting]
		if setting is String and value is float:
			var number: float = value
			settings.chosen[setting] = int(number)
	return settings


## Saves the settings to `path`; returns why it couldn't, or "".
func save(path: String = PATH) -> String:
	return SaveStore.write_atomic(path, JSON.stringify(chosen, "\t", true) + "\n")
