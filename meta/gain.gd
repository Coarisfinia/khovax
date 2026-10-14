class_name Gain
extends RefCounted
## What the player just obtained in a run (#37): monsters caught and materials found. It's handed
## to the profile the moment it happens, not at the run's end, and saved at once (ProfileKeeper),
## so a crash mid-run never loses a catch (owner, #73).

var caught_species: Array[String] = []
var materials: Dictionary[String, int] = {}
