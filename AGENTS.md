# Agent notes for khovax

`khovax` is the permanent codename: the repository, paths and code identifiers use it. The game's
player-facing name is separate and lives only in display strings and config, so it can change without
touching git.

**The code explains itself**, with short comments next to it for the reasons a reader can't see (keep
them true in the same pull request that changes the code). **Decisions and their history live in the
GitHub issues.** `docs/design.html` is the design report: the current state of the game design, updated
in the pull request that changes a decision. The README holds only what a human has to do by hand and
how to run things. This file holds the rules for working here and what agents have learned the hard
way; add to it when something bites.

## Working on GitHub

- **The repository is public.** Issues, pull requests, comments, commits, code and tests never
  contain personal data. Editing a slip away isn't enough, because GitHub keeps the edit history.
- **No brand names of other games or products** in issues, pull requests, comments, commits, code,
  tests or docs (owner's rule): describe the idea instead ("instanced regions", "comic-style cel
  shading with ink outlines", "monster catching"). The tools the project uses (Godot, GitHub, scoop,
  gdstyle, Codex) are dependencies, not references, and are fine.
- **The agent works as `flixbox-ai-agent[bot]`** (the private GitHub App "Flixbox [AI Agent]"): it
  commits, pushes, opens and updates pull requests, comments and reads CI as the bot, never with the
  owner's account. Commits the owner makes by hand use the owner's GitHub noreply address, never the
  machine-global work email.
- **Tokens:** `agent-gh-token` (in `~/.local/bin`) signs a JWT with the app's private key
  (`~/.config/khovax-agent/app.pem`, App ID in `app-id` next to it) and prints a 1-hour installation
  token, cached for 50 minutes. The token is scoped to this repository only and to the permissions
  the agent needs (contents, pull requests, issues and workflows: write; actions: read), so it can't
  change settings even if the App could. `agent-gh` is `gh` with that token.
  The key is never read, printed, committed or sent anywhere except GitHub's token endpoint.
