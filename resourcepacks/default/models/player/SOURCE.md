# Player body and clips

- **Author:** the project (generated with Meshy AI, paid plan, Private licence)
- **Source:** the baseline body (#1827), textured by the owner with Meshy AI and rigged apart:
  `src/game-models/import_body.py` moves the textured export's UVs and colour onto the rigged
  export, the same triangles, into `player_body.glb`. Its clips: the baseline body rigged and
  animated with Meshy AI by the owner, one clip per export (#1934); each export's rig and clip taken by `src/game-models/import_clip.py` into
  `resourcepacks/default/models/player/build/`, then merged into `player_clips.glb` by
  `resourcepacks/default/models/player/build/player_clips.py` (#1935). The Throw clip is motion capture instead: subject
  141, trial 11 (frames 221 to 341) of the CMU Graphics Lab Motion Capture Database
  (http://mocap.cs.cmu.edu/, funded by NSF EIA-0196217), retargeted onto the same rig by
  `src/game-models/import_mocap.py` (#1951)
- **License:** Unlicense, the repository's own license, see `LICENSE.md` next to this file. The
  CMU database's terms let its data be copied, modified and redistributed without permission
  (http://mocap.cs.cmu.edu/faqs.php), and it asks to be credited as above.
- **Used for:** the player's body, and its clips, a library apart from the body; both are mapped
  to Godot's humanoid skeleton profile on import, so the body plays the library's clips.
