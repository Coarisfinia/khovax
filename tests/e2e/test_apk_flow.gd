extends RefCounted
## The APK's e2e flow (tests/apk/apk_flow.gd), run headless as well: it pins the flow's expected end
## state here, so the Android emulator's job checks the same game.

const FLOW: String = "res://tests/apk/apk_flow.gd"
## The flow's own profile, empty at the start (#570): the session starts from the player's profile
## (their companion), so a run on a machine with a real profile would end in another hash than on a
## fresh device, and a test never reads or writes the player's own profile.
const PROFILE_PATH: String = "user://test_apk_profile.json"
## A device's screen: the headless window is so small that the roster's squares cover the middle,
## where the finger touches down, and take the touch instead of the stick (#750).
const SCREEN: Vector2i = Vector2i(1152, 648)


func run(tree: SceneTree) -> String:
	var window_size: Vector2i = tree.root.size
	tree.root.size = SCREEN
	var main: Node = await FlowGame.start(tree, PROFILE_PATH)
	var flow: Object = (load(FLOW) as GDScript).new()
	var done: Signal = Signal(flow, "finished")
	flow.call("begin", main, tree)
	var result: String = await done
	main.queue_free()
	# The holder saves what is pending as it leaves the tree, so the file goes after that.
	await tree.process_frame
	SaveStore.remove(PROFILE_PATH)
	tree.root.size = window_size
	return result
