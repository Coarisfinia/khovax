class_name QuestRewards
extends RefCounted
## What finishing a quest gives the player (#817), through their profile's own parts: it leans
## them toward the quest's path (#658), moves their standing with the faction it names (#532) and
## that faction's enemies (#1310), held on the scale by Standings, then holds the standings it
## enforces within their bounds (#1326), posts the hand-over of the territory it names to the
## outbox (#638, #771) and hands over the materials it gives (#1348), like loot found. Finishing the
## quest that ends the main story puts the player in the postgame (#1333), after its own standing
## moved. Given in the same change as the quest is marked done, so a save never has one without the
## other.


## Gives `profile` what finishing `quest` gives.
static func give(quest: QuestDefinition, profile: Profile) -> void:
	profile.leaning.lean(quest.path)
	if quest.standing != null:
		# Its faction was checked when the quest was read, so it's there; gaining rank with it costs
		# half that with each of its enemies (#1310).
		var faction: Faction = FactionContent.cached().factions[quest.standing.faction]
		profile.standings.align(faction, quest.standing.change, profile.postgame)
	_enforce(quest.alignment, profile.standings, profile.postgame)
	if quest.territory != null:
		var code: int = Territory.code(quest.territory.instance, quest.territory.faction)
		var _posted: OutboxEntry = profile.outbox.post(OutboxEntry.TERRITORY, code)
	if not quest.materials.is_empty():
		var gain: Gain = Gain.new()
		gain.materials = quest.materials.duplicate()
		# Refused only past what a profile can hold, and then the player keeps what they had.
		var _refused: String = profile.apply(gain)
	if quest.ends_story:
		profile.postgame = true


## Holds `standings` within the bounds `alignment` enforces (#1326), as a player in the `postgame`
## or not (#1333). A floor raises a standing like any gain, costing half that with the faction's
## enemies (#1310), and a ceiling lowers one, never below what an alliance until the postgame holds
## a player who joined it at (#1324): the lock wins. One entry's gain can lower another entry's
## faction below its floor, never raise one past its ceiling, so the floors are held once more,
## without that cost: each holds whatever the entries' order.
static func _enforce(alignment: Array[QuestAlignment], standings: Standings, postgame: bool) -> void:
	for aligned: QuestAlignment in alignment:
		# Its faction was checked when the quest was read, so it's there.
		var faction: Faction = FactionContent.cached().factions[aligned.faction]
		var before: int = standings.of(aligned.faction)
		standings.align(faction, aligned.enforced(before) - before, postgame)
	for aligned: QuestAlignment in alignment:
		var after: int = standings.of(aligned.faction)
		if after < aligned.at_least:
			var _raised: String = standings.change(aligned.faction, aligned.at_least - after)
