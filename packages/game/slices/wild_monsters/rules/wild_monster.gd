class_name WildMonster
extends RefCounted
## One wild monster's own data (#820), which WildMonsterFeature keeps by its entity id, so what
## belongs to one monster stays together: its species id, its short id (#700, which a dominated one
## keeps), its stacks of rage (#220; none once it faints), and what the region's legend
## says of it beyond its species: the event it emits when it faints (#541, "" for none and once
## emitted, so it's emitted once) and the quest target it is (#625, the content id a quest's step
## names it by, "" for none, kept after it faints).

var species: String = ""
var short_id: String = ""
var rage: int = 0
var emits: String = ""
var target: String = ""


## A wild monster of `of_species`, not enraged and unmarked, its short id still to draw. Its HP is
## HealthFeature's (#835).
static func of(of_species: String) -> WildMonster:
	var wild: WildMonster = WildMonster.new()
	wild.species = of_species
	return wild
