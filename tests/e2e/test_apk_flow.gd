extends RefCounted
## The APK's e2e flow (tests/apk/apk_flow.gd), run headless as well: it pins the flow's expected end
## state here, so the Android emulator's job checks the same game.

const FLOW: String = "res://tests/apk/apk_flow.gd"


func run(tree: SceneTree) -> String:
	var main: Node = await FlowGame.start(tree)
	var flow: Object = (load(FLOW) as GDScript).new()
	var done: Signal = Signal(flow, "finished")
	flow.call("begin", main, tree)
	var result: String = await done
	main.queue_free()
	return result
