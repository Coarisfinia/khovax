class_name QuietQuit
extends RefCounted
## Quits a test tool's tree without leaking a sound (#1906). The audio server lets go of a stopped
## sound only on its own thread, a few mixing rounds after its player is freed, and until then holds
## its stream: a tool quitting right after the game's music stopped (a flow freeing the main scene
## just before) leaks it or not by chance, and Godot reports it as leaked at exit. So the tree runs
## on for a moment before it quits. Not a flow itself: the runner runs only the `test_*.gd` files.

## How long the audio server gets to drop the sounds stopped: many of its mixing rounds.
const AUDIO_RELEASE_SECONDS: float = 0.5


## Frees whatever is in `tree`'s root, which stops every sound still playing, and quits with `code`
## once the audio server has had time to let go of them. The tree runs on until then: stop stepping
## anything.
static func quit(tree: SceneTree, code: int) -> void:
	for child: Node in tree.root.get_children():
		child.queue_free()
	var timer: SceneTreeTimer = tree.create_timer(AUDIO_RELEASE_SECONDS)
	var _connected: int = timer.timeout.connect(tree.quit.bind(code))
