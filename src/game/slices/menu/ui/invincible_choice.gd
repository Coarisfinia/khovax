class_name InvincibleChoice
extends HostChoice
## The Settings tab's Invincible row, in its Debug submenu (#2273, #1777): whether this machine's
## player is invincible (HealthFeature, the same world store entry the `--invincible` launch option
## sets), Off or On. Every player chooses it for themselves, not only the host. A step posts their
## request to their profile's outbox (OutboxEntry.INVINCIBLE), which reaches the world in their next
## command, like the host's choices; until the world applied it, the row shows the choice waiting
## in the outbox.

## The row's setting, as the Settings tab names it.
const SETTING: String = "invincible"
## Its choices, as its request's data says them.
const OFF: int = 0
const ON: int = 1


func _init(running: Session = null, called: Array[String] = []) -> void:
	super(running, SETTING, called)


## Off or On, for the row.
func label() -> String:
	return names[current()]


## Steps it `steps` choices on (back for fewer), stopping at Off and On. Returns why it couldn't be
## kept, which is never: the profile keeps the request.
func step(steps: int) -> String:
	var chosen: int = clampi(current() + steps, OFF, ON)
	if chosen == current() or not post.is_valid():
		return ""
	post.call(OutboxEntry.INVINCIBLE, chosen)
	return ""


## The player's choice: the newest one waiting in their outbox, else what the world keeps.
func current() -> int:
	if outbox.is_valid():
		var waiting: int = -1
		for request: OutboxEntry in outbox.call():
			if request.kind == OutboxEntry.INVINCIBLE:
				waiting = request.data
		if waiting == OFF or waiting == ON:
			return waiting
	if session.world == null:
		return OFF
	var slot: int = session.input.slot if session.input != null else 0
	return ON if session.world.stored(slot, HealthFeature.ID).has(HealthFeature.INVINCIBLE) else OFF
