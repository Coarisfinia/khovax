class_name QuestData
extends RefCounted
## The quests as QuestContent reads them, with the species their steps were checked against (#506:
## the slice holds its own kind, so the shared Content never names it).

## Every species, by id.
var species: Dictionary[String, Species] = {}
## Every quest, by id.
var quests: Dictionary[String, QuestDefinition] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""
