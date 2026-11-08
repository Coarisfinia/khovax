class_name TerritoryQuests
extends RefCounted
## What the content flow asks of the territory quests (#639, from #548): every faction has a quest
## for every territory, and no two quests of one territory are samey. Not a flow itself: the runner
## runs only the `test_*.gd` files.
##
## Every instance blueprint counts as a territory: nothing in the data marks one as such. A faction
## needs a quest for the territories it starts with too.

## The faction and territory pairs that have no quest yet, each "<faction>/<territory>", filed as
## content issues. This list only shrinks: `problem` refuses an entry whose quest now exists, so
## the quest's pull request takes it out. A new faction or territory is refused until it has its
## quests, and CI refuses a new entry here (packages/game-checks/known_gaps_check.py, #2182).
const KNOWN_GAPS: Array[String] = [
	# #2174
	"amvrel_velmarai/brekhal_varn",
	"amvrel_velmarai/dhorvone_stolm",
	"amvrel_velmarai/hrovumel_stolm",
	"amvrel_velmarai/hrunde_orl",
	"amvrel_velmarai/ivenwhal_wudhen",
	"amvrel_velmarai/lumwen_hoal",
	"amvrel_velmarai/senwel_sael",
	"amvrel_velmarai/thudren_orl",
	# #2175
	"odun_kragothai/brekhal_varn",
	"odun_kragothai/dhorvone_stolm",
	"odun_kragothai/edhra_tewk",
	"odun_kragothai/hrovumel_stolm",
	"odun_kragothai/hrunde_orl",
	"odun_kragothai/ivenwhal_wudhen",
	"odun_kragothai/lumwen_hoal",
	"odun_kragothai/morwe_wudhen",
	"odun_kragothai/senwel_sael",
	"odun_kragothai/thudren_orl",
	"odun_kragothai/planted_gap",
	# #2176
	"sorn_lumawenai/brekhal_varn",
	"sorn_lumawenai/dhorvone_stolm",
	"sorn_lumawenai/edhra_tewk",
	"sorn_lumawenai/hrovumel_stolm",
	"sorn_lumawenai/hrunde_orl",
	"sorn_lumawenai/ivenwhal_wudhen",
	"sorn_lumawenai/lumwen_hoal",
	"sorn_lumawenai/morwe_wudhen",
	"sorn_lumawenai/senwel_sael",
	"sorn_lumawenai/thudren_orl",
]


## Why the territory quests among `quests` don't keep to the rules, or "": a pair of one of
## `factions` and one of `territories` has no quest and isn't in `gaps`, an entry of `gaps` isn't
## such a missing pair (its quest exists, or its faction or territory doesn't) or comes twice, or
## two quests of one territory are samey.
static func problem(
	quests: Array[QuestDefinition],
	factions: Array[String],
	territories: Array[String],
	gaps: Array[String],
) -> String:
	var missing: Array[String] = _missing(quests, factions, territories)
	var found: Array[String] = []
	found.append_array(_no_quest(missing, gaps))
	found.append_array(_stale(missing, gaps))
	found.append_array(_samey(quests))
	return "; ".join(PackedStringArray(found))


## Every pair of `factions` and `territories` without a quest, sorted.
static func _missing(
	quests: Array[QuestDefinition],
	factions: Array[String],
	territories: Array[String],
) -> Array[String]:
	var written: Dictionary[String, bool] = {}
	for quest: QuestDefinition in quests:
		if quest.territory != null:
			written[_pair(quest.territory.faction, quest.territory.instance)] = true
	var missing: Array[String] = []
	for faction: String in factions:
		for territory: String in territories:
			if not written.has(_pair(faction, territory)):
				missing.append(_pair(faction, territory))
	missing.sort()
	return missing


## The one problem naming every pair of `missing` that `gaps` doesn't list, or none.
static func _no_quest(missing: Array[String], gaps: Array[String]) -> Array[String]:
	var unlisted: Array[String] = []
	for pair: String in missing:
		if not gaps.has(pair):
			unlisted.append(pair)
	if unlisted.is_empty():
		return []
	return ["%d without a territory quest: %s" % [
		unlisted.size(), ", ".join(PackedStringArray(unlisted)),
	]]


## A problem for each entry of `gaps` that isn't a missing pair or comes twice.
static func _stale(missing: Array[String], gaps: Array[String]) -> Array[String]:
	var found: Array[String] = []
	for gap: String in gaps:
		if not missing.has(gap):
			found.append("%s is listed as a gap, but there's no such gap" % gap)
		elif gaps.count(gap) > 1 and not found.has("%s is listed twice" % gap):
			found.append("%s is listed twice" % gap)
	return found


## A problem for each two quests of one territory whose steps are the same kinds in the same order.
static func _samey(quests: Array[QuestDefinition]) -> Array[String]:
	var seen: Dictionary[String, String] = {}
	var found: Array[String] = []
	for quest: QuestDefinition in quests:
		if quest.territory == null:
			continue
		var shape: String = quest.territory.instance + ":" + _kinds(quest)
		if seen.has(shape):
			found.append("%s and %s are samey in %s" % [
				seen[shape], quest.id, quest.territory.instance,
			])
		else:
			seen[shape] = quest.id
	found.sort()
	return found


## The kinds of `quest`'s steps in order; a step with choices is the sorted kinds of its choices.
static func _kinds(quest: QuestDefinition) -> String:
	var kinds: Array[String] = []
	for step: QuestStep in quest.steps:
		var options: Array[String] = []
		for trigger: QuestStep in step.triggers():
			options.append(trigger.condition)
		options.sort()
		kinds.append("|".join(PackedStringArray(options)))
	return ">".join(PackedStringArray(kinds))


static func _pair(faction: String, territory: String) -> String:
	return faction + "/" + territory
