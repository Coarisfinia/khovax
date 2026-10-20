class_name TerritoryFactory
extends RefCounted
## Builds an instance's territory feature (#638, #823) with every territory a quest hands over, by
## code, from the quests' content data. The content flow checks that each names an instance that
## exists.


static func build(_setup: FeatureSetup) -> TerritoryFeature:
	var content: QuestContent = QuestContent.load_quests()
	if not content.problem.is_empty():
		push_error("the quests don't load: " + content.problem)
	return TerritoryFeature.new(content.handovers)
