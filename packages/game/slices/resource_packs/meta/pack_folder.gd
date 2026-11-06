class_name PackFolder
extends RefCounted
## The folder a player's resource packs are found in (#1942). Stub: one folder everywhere.

const USER: String = "user://packs/"


static func path() -> String:
	return USER
