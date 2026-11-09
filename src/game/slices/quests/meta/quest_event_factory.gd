class_name QuestEventFactory
extends RefCounted
## Builds an instance's quest events feature (#755, #823) with every event a quest emits, by code,
## from the quests' content data.


static func build(_setup: FeatureSetup) -> QuestEventFeature:
	var content: QuestContent = QuestContent.cached()
	if not content.problem.is_empty():
		push_error("the quests don't load: " + content.problem)
	return QuestEventFeature.new(content.events)
