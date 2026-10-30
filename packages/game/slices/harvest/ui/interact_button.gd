class_name InteractButton
extends ActionButton
## The touch button that harvests a tile by hand (#1488), pressing `interact` as the F key and a
## controller's A do (#696). It shows a grabbing hand, and only while a press would begin a harvest
## (shows_in): there's nothing to do with it otherwise, as with the respawn button. It shares the
## respawn button's place, since a knocked-down player harvests nothing and so the two never show
## together.


func _init() -> void:
	icon = ResourcePacks.texture("icon_grab")
	action = &"interact"
	column_index = 2


func lay_out_in(screen: Vector2) -> void:
	super(screen)
	visible = visible and shows_in(state(), slot())


## Whether slot `player_slot`'s player in `game` would begin a harvest by pressing interact: the
## instance has harvesting and it's on, they stand on or next to a tile bare hands can harvest
## (TileHarvestFeature.target_of), and they aren't knocked down.
static func shows_in(game: GameState, player_slot: int) -> bool:
	var harvest: Feature = game.feature(TileHarvestFeature.ID) if game != null else null
	if harvest == null or not harvest.enabled:
		return false
	var harvester: Entity = game.player(player_slot)
	if harvester == null:
		return false
	var knockdown: KnockdownFeature = game.feature(KnockdownFeature.ID) as KnockdownFeature
	if knockdown != null and knockdown.is_down(harvester.id):
		return false
	return TileHarvestFeature.target_of(game, harvester) != TileHarvestFeature.NO_TILE
