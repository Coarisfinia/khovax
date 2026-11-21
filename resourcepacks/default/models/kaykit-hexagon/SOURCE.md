# KayKit Medieval Hexagon Pack 1.0

- **Author:** Kay Lousberg (www.kaylousberg.com)
- **Source:** https://github.com/KayKit-Game-Assets/KayKit-Medieval-Hexagon-Pack-1.0
  (`addons/kaykit_medieval_hexagon_pack/Assets/gltf/decoration/nature/`, and
  `resource_lumber` from `decoration/props/`)
- **License:** CC0 1.0, see `LICENSE.md` next to this file. Credit is welcome, not required.
- **Used for:** the decorations on forest, shrubs, boulder, stump, cracked rock, rubble and logs
  tiles (#116, #205, #1546, #2485), until the game's own look exists.
- **Only what the game uses is here:** the models `trees_A_large`, `trees_B_small`,
  `mountain_C`, `tree_single_B_cut`, `rock_single_E`, `rock_single_A` and `resource_lumber`,
  each with its buffer, and the pack's shared texture, unchanged except below.
- **Modifications:** `resource_lumber.gltf`'s node is turned 30 degrees about the vertical axis
  (its `rotation`, added by hand, #2485), so the board's camera sees the log ends instead of a
  plank-like side. Its buffer is unchanged.
- **Checked:** 2026-11-21: `resource_lumber.gltf` and `.bin` taken from the repository at commit
  `84fa4e91af6a88989be7c99e0891cede11f2ca38`, under the pack's CC0 `LICENSE`; SHA-256 as
  downloaded: `601a69f44f0c4a9b5070a80bd4a20887960e01f1523a6125c1edc8ba19168f1f` (`.gltf`),
  `90bb1e1f23dbc3de372059b45ae289ec414b1fb50b49852ce0a3b30dc370db8b` (`.bin`).
