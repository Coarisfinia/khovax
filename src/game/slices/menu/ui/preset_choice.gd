class_name PresetChoice
extends HostChoice
## The difficulty preset in the Settings tab (#1892, HostSettings.PRESETS): Easy, Standard or Hard,
## or Custom while the host changed a setting a preset sets. Stepping it, which only the host can,
## posts a request for each setting the preset it lands on sets otherwise, so it never keeps a
## preset of its own; until the world applied them, the row shows the choices waiting in the
## outbox, like every HostChoice.


func _init(running: Session = null, called: Array[String] = []) -> void:
	super(running, HostSettings.PRESET, called)


## The preset the settings are on, or Custom, for the row.
func label() -> String:
	var preset: int = HostSettings.preset_of(values())
	return as_seen(tr("Custom") if preset == HostSettings.CUSTOM else names[preset])


## Steps the preset `steps` presets on (back for fewer), stopping at the first and the last, and
## from Custom onto the preset with the wild monsters' factor first (HostSettings.preset_step);
## only the host can. Returns why it couldn't be kept, which is never.
func step(steps: int) -> String:
	if not is_host() or not post.is_valid():
		return ""
	var now: Dictionary[String, int] = values()
	for data: int in HostSettings.preset_requests(now, HostSettings.preset_step(now, steps)):
		post.call(OutboxEntry.HOST_SETTING, data)
	return ""


## The settings a preset sets, as the host chose them (HostChoice.current_of), by their keys.
func values() -> Dictionary[String, int]:
	var chosen: Dictionary[String, int] = {}
	for key: String in HostSettings.PRESETS[0]:
		chosen[key] = current_of(key)
	return chosen
