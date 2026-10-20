class_name RegionFiles
extends Content
## The text of a region's files (#816): its one region file, regions/<name>.md, or its region
## pieces in regions/<name>/, read once per session (ContentCatalog), so loading an instance reads
## no files. InstanceBlueprints reads the region from them.

## Each file's text, by its path, in path order: the one region file, or every region piece.
var texts: Dictionary[String, String] = {}
## Whether the region is one region file, not pieces.
var whole: bool = false


## The files of the region `region_name`, read once per session (ContentCatalog).
static func cached(region_name: String) -> RegionFiles:
	return ContentCatalog.kept(key(region_name), load_region.bind(region_name))


## The catalog's key for the files of the region `region_name`.
static func key(region_name: String) -> String:
	return InstanceBlueprints.REGIONS + region_name


## Whether the region `region_name` is in this build: a region file or a folder of pieces. The
## device builds leave the test-only regions out (export_presets.cfg).
static func exists(region_name: String) -> bool:
	return (
		FileAccess.file_exists(key(region_name) + ".md")
		or DirAccess.dir_exists_absolute(key(region_name))
	)


## The files of the region `region_name`, read: none when there's neither a region file nor a
## folder of pieces.
static func load_region(region_name: String) -> RegionFiles:
	var files: RegionFiles = RegionFiles.new()
	var path: String = key(region_name) + ".md"
	if FileAccess.file_exists(path):
		files.whole = true
		files.texts[path] = FileAccess.get_file_as_string(path)
		return files
	var folder: String = key(region_name) + "/"
	var names: Array[String] = []
	names.assign(DirAccess.get_files_at(folder))
	names.sort()
	for file: String in names:
		if file.ends_with(".md"):
			files.texts[folder + file] = FileAccess.get_file_as_string(folder + file)
	return files
