class_name QuestRewards
extends RefCounted
## What finishing a quest gives the player (#817), through their profile's own parts: it leans
## them toward the quest's path (#658), moves their standing with the faction it names (#532) and
## that faction's enemies (#1310), held on the scale by Standings, posts the hand-over of the
## territory it names to the outbox (#638, #771) and hands over the materials it gives (#1348), like
## loot found. Given in the same change as the quest is marked done, so a save never has one without
## the other.


## Gives `profile` what finishing `quest` gives.
static func give(quest: QuestDefinition, profile: Profile) -> void:
	profile.leaning.lean(quest.path)
	if quest.standing != null:
		# Its faction was checked when the quest was read, so it's there; gaining rank with it costs
		# half that with each of its enemies (#1310).
		var faction: Faction = FactionContent.cached().factions[quest.standing.faction]
		profile.standings.align(faction, quest.standing.change)
	if quest.territory != null:
		var code: int = Territory.code(quest.territory.instance, quest.territory.faction)
		var _posted: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, code)
	if not quest.materials.is_empty():
		var gain: Gain = Gain.new()
		gain.materials = quest.materials.duplicate()
		# Refused only past what a profile can hold, and then the player keeps what they had.
		var _refused: String = profile.apply(gain)
