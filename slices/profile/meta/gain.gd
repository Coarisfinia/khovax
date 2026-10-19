class_name Gain
extends RefCounted
## What the player just obtained in the world (#37): monsters dominated, materials and gear found
## (#694), chests opened, places reached, region pieces and instances entered, answers chosen in
## dialogs, the facts quests count too (#184, #339, #350, #370, #636), and the world's events, which
## every player gains (#707).
## Loot counts toward quests once the player obtains it (#686): loot landing in their missed-loot
## chest (#242) isn't obtained yet, and taking it out is, like taking it from their own chest
## (#293), so only taking it out hands a Gain.
## It's handed to the profile the moment it happens, not at the session's end, and saved at once
## (ProfileKeeper), so a crash mid-session never loses a domination (owner, #73).

## The instance it happened in, by blueprint name (#769), which a quest step naming an instance asks
## for; "" for the world's events, which happen everywhere.
var instance: String = ""
var dominated_species: Array[String] = []
## The short id of each dominated monster (#700), in the same order. A monster this lacks one for
## gets a stand-in (ShortId.stand_in).
var dominated_short_ids: Array[String] = []
## The quest targets among the monsters dominated (#625), by the ids their regions' legends name
## them by, which only quests count.
var targets_dominated: Array[String] = []
var materials: Dictionary[String, int] = {}
## Gear found (#694), by id: how many of each.
var gear: Dictionary[String, int] = {}
## Treasure chests this player got loot from, which only quests count.
var chests_opened: int = 0
## The places this player stepped into (#339), by id, which only quests count.
var places_reached: Array[String] = []
## The region pieces this player entered (#350), by id, which only quests count.
var pieces_entered: Array[String] = []
## The instances this player entered (#370), by blueprint name, which only quests count.
var instances_entered: Array[String] = []
## The answers this player chose in dialogs (#636), each as QuestStep.answer_key names it, which
## only quests count.
var answers_chosen: Array[String] = []
## The world's events that changed it (WorldChanged, #707), by name, which every player gains,
## wherever they are, and only quests count: as an event emitted, like a quest's own (#575).
var world_events: Array[String] = []
