class_name RegionFiles
extends Content
## The text of a region's files (#816): its one region file or its region pieces, as the resource
## packs list them (#1861), read once per session (ContentCatalog), so loading an instance reads no
## files. InstanceBlueprints reads the region from them.

## The start of the catalog's keys for regions' files.
const KEY: String = "region:"

## Each file's text, by its path, in path order: the one region file, or every region piece.
var texts: Dictionary[String, String] = {}
## Whether the region is one region file, not pieces.
var whole: bool = false


## The files of the region `region_name`, read once per session (ContentCatalog).
static func cached(region_name: String) -> RegionFiles:
	return ContentCatalog.kept(key(region_name), load_region.bind(region_name))


## The catalog's key for the files of the region `region_name`.
static func key(region_name: String) -> String:
	return KEY + region_name


## Whether the region `region_name` is in this build: a resource pack has it (#1861), and its files
## are there. The device builds leave the test-only regions out (export_presets.cfg).
static func exists(region_name: String) -> bool:
	var whole_file: String = ResourcePacks.region_file(region_name)
	if not whole_file.is_empty():
		return FileAccess.file_exists(whole_file)
	return ResourcePacks.region_pieces(region_name).any(FileAccess.file_exists)


## The files of the region `region_name`, read from the resource packs (#1861): none when no pack
## has it, or this build leaves its files out.
static func load_region(region_name: String) -> RegionFiles:
	var files: RegionFiles = RegionFiles.new()
	var path: String = ResourcePacks.region_file(region_name)
	if not path.is_empty():
		if FileAccess.file_exists(path):
			files.whole = true
			files.texts[path] = FileAccess.get_file_as_string(path)
		return files
	var paths: Array[String] = ResourcePacks.region_pieces(region_name)
	paths.sort()
	for piece: String in paths:
		if FileAccess.file_exists(piece):
			files.texts[piece] = FileAccess.get_file_as_string(piece)
	return files
