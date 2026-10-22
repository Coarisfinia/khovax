class_name FeatureSetup
extends RefCounted
## What a slice's factory builds an instance's feature from (#823): the instance's region and its
## blueprint's settings, as plain ids and numbers, so a slice before the blueprints can read them.
## The content data the factories read is each kind's `cached` one (ContentCatalog, #816).

## The instance's blueprint id.
var instance: String = ""
## The region the instance is loaded with, its variant's when it has one.
var region: Region
## Its instance loot table's id, or "" (Blueprint.loot_table).
var loot_table: String = ""
## Its chest loot table's id, or "" (Blueprint.chest_table).
var chest_table: String = ""
## The species its wild monster spots roll from, species id to weight (Blueprint.wild_species).
var wild_species: Dictionary[String, int] = {}
