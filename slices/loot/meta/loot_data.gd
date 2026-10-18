class_name LootData
extends RefCounted
## The loot tables as LootContent reads them (#506: the slice holds its own kind, so the shared
## Content never names it).

## Every loot table, by id.
var loot_tables: Dictionary[String, LootTable] = {}
## Why the data couldn't be read, or "" when it could.
var problem: String = ""
