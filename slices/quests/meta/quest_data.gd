class_name QuestData
extends RefCounted
## The quests as QuestContent reads them, with the species their steps were checked against (#506:
## the slice holds its own kind, so the shared Content never names it).

## Every species, by id.
var species: Dictionary[String, Species] = {}
## Every quest, by id.
var quests: Dictionary[String, QuestDefinition] = {}
## Every territory a quest hands over (#638), by the code a command hands it over by
## (Territory.code): the instance's name and the faction's id.
var handovers: Dictionary[int, PackedStringArray] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""
