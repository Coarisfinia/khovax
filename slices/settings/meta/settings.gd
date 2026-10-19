class_name Settings
extends RefCounted
## The player's own settings on this device (#161), kept apart from the profile's game progress:
## every setting the player chose instead of "Auto", by its name. A setting that isn't here is Auto.
## Saved as JSON next to the profile and kept like a save (SaveStore: checksum, older generations).
## Settings aren't progress, so when no generation can be read they're dropped for the defaults
## rather than refused.

const PATH: String = "user://settings.json"

## Each chosen setting's value, by the setting's name.
var chosen: Dictionary[String, int] = {}


## The settings saved at `path`, or none chosen when there's no file or it can't be read.
static func load_from(path: String = PATH) -> Settings:
	var settings: Settings = Settings.new()
	if not SaveStore.exists(path):
		return settings
	var saved_read: SaveRead = SaveStore.read_save(path)
	if not saved_read.problem.is_empty():
		return settings
	var parsed: Variant = JSON.parse_string(saved_read.text)
	if not parsed is Dictionary:
		return settings
	var saved: Dictionary = parsed
	for setting: Variant in saved:
		var value: Variant = saved[setting]
		if setting is String and (value is float or value is int):
			var number: float = value
			settings.chosen[setting] = int(number)
	return settings


## Saves the settings to `path`, and syncs them into the browser's storage on the web; returns why
## it couldn't, or "".
func save(path: String = PATH) -> String:
	var problem: String = SaveStore.write_save(path, JSON.stringify(chosen, "\t", true))
	if problem.is_empty():
		WebStorage.sync()
	return problem
