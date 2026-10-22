class_name QuestRewards
extends RefCounted
## What finishing a quest gives the player (#817), through their profile's own parts: it leans
## them toward the quest's path (#658), moves their standing with the faction it names (#532), held
## on the scale by Standings, and posts the hand-over of the territory it names to the outbox (#638,
## #771). Given in the same change as the quest is marked done, so a save never has one without the
## other.


## Gives `profile` what finishing `quest` gives.
static func give(quest: QuestDefinition, profile: Profile) -> void:
	profile.leaning.lean(quest.path)
	if quest.standing != null:
		# Its faction's id was checked when the quest was read, so the change can't be refused.
		var _moved: String = profile.standings.change(quest.standing.faction, quest.standing.change)
	if quest.territory != null:
		var code: int = Territory.code(quest.territory.instance, quest.territory.faction)
		var _posted: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, code)
