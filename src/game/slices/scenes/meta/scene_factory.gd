class_name SceneFactory
extends RefCounted
## Builds an instance's scene runner feature (#2415, #823) with the scenes that apply to it from
## the resource packs' scene content data.


static func build(setup: FeatureSetup) -> SceneFeature:
	var content: SceneContent = SceneContent.cached()
	if not content.problem.is_empty():
		push_error("the scenes don't load: " + content.problem)
	return SceneFeature.new(content.for_instance(setup.instance))
