class_name HostChoice
extends Node
## One of the world's settings in the Settings tab (#1309, HostSettings), like the difficulty
## (#1315): what the world's host chose, and stepping it, which only the host can. A step posts the
## host's request to their profile's outbox (OutboxEntry.HOST_SETTING), which reaches the world in
## their next command, so it changes on the fly, the same way on every machine. Until the world
## applied it, the row shows the choice waiting in the outbox.

## Beside the choice for a player who isn't the host, who sees it but can't change it.
const HOSTS: String = "%s (the host chooses)"

var session: Session
## The setting (a key of HostSettings.CHOICES), and what each of its choices is called, in order.
var setting: String
var names: Array[String] = []


func _init(running: Session = null, key: String = "", called: Array[String] = []) -> void:
	session = running
	setting = key
	names = called


## What the setting is on, for the row.
func label() -> String:
	var named: String = names[HostSettings.CHOICES[setting].find(current())]
	return named if is_host() else HOSTS % named


## Steps the setting `steps` choices on (back for fewer), stopping at the first and the last; only
## the host can. Returns why it couldn't be kept, which is never: the profile keeps the request.
func step(steps: int) -> String:
	var choices: Array = HostSettings.CHOICES[setting]
	var chosen: int = choices[clampi(choices.find(current()) + steps, 0, choices.size() - 1)]
	if not is_host() or chosen == current() or session.holder == null:
		return ""
	session.holder.change(_post.bind(HostSettings.request_data(setting, chosen)))
	return ""


## Whether this machine's player is the host.
func is_host() -> bool:
	return session.input == null or session.input.slot == HostSettings.HOST


## The choice the host made: the newest one waiting in this player's outbox, else the world's.
func current() -> int:
	var holder: ProfileHolder = session.holder
	if holder != null and holder.keeper != null and is_host():
		var waiting: int = -1
		for request: OutboxEntry in holder.keeper.profile.outbox.entries:
			var asks: bool = HostSettings.setting_of(request.data) == setting
			if request.kind == OutboxEntry.HOST_SETTING and asks:
				waiting = HostSettings.value_of(request.data)
		if HostSettings.CHOICES[setting].has(waiting):
			return waiting
	if session.world == null:
		return HostSettings.default_of(setting)
	var host: PlayerStore = session.world.stores[HostSettings.HOST]
	return HostSettings.chosen(host.stored(HostSettings.FEATURE_ID), setting)


## Posts the request `data` to `profile`'s outbox (the change hands the profile first, then the
## bound data).
func _post(profile: Profile, data: int) -> void:
	var _posted: OutboxEntry = profile.outbox.post(OutboxEntry.HOST_SETTING, data)
