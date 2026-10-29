class_name ProfilePanelsTie
extends Node
## Ties this machine's player's profile (ProfileHolder) to the menu that shows and changes it
## (#1613): the Character tab with its standings, monsters, gear and materials, and the host's
## choices in the Settings tab, which wait in the outbox. Their slices come before the profile,
## which keeps what later
## slices store, so this hands each what it shows and does instead of it finding the holder (#851).
## A profile that can't be read stays so all session (the holder reads it once, on entering the
## tree): nothing is handed then, and the panels show none, as they did without one.

## The menu whose Character tab and host choices show the profile.
@export var menu: GameMenu
## The profile they show.
@export var holder: ProfileHolder


func _ready() -> void:
	# The menu builds its tabs when it's ready, which may be after this.
	if not menu.is_node_ready():
		await menu.ready
	var tab: CharacterTab = menu.character
	tab.name_field.max_length = Profile.NAME_LIMIT
	if holder == null or holder.keeper == null:
		return
	tab.factions.standings = _standings
	tab.materials.materials = _materials
	tab.gear.slots = _gear
	tab.gear.equip = holder.equip
	tab.monsters.order = _order
	tab.monsters.carried = _carried
	tab.monsters.monster_of = _monster_of
	tab.monsters.materials = _materials
	tab.monsters.reorder = holder.move_monster
	tab.profile.keep_color = holder.choose_color
	tab.profile.keep_auto = holder.choose_color.bind(Profile.AUTO_COLOR)
	tab.profile.chose_color = holder.chose_personal_color
	tab.profile.keep_name = holder.choose_name
	tab.profile.kept_name = _name
	tab.profile.keep_node = holder.take_node
	tab.profile.keep_ascension = holder.ascend
	tab.fill_name()
	# The host's choices in the Settings tab, which the menu keeps as its children.
	for child: Node in menu.get_children():
		var choice: HostChoice = child as HostChoice
		if choice != null:
			choice.outbox = _outbox
			choice.post = _post


func _standings() -> Standings:
	return holder.keeper.profile.standings


func _materials() -> Dictionary[String, int]:
	return holder.keeper.profile.materials


func _gear() -> GearSlots:
	return holder.keeper.profile.gear


func _order() -> Array[String]:
	return holder.keeper.profile.order()


func _carried() -> Array[String]:
	return holder.keeper.profile.carried


func _monster_of(short_id: String) -> DominatedMonster:
	return holder.keeper.profile.monster_of(short_id)


func _name() -> String:
	return holder.keeper.profile.character_name


func _outbox() -> Array[OutboxEntry]:
	return holder.keeper.profile.outbox.entries


## Posts the request of `kind` with `data` to the outbox, saved like any change
## (ProfileHolder.change).
func _post(kind: int, data: int) -> void:
	holder.change(_post_to.bind(kind, data))


## Posts the request to `profile`'s outbox (the change hands the profile first, then the bound
## kind and data).
func _post_to(profile: Profile, kind: int, data: int) -> void:
	var _posted: OutboxEntry = profile.outbox.post(kind, data)
