class_name SentToWorldSpawn
extends SentToSpawn
## Event: a player is sent to the world's spawn this tick, whatever their respawn point (#2274, the
## Settings tab's Debug submenu's way back from the debug zone): onto their start in the starting
## instance, so a respawn point set in the debug zone can't keep them there. It's a SentToSpawn,
## so whatever a player leaving their instance ends (an escort) ends with it.
