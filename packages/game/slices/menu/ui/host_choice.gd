class_name HostChoice
extends Node
## One of the world's settings in the Settings tab (#1309, HostSettings), like the difficulty
## (#1315): what the world's host chose, and stepping it, which only the host can. A step posts the
## host's request to their profile's outbox (OutboxEntry.HOST_SETTING), which reaches the world in
## their next command, so it changes on the fly, the same way on every machine. Until the world
## applied it, the row shows the choice waiting in the outbox.

var session: Session
## This player's requests waiting in their profile's outbox (an Array[OutboxEntry]), and what posts
## one there (its kind and data): handed in by the profile (ProfilePanelsTie), whose slice comes
## after the menu's; none without it.
var outbox: Callable = Callable()
var post: Callable = Callable()
## The setting (a key of HostSettings.CHOICES), and what each of its choices is called, in order.
var setting: String
var names: Array[String] = []


func _init(running: Session = null, key: String = "", called: Array[String] = []) -> void:
	session = running
	setting = key
	names = called


## What the setting is on, for the row, and beside it for a player who isn't the host that they
## see it but can't change it.
func label() -> String:
	return as_seen(names[HostSettings.CHOICES[setting].find(current())])


## `named` (what the setting is on) as the row shows it: for a player who isn't the host, with
## the words that they see it but can't change it.
func as_seen(named: String) -> String:
	return named if is_host() else tr("%s (the host chooses)") % named


## Steps the setting `steps` choices on (back for fewer), stopping at the first and the last; only
## the host can. Returns why it couldn't be kept, which is never: the profile keeps the request.
func step(steps: int) -> String:
	var choices: Array = HostSettings.CHOICES[setting]
	var chosen: int = choices[clampi(choices.find(current()) + steps, 0, choices.size() - 1)]
	if not is_host() or chosen == current() or not post.is_valid():
		return ""
	post.call(OutboxEntry.HOST_SETTING, HostSettings.request_data(setting, chosen))
	return ""


## Whether this machine's player is the host.
func is_host() -> bool:
	return session.input == null or session.input.slot == HostSettings.HOST


## The choice the host made: the newest one waiting in this player's outbox, else the world's.
func current() -> int:
	return current_of(setting)


## The host's choice of `key` (a key of HostSettings.CHOICES), as `current` finds it.
func current_of(key: String) -> int:
	if outbox.is_valid() and is_host():
		var waiting: int = -1
		for request: OutboxEntry in outbox.call():
			var asks: bool = HostSettings.setting_of(request.data) == key
			if request.kind == OutboxEntry.HOST_SETTING and asks:
				waiting = HostSettings.value_of(request.data)
		if HostSettings.CHOICES[key].has(waiting):
			return waiting
	if session.world == null:
		return HostSettings.default_of(key)
	var host: PlayerStore = session.world.stores[HostSettings.HOST]
	return HostSettings.chosen(host.stored(HostSettings.FEATURE_ID), key)
