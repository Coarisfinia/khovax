# gdstyle:ignore-file=quality/no-debug-print
# It reports a late error on stderr to whoever runs the tool, like the tools themselves.
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
## anything. `code` is the tool's verdict, given before the wait, so an error `errors` counts during
## the wait (a node leaving the tree, a stopping sound, a freed scene's script) fails the run here
## instead (#2371).
static func quit(tree: SceneTree, code: int, errors: ErrorCounter) -> void:
	var counted: int = errors.count
	for child: Node in tree.root.get_children():
		child.queue_free()
	var timer: SceneTreeTimer = tree.create_timer(AUDIO_RELEASE_SECONDS)
	var _connected: int = timer.timeout.connect(_quit_now.bind(tree, code, errors, counted))


## Quits `tree` with `code`, or with 1 when `errors` counted more than `counted` meanwhile and
## `code` said the run passed.
static func _quit_now(tree: SceneTree, code: int, errors: ErrorCounter, counted: int) -> void:
	var late: int = errors.count - counted
	if late > 0:
		printerr("FAIL  quit: %d error(s) logged after the verdict, while quitting" % late)
	tree.quit(1 if late > 0 and code == 0 else code)
