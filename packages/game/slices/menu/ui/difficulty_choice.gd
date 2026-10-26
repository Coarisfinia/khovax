class_name DifficultyChoice
extends Node
## The difficulty in the Settings tab's Difficulty submenu (#1315): what the world's host chose
## (HostSettings), and stepping it, which only the host can. A step posts the host's request to
## their profile's outbox (OutboxEntry.HOST_SETTING), which reaches the world in their next command,
## so it changes on the fly, the same way on every machine. Until the world applied it, the row
## shows the choice waiting in the outbox.

## What each difficulty is called, by HostSettings.DIFFICULTIES' order.
const NAMES: Array[String] = ["Easy", "Standard", "Hard"]
## Beside the difficulty for a player who isn't the host, who sees it but can't change it.
const HOSTS: String = "%s (the host chooses)"

var session: Session


func _init(running: Session = null) -> void:
	session = running


## What the difficulty is on, for the row.
func label() -> String:
	var named: String = NAMES[HostSettings.DIFFICULTIES.find(current())]
	return named if is_host() else HOSTS % named


## Steps the difficulty `steps` on (back for fewer), stopping at Easy and Hard; only the host can.
## Returns why it couldn't be kept, which is never: the profile keeps the request.
func step(steps: int) -> String:
	var at: int = HostSettings.DIFFICULTIES.find(current())
	var chosen: int = HostSettings.DIFFICULTIES[clampi(at + steps, 0, NAMES.size() - 1)]
	if not is_host() or chosen == current() or session.holder == null:
		return ""
	var data: int = HostSettings.request_data(HostSettings.DIFFICULTY, chosen)
	session.holder.change(_post.bind(data))
	return ""


## Whether this machine's player is the host.
func is_host() -> bool:
	return session.input == null or session.input.slot == HostSettings.HOST


## The difficulty the host chose: the newest one waiting in this player's outbox, else the world's.
func current() -> int:
	var holder: ProfileHolder = session.holder
	if holder != null and holder.keeper != null and is_host():
		var waiting: int = -1
		for request: OutboxEntry in holder.keeper.profile.outbox.entries:
			var data: int = request.data
			var asks: bool = HostSettings.setting_of(data) == HostSettings.DIFFICULTY
			if request.kind == OutboxEntry.HOST_SETTING and asks:
				waiting = HostSettings.value_of(data)
		if HostSettings.DIFFICULTIES.has(waiting):
			return waiting
	if session.world == null:
		return HostSettings.STANDARD
	var host: PlayerStore = session.world.stores[HostSettings.HOST]
	return HostSettings.chosen(host.stored(HostSettings.FEATURE_ID), HostSettings.DIFFICULTY)


## Posts the request for the difficulty `data` to `profile`'s outbox.
func _post(data: int, profile: Profile) -> void:
	var _posted: OutboxEntry = profile.outbox.post(OutboxEntry.HOST_SETTING, data)
