# Player clips

- **Author:** the project (generated with Meshy AI, paid plan, Private licence)
- **Source:** the baseline body (#1827) rigged and animated with Meshy AI by the owner, one clip per
  export (#1934); each export's rig and clip taken by `packages/game-models/import_clip.py` into
  `packages/game-models/sources/player/`, then merged into `player_clips.glb` by
  `packages/game-models/player_clips.py` (#1935)
- **License:** Unlicense, the repository's own license, see `LICENSE.md` next to this file.
- **Used for:** the player's clips, a library apart from the body, mapped to Godot's humanoid
  skeleton profile on import.
