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
  tests or docs (owner's rule): describe the idea instead ("instanced maps", "comic-style cel
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
- **What the bot doesn't do:** change repository settings or merge directly. It only enables
  auto-merge after the owner's approval. Settings changes the owner asks
  for are made with the owner's `gh` login.
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
  screenshot. Render it locally with `godot --path . --write-movie <file>.png --quit-after 3`, since
  headless runs have no renderer. It writes numbered frames (`<file>00000000.png`, …); use the last
  one, and publish it on the `assets` branch (an orphan branch that is never merged), through the
  `assets/` worktree next to `main/`: `![what it shows](https://github.com/Flixbox/khovax/blob/assets/pr-<n>-<what>.png?raw=true)`.
  When the change has no visible part, say so instead.

### After every push

- **Update the PR description** so it describes what the branch does now.
- **Keep the project watcher running in the background**: the household-brain watcher
  ([`watch-project.ts`](https://github.com/Flixbox/household-brain/blob/main/packages/tooling/src/watch-project.ts);
  its events and what to do about each are in household-brain's
  [`AGENTS.md`](https://github.com/Flixbox/household-brain/blob/main/AGENTS.md), "When the watcher
  reports"). Set it up as the owner's laptop-wide agent notes describe, with this repository's values: `REPO=Flixbox/khovax`, `WORKFLOW=ci.yml`, `GH=agent-gh`.
  On a failing CI run, read the job with `agent-gh run view <run-id> --log-failed`, reproduce it
  locally, fix it, and push once.

### Review and merge

- **Every pull request gets one review**, by Codex as the laptop-wide agent notes describe: read-only, reporting findings with severity and
  evidence. Fix blockers and should-fix items before merge, in one push, and say in the PR
  description what was addressed. Four review rounds is the soft cap.
- **Every comment gets an answer.** Fix what is asked in one push, then reply saying what changed. If
  a comment needs the owner's decision, say so and leave it open.
- **Merging:** once the owner has **approved** and the PR is well reviewed, read the PR for
  unanswered comments (an approval and a comment often arrive together), then enable auto-merge:
  `agent-gh pr merge <n> --auto --squash`. It merges once the required CI check is green. Without
  the owner's approval, never enable auto-merge. The approval stays valid through later pushes (owner's
  rule), so check the comments again before enabling auto-merge after a fix.

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
  off per instance, also during a run (e.g. a boss phase). The core holds no game rule: only the
  tick, the seed, the map, the entities and the instance's features in their step order. A feature
  (`sim/features/`, extends `Feature`) has a stable id in `Features` (never reused), its own state,
  a `step` called in order each tick, the features it `requires` earlier in the order, and its
  `hash_values`. Features talk through the tick's `events` (e.g. `EntityMoved`), not by reaching
  into each other. Whether a feature is on is state: only rules switch it, inside a tick
  (`GameState.set_enabled`); a disabled feature keeps its state and doesn't step.
- **Entities** (#31): everything in the world (players, later the ball, monsters, totems) is an
  `Entity` with a stable id, never reused, an owning player slot (0–3, or none) and a tile. A
  feature keeps its own data per entity id, like a component (`MovementFeature.walks`), set up and
  dropped in `entity_added` / `entity_removed`. Rules go through entities in id order
  (`GameState.entities`), never in a dictionary's order, and sort ids before hashing.
- **Maps** (#36, `HexMap`): which tiles exist, each tile's terrain (ground, water, rock) and the
  players' starts. Rules ask `state.map` (`is_walkable`, `has_tile`), never a distance from the
  origin, so a map can have any shape. Maps are hand-made text files in `maps/` (format in
  `HexMap.parse`); instanced layouts will be assembled from hand-made pieces, the whole layout
  turned by the run's seed (#57). The map is in the state hash.
- **Instances** (`sim/instances/`): which map (a file in `maps/`) and which features in which
  order; players start on the map's starts. A new mechanic is a new feature that instances list;
  it never grows the core.
- **Names in code** (owner's rule, #45): clear differentiators, never a bare `monster` where one of
  these is meant. A `species` is what every monster is, captured or not; a `captured_monster` was
  caught by the player; a `wild_monster` can still be caught; an `ally_monster` fights on the
  player's side but isn't captured and can't be. They're names, not necessarily separate classes.
- **Commands** (`sim/command.gd`): the only way into the simulation. One per player per tick,
  indexed by player slot (`Command.of`), integers only. The starting state plus every tick's
  commands is a replay.
- **`meta/`, the layers above a run** (#37): the player's `Profile` (captured monsters, materials,
  unlocked slots) lasts between runs. A run is the profile's party plus an instance and a seed
  (`Instances.create`): deterministic, like everything in `sim/`. **Whatever the player obtains is
  saved at once** (owner, #73): each catch or find is a `Gain`, which `ProfileKeeper.take` applies
  and saves atomically right away, so a crash mid-run loses nothing; `finish_run` counts the run. The profile is saved as versioned JSON (`Profile.FORMAT`, `SaveStore`), integers and
  ids only: a newer format is refused, and an older one is migrated in `Profile.parse` once a second
  format exists. Content data (species, items) comes in #72.
- **`input/`, the input layer:** devices to commands. Every device presses the same InputMap actions
  (keys, the touch stick, later controllers). `LocalInput` turns them into the local player's
  command, and `HexInput.direction_toward` is where floats become a hex direction.
- **`view/`, the presentation:** scenes that read the state and draw it, interpolating between ticks
  (`GameDriver.tick_fraction()`). They never write the state. `HexLayout` is the only tile-to-world
  conversion. One-shot moments (a catch, a ring breaking, a hit) reach views as the tick's events
  through the driver's `ticked(tick, events)` signal (#34): every tick exactly once, in order,
  however many ticks a frame runs. Effects play from those; lasting looks come from the state.
- **`game/`, the driver:** `GameDriver` runs whole ticks from accumulated real time, in lockstep
  (#38). Real time decides when ticks happen, never what they do. Before each tick it polls its
  `CommandSource`s (the local player's `LocalSource`; later network peers or a replay), which put
  commands into the `CommandSchedule` `input_delay` ticks ahead; a tick runs only once every
  player's command for it is known, and a command once put is final. It keeps the last ticks' state
  hashes (`hashes`) for desync checks. It records every run (`GameDriver.recording`, a `Replay`,
  #35): the instance, seed, players, rules version and features, every change of a slot's command,
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
- **Never color alone** (owner's rule, #68): whatever the player tells apart by color (types,
  teams, states) also gets a symbol or a shape, so the game stays colorblind friendly.
- **The look is cel-shaded eye candy** (owner, #69): monsters and what the camera shows up close
  are medium-poly; only small things that don't read from the top-down camera may be low poly.
  Low-poly packs are placeholders. Every asset in the repository has a license that allows it
  here (CC0, CC BY with credit), kept next to it.

### Testing and CI

- **Every user flow has one coherent e2e test, headless** (owner's rule): one flow for booting
  into the world, one for moving on the hex grid, one for a full catch or combat encounter, and so
  on. A change to an area extends the flow that covers it with new steps; a new flow file
  (`tests/e2e/test_<flow>.gd`) is only for a new user flow. No collections of small unrelated tests,
  and no separate unit tests while the flows already check the same things (owner, #61).
- **Exactly one e2e flow runs on the APK** (owner's rule, #61): `tests/apk/apk_flow.gd`, on an
  Android emulator in CI (`apk-e2e`, started by `game/test_mode.gd` in the test APK only). It
  starts from a fixed seed, scripts its touches per tick, and must end in `EXPECTED_HASH`, which
  the same flow pins headless (`tests/e2e/test_apk_flow.gd`). A rule change that moves it updates
  it on purpose, like the golden replays. Everything else stays headless. `apk-e2e` is a required
  check: it passed on its first run, and the owner asked to enforce it then.
- **The test runner is our own** (`tests/e2e/run_e2e.gd`). The owner kept it over a framework
  for now (#61).
- **A fresh checkout needs `godot --headless --path . --import`** before headless runs.
- **A script error in the runner itself leaves the SceneTree running forever.** Every CI step that
  runs Godot needs a `timeout`, and every job a `timeout-minutes`.
- **Local names that shadow a base-class method or property fail the script check**: `reference`,
  `position`, `script`, `name`, and the test's own `run` have all bitten. So have discarded return
  values (`erase`, `resize`, a method returning the thing it added): assign them to a `_`-prefixed
  local, and an inner test class named like a global one (`Walk`).
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
  the checksum. Bump a version and its checksum together. The runner image is named explicitly
  (`ubuntu-26.04`, not `ubuntu-latest`), so a new image arrives on purpose, with the APK build
  checked, not on GitHub's date.
- **Golden replays** (`tests/replays/*.replay`) are played by the replay flow in CI. One that stops
  matching means a change altered what the game does. If that is on purpose, bump
  `Simulation.RULES_VERSION`, rehash them (`godot --headless --path . -s
  res://tests/replays/rehash.gd`) and say in the pull request why the game plays out differently.
  Never rehash to make a surprise go away.
- **No measured numbers in docs or comments** (durations, sizes, counts): they go stale. They belong
  in the PR or issue that measured them.

### Repository and accounts

- **`main` is protected by the ruleset "protect main"**, with no bypass: pull requests only, one
  approval (later pushes don't dismiss it), review threads resolved, the `headless` and `apk-e2e`
  checks from GitHub Actions green on a branch that is up to date with `main`, squash merges only, no
  force-push or deletion. The required checks are named after the CI jobs: renaming a job means
  changing the ruleset in the same PR (owner's `gh`).
- **Pull requests opened with the owner's account can't be approved by the owner.** The bot opens
  them.

### Toolchain

- **Install tools with scoop** (owner's rule). The development machine runs Windows, so Homebrew isn't
  available.
- **`git push` hung on a Windows credential prompt.** In this repository the repo-local credential
  helper above avoids it. For the owner's own pushes elsewhere, `gh auth setup-git` makes git use the
  `gh` login.
