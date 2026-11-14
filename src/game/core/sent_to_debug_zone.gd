class_name SentToDebugZone
extends SentToSpawn
## Event: a player is sent to the debug zone this tick (#2274, the Settings tab's Debug submenu):
## the instance the world's source names for it (InstanceSource.debug_zone), which no exit leads
## to. The world moves them onto their start there, after every instance has stepped, as a new
## entity, like one sent to the spawn; while there's no debug zone, or it can't load, they stay.
## It's a SentToSpawn, so whatever a player leaving their instance ends (an escort) ends with it.
