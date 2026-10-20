class_name Gain
extends RefCounted
## What the player just obtained in the world (#37): monsters dominated, materials and gear found
## (#694), and the facts only quests count (#817): a quest target dominated, a chest opened, a place
## reached, a region piece or an instance entered, an answer chosen in a dialog, or one of the
## world's events, which every player gains (#707). Dominations and loot count toward quests too,
## as the profile takes them over.
## Loot counts toward quests once the player obtains it (#686): loot landing in their missed-loot
## chest (#242) isn't obtained yet, and taking it out is, like taking it from their own chest
## (#293), so only taking it out hands a Gain.
## It's handed to the profile the moment it happens, not at the session's end, and saved at once
## (ProfileKeeper), so a crash mid-session never loses a domination (owner, #73).

## The instance it happened in, by blueprint name (#769), where its dominations and loot count; ""
## for none. Each fact names its own.
var instance: String = ""
var dominated_species: Array[String] = []
## The short id of each dominated monster (#700), in the same order. A monster this lacks one for
## gets a stand-in (ShortId.stand_in).
var dominated_short_ids: Array[String] = []
var materials: Dictionary[String, int] = {}
## Gear found (#694), by id: how many of each.
var gear: Dictionary[String, int] = {}
## What only quests count, in the order it happened.
var facts: Array[QuestFact] = []


## Whether it holds nothing at all.
func is_empty() -> bool:
	return (dominated_species.is_empty() and materials.is_empty() and gear.is_empty()
		and facts.is_empty())