- **Each clone**, once after cloning (its worktrees share the clone's config):

  ```sh
  git config user.name 'flixbox-ai-agent[bot]'
  git config user.email '336689584+flixbox-ai-agent[bot]@users.noreply.github.com'
  git config credential.https://github.com.helper ''
  git config --add credential.https://github.com.helper \
    '!f() { test "$1" = get || exit 0; echo username=x-access-token; echo "password=$(agent-gh-token)"; }; f'
  ```

- **Pull requests and comments:** `agent-gh pr create --assignee Flixbox …`, `agent-gh pr comment …`.
- **What the bot doesn't do:** change repository settings, or merge without the owner's approval.
  After the approval it enables auto-merge, or merges itself when auto-merge stalls (below).
  Settings changes the owner asks for are made with the owner's `gh` login.
- **In Git Bash, `gh api` takes endpoints without a leading slash** (`installation/repositories`):
  the shell rewrites `/path` into a Windows file path.
- **Name other repositories' issues and pull requests only as code text** (`` `owner/repo#123` ``),
  never as a link: GitHub adds a "mentioned this" entry to the other repository for every linked
  mention from this public one.

## Pull requests

You own a pull request from the moment you open it until it is merged. "Pushed" is not "done".

**One issue, one pull request** (owner's rule). Every pull request says `Closes #n` for its issue and
is assigned to the owner (`--assignee Flixbox`).

**Every branch is a worktree next to `main/`** (owner's rule, the same layout as the owner's other
repositories). The container folder `project-khovax/` holds `main/` (the primary checkout, always on
`main`), `assets/` (the `assets` branch) and one `<issue>-<slug>/` worktree per open branch, created
with `git -C main worktree add ../<branch> -b <branch>` and removed once its pull request is merged.
Never create or switch branches inside `main/`.

**One pull request at a time** (owner's rule). Never stack pull requests or work on two open ones in
parallel: pull requests are squash-merged, which rewrites the history a stacked branch is built on. Open
the next one as soon as the previous one is merged.

**While a pull request waits for the owner's review, prepare exactly one next one** (owner's rule),
so the owner can review it right away: in its own worktree, branched from `main`, fully built and
reviewed by Codex locally, but not pushed or opened. Once the open one merges, update the prepared
branch onto the new `main` (`git rebase origin/main`), check it still holds, push it and open it.

**One pull request per coherent change**: one feature, one fix or one refactor, whole. Side findings,
refactors and tooling tweaks get their own issue and their own pull request later, never along for the
ride.

**Keep each pull request low in complexity: a concise unit of progress, no bloat** (owner's rule).
Prefer the simplest solution that does the job, and Godot's built-in way over a hand-built one. When
an issue turns out bigger than one such unit, build the core now and file the rest as its own
issue.

**No pull requests that only change docs.** A change to this file, the README or the design report
rides along with the next real pull request, and that pull request's description says so.

**Rules live in this file, not in an agent's memory.** When the owner states a rule for this
repository, write it here in the next real pull request.

**Track queued work as GitHub issues.** Every idea or request that isn't being built right now gets an
issue assigned to the owner. Nothing waits only in a chat. **Read the issue and all its comments
before starting work on it**: the owner decides things in comments, and the description alone can be
out of date.

**`blocking` issues come first** (owner's rule). An open issue labelled `blocking` goes before
everything else, tech debt included.

**Tech debt comes before new features** (owner's rule). When picking the next issue, open
`tech-debt` issues (refactors, cleanups, tooling, bugs) go first, then features.

**Never ask whether to continue** (owner's rule): work. Ask only for decisions that belong to the
owner.

**Keep going without being asked.** Once a pull request is merged, take the next issue. Tech debt,
refactors and bugs come before new features. Ask only for decisions that belong to the owner (game
design, scope, security trade-offs).

**Stuck? File an issue and move on.** When something can't be finished without the owner, file an
issue saying what is blocked and why, and continue with the next work.

**Run long things in the background and keep working.** CI watchers and reviewer agents run in the
background; only wait in the foreground for a result the very next step needs.

### Before you push

- **Don't rerun locally what CI runs** (owner's rule): lint, the script check and the e2e tests run
  on every push. Push and let CI check. Run them locally only to reproduce a CI failure.
- **Check exit codes without pipes**, or with `${PIPESTATUS[0]}`: a pipe hides the exit code.
- **Batch your changes** into one push.
- **Every pull request that changes what the player sees shows it** in its description as a
  screenshot. Headless runs have no renderer, so render it locally with a throwaway `-s` script
  that never shows a window (owner's rule: the owner works on the same PC, and off-screen
  positions get clamped onto a second monitor): it sets `root.mode = Window.MODE_MINIMIZED`, runs
  the main scene inside a `SubViewport` (`UPDATE_ALWAYS`, its own `msaa_3d`) and saves
  `get_texture().get_image()` as a PNG after enough frames for the camera to settle. Run it with
  `--audio-driver Dummy`, so the music stays silent (headless runs already are). Publish it on
  the `assets` branch (an orphan branch that is never merged), through the
  `assets/` worktree next to `main/`: `![what it shows](https://github.com/Flixbox/khovax/blob/assets/pr-<n>-<what>.png?raw=true)`.
  When the change has no visible part, say so instead. **Before and after pictures always go in
  that order** (owner's rule): the before first, then the after.
- **Show the flow as a replay whenever sensible** (owner's rule, #214): a pull request that
  changes how something plays shows it in its description as an animated GIF of that flow,
  rendered the same hidden, silent way (a PNG every few frames, assembled into the GIF) and
  published on the `assets` branch like a screenshot.

### After every push

- **Update the PR description** so it describes what the branch does now.
- **Keep the project watcher running in the background**: household-brain's Claude Code plugin
  `project-watcher` (#142); what each event asks for is in its `babysit-prs` skill
  ([`SKILL.md`](https://github.com/Flixbox/household-brain/blob/main/packages/watcher/skills/babysit-prs/SKILL.md)).
  Set it up as the owner's laptop-wide agent notes describe, with this repository's values:
  `REPO=Flixbox/khovax`, `WORKFLOW=ci.yml`, `GH=agent-gh`, `ACTIVITY_GH=gh` and
  `SELF='flixbox-ai-agent[bot]'` (it has no default). On a failing CI run, read the job with
  `agent-gh run view <run-id> --log-failed`, reproduce it locally, fix it, and push once.

### Review and merge

- **Every pull request gets one review**, by Codex as the laptop-wide agent notes describe: read-only, reporting findings with severity and
  evidence. Fix blockers and should-fix items before merge, in one push, and say in the PR
  description what was addressed. Four review rounds is the soft cap.
- **Every comment gets an answer.** Fix what is asked in one push, then reply saying what changed. If
  a comment needs the owner's decision, say so and leave it open.
- **Merging:** once the owner has **approved** and the PR is well reviewed, read the PR for
  unanswered comments (an approval and a comment often arrive together), then enable auto-merge:
  `agent-gh pr merge <n> --auto --squash`. It merges once the required CI check is green. Without
  the owner's approval, never enable auto-merge. **If it doesn't merge** although the PR is
  approved, CI is green and it shows as clean and mergeable (GitHub's auto-merge sometimes stalls),
  merge it yourself: `agent-gh pr merge <n> --squash` (owner, #99). The approval stays valid through
  later pushes (owner's rule), so check the comments again before enabling auto-merge after a fix.
- **Read the reviews themselves to see an approval** (`gh api repos/Flixbox/khovax/pulls/<n>/reviews`),
  never `reviewDecision` or the watcher's status line: under the ruleset `reviewDecision` stays
  empty, so an approved pull request shows as "awaiting approval" (`Flixbox/household-brain#197`).
  An approval often arrives together with review comments, and the watcher reports only those.

## Architecture

Game logic and control logic are strictly separated (owner's rule, #26), so that the same start
and the same commands always give the same game: for replays, lockstep co-op and tests.

```
devices -> input/ -> Command -> sim/ -> GameState -> view/
                        ^
              game/ driver: fixed ticks
```

- **`sim/`, the simulation:** the core (`Simulation.step(state, commands)`, `GameState`, the grid
  math `Hex`) and the features. Plain `RefCounted` classes (or subclasses of `sim/` classes),
  integers only, durations in ticks (`Simulation.TICKS_PER_SECOND`). No nodes, `Input`, `Time`,
  `Engine`, `OS`, global randomness, frame `delta` or `float`: CI greps for them. Randomness comes
  from `Rng` (#32, xoshiro128** in integers): each feature that rolls owns its own stream,
  `Rng.new(state.rng_seed, id())` in `start`, keeps it in its state and hashes it, and draws only
  inside its step; streams keep one system's rolls from shifting another's. Ranges use
  `below`/`between` (no modulo bias), never `next_u32() % n`. **Numbers** (#33, `Fixed`): amounts
  (HP, strength, power, damage) are whole integers up to `Fixed.MAX_AMOUNT`, fractions are in
  thousandths (`Fixed.ONE`), and every division rounds down through `Fixed` (`mul_div`, `ratio`,
  `scale`, `div_floor`), multiplying first and dividing last; never `/` on ints elsewhere.
  `GameState.state_hash()` fingerprints the whole state; a new value goes into the hash too
  (`Feature.hash_values()` for a feature's).
- **Every game rule is a feature** (owner's rule, #30): modular, and every one can be switched on or
  off per instance, also during a session (e.g. a boss phase). The core holds no game rule: only the
  tick, the seed, the region, the entities and the instance's features in their step order. A feature
  (`sim/features/`, extends `Feature`) has a stable id in `Features` (never reused), its own state,
  a `step` called in order each tick, the features it `requires` earlier in the order, and its
  `hash_values`. Features talk through the tick's `events` (e.g. `EntityMoved`), not by reaching
  into each other: a feature may read the features it `requires` and change them only through
  their public methods (e.g. `CatchFeature` restarts a trail with `TrailFeature.restart`), never
  their fields. Whether a feature is on is state: only rules switch it, inside a tick
  (`GameState.set_enabled`); a disabled feature keeps its state and doesn't step.
- **Entities** (#31): everything in the world (players, wild monsters, later totems) is an
  `Entity` with a stable id, never reused, an owning player slot (0–3, or none) and a tile. A
  feature keeps its own data per entity id, like a component (`MovementFeature.walks`), set up and
  dropped in `entity_added` / `entity_removed`. Rules go through entities in id order
  (`GameState.entities`), never in a dictionary's order, and sort ids before hashing.
- **Regions** (#36, `Region`): which tiles exist, each tile's kind (a tile blueprint, #116), the
  players' starts, where wild monsters stand (`WildMonsterFeature` places them, #19, each of a
  species its spot names or rolled from the blueprint's `WILD_SPECIES`, #133; anything
  that isn't a player blocks walkers, players pass through each other) and where treasure chests
  stand (`ChestFeature`, #124, in blueprints with an instance loot table). Rules ask `state.region`
  (`is_walkable`, `has_tile`), never a distance from the origin, so a region can have any shape.
  A region is a hand-made Markdown file in `regions/` (a title, prose, the tiles in a code block and
  a legend explaining every symbol; format in `RegionDocument`, #145), or arranged from
  hand-made region pieces in `regions/<blueprint>/` by `RegionArranger`: the seed fits them together
  at their connectors and turns the whole region (#57), from its own random stream, unless the
  blueprint keeps its layout (`InstanceBlueprints.UNTURNED`, e.g. a boss arena, #127). The region is
  in the state hash; its connectors are used up by arranging. **Exits** (#140) lead
  to another blueprint, which has the way back on the opposite side (`exit_problem`); every instance
  in that web is unturned, so an exit always leads out the same way (#120). A player who walks out
  through one (`ExitFeature`, an `ExitTaken` event) is moved by the `World` into the instance
  it leads to, onto its way back (#154).
- **Instance blueprints** (`sim/blueprints/`, `InstanceBlueprints`): which region (a file in
  `regions/`) and which features in which order; players start on the region's starts. A new
  mechanic is a new feature that blueprints list; it never grows the core.
- **Names in code** (owner's rule, #45): clear differentiators, never a bare `monster` where one of
  these is meant. A `species` is what every monster is, captured or not; a `captured_monster` was
  caught by the player; a `wild_monster` can still be caught; an `ally_monster` fights on the
  player's side but isn't captured and can't be. They're names, not necessarily separate classes.
- **The place you play in** (owner's rule, #57, #117): **"map" is banned** in code and docs, except
  for a **map item**, an item drop that adds modifiers to an instance blueprint (#120). An
  **instance blueprint** is what an instance is loaded from (its region pieces and features); an
  **instance** is a loaded one (its region and state, #119); the **region** is the arranged place;
  a **region piece** is a hand-made piece a region is arranged from.
- **Commands** (`sim/command.gd`): the only way into the simulation. One per player per tick,
  indexed by player slot (`Command.of`), integers only. The starting state plus every tick's
  commands is a replay.
- **`meta/`, the layers above the simulation** (#37): the player's `Profile` (captured monsters,
  materials, unlocked slots) lasts between sessions. There are no runs (#183): the player roams one
  persistent `World`, built from a seed, deterministic like everything in `sim/`. A **session** is
  the span from loading the game to quitting it, which replays and lockstep co-op work in; it is
  technical and never shown to the player. Each catch or find is a
  `Gain`, which `ProfileKeeper.take` applies at once (`ProfileHolder` in the main scene loads the
  profile at boot and takes this machine's player's catches from the tick's events, #132); **saves
  are debounced** (owner, #73): the first gain after a quiet spell is saved right away, later ones
  at most once per `ProfileKeeper.SAVE_INTERVAL_MSEC`, and ending the session (quitting) or going
  to the background flushes what's pending. Saves are atomic, so a crash loses at most one interval's gains. The profile is
  saved as versioned JSON (`Profile.FORMAT`, `SaveStore`), integers and ids only: a newer format is
  refused, and an older one is migrated in `Profile.parse`, one format at a time.
  **Quest progress** (#184) lives in the profile too: a gain carries the facts quests count
  (catches, chests opened), and `Profile.apply` advances each quest in its `quest_book` (the quest
  data) from them, so progress is saved and debounced like any gain.
  **The world is saved too** (#119), in its own file next to the profile (`WorldSave`, through
  `SaveStore`), never in the profile: `World.to_data` holds its seed, tick and every loaded
  instance's entities and feature state (`Feature.save_values`/`load_values`; regions are arranged
  again from blueprint and seed), integers and ids only, and `World.from_data` refuses it whole
  for another format, other rules (`RULES_VERSION`: it couldn't go on deterministically) or a hash
  that doesn't match. `WorldKeeper` in the main scene hands the driver the saved world at boot and
  saves it debounced like the profile; the headless flows and the test builds keep no world
  (`WorldKeeper.default_path`). The same data is the snapshot co-op will resync from. The ground
  this machine's player explored (#215, FogView's memory) is saved beside it in the same file,
  under its own key, read apart: it's a view's, so it never enters the world's data, hash or
  replays, and bad memory is dropped without refusing the world.
  The player's `Settings` (#161) are kept apart from that progress, in their own file: each
  setting starts at "Auto", which picks what suits the device (`Graphics` applies the graphics
  ones), and a player's choice overrides it until they choose Auto again.
  Content data (species, quests, items) is read in `meta/` too (below).
- **Content data** (#72): species, loot tables, tile blueprints, quests and, later, items are JSONC files
  in `data/<kind>/`, one per entry and named after its id, with a JSON Schema in
  `data/schemas/<kind>.schema.json`. Not Godot resources (owner, #72: no engine lock-in). `meta/`
  reads them (`Content`, comments stripped by `Jsonc`) and hands the simulation plain integers and ids. CI checks every file against its
  schema with `jv` (pinned, verified), after `tools/data_to_json.gd` strips the comments with the
  same stripper; the content flow checks what a schema can't (ids matching files and unique, types
  from the chart, never two types of one family, loot chances adding up to 100 %). Loot tables
  (`LootTable`, #90) roll from the `Rng` they're given, so a feature's stream rolls the same loot.
  Tile blueprints (`TileBlueprint`, #116) each carry a permanent `number`, never reused or
  changed once shipped, which `Region.terrain` holds; `TileKinds` in `sim/` keeps only each kind's
  id, number and traits, and the views read the look (`TileLooks`). **Tile traits are rules:**
  changing one (e.g. `walkable`) changes what the game does, so it bumps
  `Simulation.RULES_VERSION` and rehashes the golden replays, like any rule change.
- **`input/`, the input layer:** devices to commands. Every device presses the same InputMap actions
  (keys, the touch stick, later controllers). `LocalInput` turns them into the local player's
  command, and `HexInput.direction_toward` is where floats become a hex direction.
- **`view/`, the presentation:** scenes that read the state and draw it, interpolating between ticks
  (`GameDriver.tick_fraction()`). They never write the state. `HexLayout` is the only tile-to-world
  conversion. The views of the local player's instance sit under one `InstanceRoot` (#189),
  placed at that instance's place in the world (`World.offset`), so the camera follows the player
  in world space and walking through an exit has no cut. One-shot moments (a catch, a ring
  breaking, a hit) reach views as the tick's events through the driver's `ticked(tick, events)`
  signal (#34): every tick exactly once, in order, however many ticks a frame runs. Effects play
  from those; lasting looks come from the state.
- **`game/`, the driver:** `GameDriver` runs whole ticks of the `World` (#148, #158) from
  accumulated real time, in lockstep (#38); its `state` is the instance this machine's player is in,
  which the views draw. Real time decides when ticks happen, never what they do. Before each tick it polls its
  `CommandSource`s (the local player's `LocalSource`; later network peers or a replay), which put
  commands into the `CommandSchedule` `input_delay` ticks ahead; a tick runs only once every
  player's command for it is known, and a command once put is final. It keeps the last ticks' state
  hashes (`hashes`) for desync checks. Its events also go onto the `EventBus` (#184), which hands
  them to subscribers by topic a frame later, publish/subscribe: `ProfileHolder` takes this
  machine's player's catches and chests from it, which advance their quests too. Subscribers never change the world; views keep the driver's `ticked` signal. It records every session (`GameDriver.recording`, a `Replay`,
  #35): the starting instance, seed, players, rules version and features (and the starting world,
  for a session that resumed one), every change of a slot's command,
  and the state hash at checkpoints. `Replay.play()` plays one back headless and names the first
  difference, or why this build can't play it (format, rules version, instance, features).
- A new mechanic puts its rules and data into a feature in `sim/features/` with a replay check, its
  controls into `input/` as commands, and its look into its own view in `view/` (like `TrailView`,
  which paints the trail onto `HexGrid`; `HexGrid` itself only draws tiles).

## Lessons learned

### Game architecture

- **GDScript only, no C#.** Godot's C# projects can't export to the web, and the project keeps one
  language for all code.
- **Every GDScript warning is an error** (`project.godot`), and **every gdstyle rule is an error**
  (`gdstyle.toml`), the opt-in ones included (owner's rule). Type every variable, parameter and
  return value explicitly (no `:=`: `inferred_declaration` is an error too). A rule or warning only
  gets relaxed when it truly conflicts with another one, with the conflict named next to it.
  Inconvenience is not a reason. A suppression is a `# gdstyle:ignore=<rule>` or
  `# gdstyle:ignore-file=<rule>` comment directly below a line giving the reason.
- **Before pushing, run `gdstyle fmt .`**: it fixes the formatting rather than only checking it.
  gdstyle is installed with scoop from `tools/scoop/gdstyle.json`; its version is pinned there and
  in CI (with the archive's checksum), so bump both together.
- **Godot rewrites `project.godot` in its own form** whenever it runs: its own order, no comments,
  and settings equal to their default left out (four warnings are errors by default). Keep the file
  in that form so it doesn't churn, and keep the reasons for its settings in this file instead.
- **The headless renderer is a dummy**: a MultiMesh's instance transforms can't be read back, so
  code that tests need to inspect keeps its own copy of what it gave the renderer.
- **The simulation is deterministic**: see "Architecture" above. No Godot physics in gameplay.
- **The Compatibility renderer is the baseline** on every platform, because the web supports only
  that one. Shaders and effects have to work there.
- **The camera never shakes, pulses or snaps**: the game is designed around motion sickness.
- **Every feature is designed for co-op** (owner's rule, #74), though the game is played solo
  until hosting is solved (#75). Rules run in the deterministic simulation for 1–4 players, input
  reaches it only as per-player commands, nothing assumes a single player (no one "the player", no
  shared camera), and what a player obtains goes into their own profile.
- **Never color alone** (owner's rule, #68): whatever the player tells apart by color (types,
  teams, states) also gets a symbol or a shape, so the game stays colorblind friendly.
- **The look is cel-shaded eye candy** (owner, #69): monsters and what the camera shows up close
  are medium-poly; only small things that don't read from the top-down camera may be low poly.
  Low-poly packs are placeholders. Every asset in the repository has a license that allows it
  here (CC0, CC BY with credit), kept next to it. **Each pack lives in `assets/<pack>/`** with its
  license file and a `SOURCE.md` (title, then `- **Author:**`, `- **Source:**`, `- **License:**`);
  `CREDITS.md` is generated from those by `tools/credits.gd`, and CI fails when it's out of date
  (owner, #69/#70). Commit only what the game uses, not whole packs.

### Testing and CI

- **Every user flow has one coherent e2e test, headless** (owner's rule): one flow for booting
  into the world, one for moving on the hex grid, one for a full catch or combat encounter, and so
  on. A change to an area extends the flow that covers it with new steps; a new flow file
  (`tests/e2e/test_<flow>.gd`) is only for a new user flow. No collections of small unrelated tests,
  and no separate unit tests while the flows already check the same things (owner, #61).
- **Exactly one e2e flow runs on the devices** (owner's rule, #61, #102, #113):
  `tests/apk/apk_flow.gd`, on an Android emulator (`apk-e2e`), in headless Chrome (`web-e2e`,
  `tests/web/web_e2e.ts`) and on the Linux build under a virtual display (`linux-e2e`) in CI,
  started by `game/test_mode.gd` in the test builds only (the `e2e_test` export feature). It
  starts from a fixed seed, scripts its touches per tick, and must end in `EXPECTED_HASH`, which
  the same flow pins headless (`tests/e2e/test_apk_flow.gd`). A rule change that moves it updates
  it on purpose, like the golden replays. Everything else stays headless. `apk-e2e` is a required
  check: it passed the first time it ran, and the owner asked to enforce it then.
- **The test runner is our own** (`tests/e2e/run_e2e.gd`). The owner kept it over a framework
  for now (#61).
- **A fresh checkout needs `godot --headless --path . --import`** before headless runs.
- **A script error in the runner itself leaves the SceneTree running forever.** Every CI step that
  runs Godot needs a `timeout`, and every job a `timeout-minutes`.
- **Local names that shadow a base-class method or property fail the script check**: `reference`,
  `position`, `script`, `name`, and the test's own `run` have all bitten. So have discarded return
  values (`erase`, `resize`, a method returning the thing it added): assign them to a `_`-prefixed
  local, and an inner test class named like a global one (`Walk`).
- **gdstyle can accept what Godot's parser refuses**: a multi-line lambda inside a call's arguments
  passed `gdstyle check` but failed the script check ("Unindent doesn't match"). Write a loop, or a
  one-line lambda.
- **A warning fails a flow too**, unless the flow expects it: before provoking one on purpose (a
  refused world save), it calls `tree.call("expect_warning", "<fragment>")`, and fails if the
  warning never comes. The device flows expect none.
- **A GDScript function that hits a script error returns its type's default** (`""` for `String`), so
  a test can't signal success by returning nothing. The runner counts logged errors during each test
  (a `Logger` added with `OS.add_logger`) and fails the test if any appeared.
- **Commit the `.uid` files** Godot creates next to scripts and resources. Godot only writes them on an
  import, so after adding a script run `godot --headless --path . --import` before committing. It
  generates files rather than checking anything, so it doesn't fall under not rerunning CI locally.
- **Pushing anything under `.github/workflows/` needs workflow rights.** The bot has them through the
  App's Workflows permission. For the owner's own login it is the `workflow` scope
  (`gh auth refresh -h github.com -s workflow`).
- **Never use the `pull_request_target` or `workflow_run` triggers**, and never add self-hosted
  runners to this public repository.
- **Everything CI downloads is pinned and verified:** actions by full commit SHA (with the tag in a
  comment), and Godot, its export templates and gdstyle by checksum, with cache keys that include
  the checksum. Bump a version and its checksum together, in `ci.yml` and `release.yml` both. The
  runner image is named explicitly (`ubuntu-26.04`, not `ubuntu-latest`), so a new image arrives on
  purpose, with the APK build checked, not on GitHub's date.
- **Golden replays** (`tests/replays/*.replay`) are played by the replay flow in CI. One that stops
  matching means a change altered what the game does. If that is on purpose, bump
  `Simulation.RULES_VERSION`, rehash them (`godot --headless --path . -s
  res://tests/replays/rehash.gd`) and say in the pull request why the game plays out differently.
  Never rehash to make a surprise go away.
- **Point to the source, never enumerate it** (owner's rule, #99): a list that exists somewhere
  (the presets, the assets, the content files) is read from there, not copied into a workflow, a
  doc or a comment, where it would drift. E.g. CI unpacks the templates `tools/export_templates.sh`
  reads from `export_presets.cfg`, and `CREDITS.md` is generated from the assets.
- **No measured numbers in docs or comments** (durations, sizes, counts): they go stale. They belong
  in the PR or issue that measured them.

### Repository and accounts

- **`main` is protected by the ruleset "protect main"**, with no bypass: pull requests only, one
  approval (later pushes don't dismiss it), review threads resolved, the `headless` and `apk-e2e`
  checks from GitHub Actions green on a branch that is up to date with `main`, squash merges only, no
  force-push or deletion. The required checks are named after the CI jobs: renaming a job means
  changing the ruleset in the same PR (owner's `gh`).
- **Release tags are immutable:** the tag ruleset "immutable release tags" (`refs/tags/v*`, owner,
  #91) blocks deleting, moving and force-updating them, with no bypass; creating one is allowed.
  A wrong release gets a new version, never a moved tag.
- **Pull requests opened with the owner's account can't be approved by the owner.** The bot opens
  them.

### Toolchain

- **Install tools with scoop** (owner's rule). The development machine runs Windows, so Homebrew isn't
  available.
- **`git push` hung on a Windows credential prompt.** In this repository the repo-local credential
  helper above avoids it. For the owner's own pushes elsewhere, `gh auth setup-git` makes git use the
  `gh` login.
