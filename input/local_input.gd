class_name LocalInput
extends Node
## The local player's commands. Every device feeds the same movement actions (keys, the touch
## stick, later controllers), and this turns them into one command per tick.


func command(state: GameState) -> Command:
	var vector: Vector2 = Input.get_vector("move_left", "move_right", "move_down", "move_up")
	return Command.new(HexInput.direction_toward(vector, state.player_tile))
