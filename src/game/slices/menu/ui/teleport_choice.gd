class_name TeleportChoice
extends HostChoice
## The Settings tab's teleport buttons, in its Debug submenu (#2274, #1777): one sends this
## machine's player to the debug zone (SentToDebugZone), the other back to the world's spawn
## (SentToWorldSpawn), whatever their respawn point. Every player teleports only themselves. A press
## posts their request
## to their profile's outbox (OutboxEntry.TELEPORT), which reaches the world in their next command,
## like the host's choices; it's a HostChoice only so the profile's tie hands it the outbox.

## The setting it's kept under, as the menu names its node.
const SETTING: String = "teleport"
## Its requests' data: to the debug zone, and back.
const TO_DEBUG_ZONE: int = 1
const BACK: int = 0


func _init(running: Session = null) -> void:
	super(running, SETTING)


## Sends this machine's player to the debug zone.
func to_debug_zone() -> void:
	_ask(TO_DEBUG_ZONE)


## Sends this machine's player back to the spawn.
func back() -> void:
	_ask(BACK)


func _ask(data: int) -> void:
	if post.is_valid():
		post.call(OutboxEntry.TELEPORT, data)
