extends RefCounted
## The APK's e2e flow (tests/apk/apk_flow.gd), run headless as well: it pins the flow's expected end
## state here, so the Android emulator's job checks the same game.

const FLOW: String = "res://tests/apk/apk_flow.gd"


func run(tree: SceneTree) -> String:
	var path: String = str(ProjectSettings.get_setting("application/run/main_scene"))
	var main: Node = (load(path) as PackedScene).instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var flow: Object = (load(FLOW) as GDScript).new()
	var done: Signal = Signal(flow, "finished")
	flow.call("begin", main, tree)
	var result: String = await done
	main.queue_free()
	return result
