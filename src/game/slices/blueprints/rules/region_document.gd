class_name RegionDocument
extends RefCounted
## A region or region piece as a Markdown file (#145): a title and prose explaining it, its tiles
## drawn as an EmojiGrid, which reads the grid and the legend (#865). Nothing refers to a tile by
## numbers: connectors, exits and named species are symbols in the grid, which the legend
## explains. Each meaning is one LegendMeaning reads, with the readers of what the slices place
## (PlacementReader), and the document builds its Region with them (#824). One symbol at most may
## name the document's floor (#2498), a walkable kind the tiles on plain ground lie on instead of
## grass.


## The region a Markdown region document describes, with what the slices place read by `readers`
## (InstanceBlueprints hands every slice's over); its `problem` says what's wrong.
static func parse(text: String, readers: Array[PlacementReader] = []) -> Region:
	var grid: EmojiGrid = EmojiGrid.read(text)
	if not grid.problem.is_empty():
		return _refused(grid.problem)
	var meanings: Dictionary[String, LegendMeaning] = {}
	for symbol: String in grid.legend:
		meanings[symbol] = LegendMeaning.read(grid.legend[symbol], readers)
	var unexplained: String = grid.unexplained(meanings)
	if not unexplained.is_empty():
		return _refused("the legend doesn't explain `%s`" % unexplained)
	if grid.symbols.size() > Region.MAX_TILES:
		return _refused("the region has more than %d tiles" % Region.MAX_TILES)
	var floors: Array[String] = _floors(meanings)
	var floor_kind: String = Region.GROUND if floors.is_empty() else floors[0]
	if floors.size() > 1 or not TileKinds.is_walkable(floor_kind):
		return _refused("the legend's floors %s aren't one walkable kind" % [floors])
	var region: Region = Region.new()
	# Each drawn tile's meaning, in reading order: what stands on it is placed once all are laid.
	var drawn: Dictionary[Vector2i, LegendMeaning] = {}
	for tile: Vector2i in grid.symbols:
		drawn[tile] = meanings[grid.symbols[tile]]
		region.problem = drawn[tile].lay(region, tile, floor_kind)
		if not region.problem.is_empty():
			return region
	region.problem = _starts(region, drawn)
	for tile: Vector2i in drawn:
		if region.problem.is_empty():
			region.problem = drawn[tile].place(region, tile)
	for reader: PlacementReader in readers:
		if region.problem.is_empty():
			region.problem = reader.problem_in(region)
	return region


## Sets `region`'s player starts from the tiles `drawn` as them, by slot; returns why it can't, or
## "": each player's start is drawn once, numbered 1, 2, 3, … without gaps.
static func _starts(region: Region, drawn: Dictionary[Vector2i, LegendMeaning]) -> String:
	var starts_by_slot: Dictionary[int, Vector2i] = {}
	for tile: Vector2i in drawn:
		var slot: int = drawn[tile].start
		if slot >= 0 and starts_by_slot.has(slot):
			return "player %d's start is marked twice" % (slot + 1)
		if slot >= 0:
			starts_by_slot[slot] = tile
	for slot: int in starts_by_slot.size():
		if not starts_by_slot.has(slot):
			return "the player starts aren't numbered 1, 2, 3, … without gaps"
		region.starts.append(starts_by_slot[slot])
	return ""


## The kinds the legend's `meanings` name as the document's floor (#2498), one per symbol saying
## it.
static func _floors(meanings: Dictionary[String, LegendMeaning]) -> Array[String]:
	var floors: Array[String] = []
	for symbol: String in meanings:
		var said: LegendMeaning = meanings[symbol]
		if said != null and said.is_floor:
			floors.append(said.kind)
	return floors


static func _refused(problem: String) -> Region:
	var region: Region = Region.new()
	region.problem = problem
	return region
