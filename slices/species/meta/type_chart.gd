class_name TypeChart
extends RefCounted
## The type chart (#68, #279): five families, each with its Lesser and Greater type. Families have
## no names; each is shown as an icon in a circle on its color. A species has one or two types,
## never two of one family.

## Each family's Lesser and Greater type, by family id.
const FAMILIES: Array[Array] = [
	["mana", "arcane"],
	["shadow", "abyss"],
	["might", "titan"],
	["growth", "nature"],
	["breeze", "tempest"],
]


## The family id of a type, or -1 for a type that isn't on the chart.
static func family_of(type: String) -> int:
	for family: int in FAMILIES.size():
		if FAMILIES[family].has(type):
			return family
	return -1
