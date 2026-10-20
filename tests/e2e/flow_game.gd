class_name FlowGame
extends RefCounted
## Starts the game's main scene inside a flow, as a session would (#247, AGENTS.md: shared, never
## copied). Not a flow itself: the runner runs only the `test_*.gd` files.


## Adds the main scene to the tree and waits a frame for it to start. With a profile path, the
## flow's dominations and finds go into a fresh save there, never into the player's own.
static func start(tree: SceneTree, profile_path: String = "") -> Node:
	var path: String = Boot.GAME
	var main: Node = (load(path) as PackedScene).instantiate()
	if not profile_path.is_empty():
		SaveStore.remove(profile_path)
		holder(main).save_path = profile_path
	tree.root.add_child(main)
	await tree.process_frame
	return main


## The main scene's driver.
static func driver(main: Node) -> GameDriver:
	return main.get_node("Driver") as GameDriver


## The main scene's driver, held: the flow steps the world itself, real time doesn't.
static func held_driver(main: Node) -> GameDriver:
	var held: GameDriver = driver(main)
	held.set_process(false)
	return held


## The main scene's profile holder.
static func holder(main: Node) -> ProfileHolder:
	return main.get_node("ProfileHolder") as ProfileHolder


## The main scene's quest keeper (#855), which keeps the player's quests in the profile's file.
static func quests(main: Node) -> QuestKeeper:
	return main.get_node("QuestKeeper") as QuestKeeper
