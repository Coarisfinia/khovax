class_name RunResult
extends RefCounted
## What a finished run hands back to the profile (#37): the species caught and the materials found.
## The run itself is deterministic; its result is read from the run's end, then applied to the
## profile, which is the only thing that lasts.

var caught_species: Array[String] = []
var materials: Dictionary[String, int] = {}
