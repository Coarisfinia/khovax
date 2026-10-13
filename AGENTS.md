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
- **Each clone or worktree**, once after creating it:

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

**One pull request at a time** (owner's rule). Never stack pull requests or work on two open ones in
parallel: pull requests are squash-merged, which rewrites the history a stacked branch is built on. Open
the next one as soon as the previous one is merged.

**One pull request per coherent change**: one feature, one fix or one refactor, whole. Side findings,
refactors and tooling tweaks get their own issue and their own pull request later, never along for the
ride.

**Keep each pull request low in complexity.** Prefer the simplest solution that does the job, and
Godot's built-in way over a hand-built one.

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
  one, and publish it on the `assets` branch (an orphan branch that is
  never merged): `![what it shows](https://github.com/Flixbox/khovax/blob/assets/pr-<n>-<what>.png?raw=true)`.
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

- **`sim/`, the simulation:** the rules (`Simulation.step(state, commands)`), the state
  (`GameState`) and the grid math (`Hex`). Plain `RefCounted` classes, integers only, durations in
  ticks (`Simulation.TICKS_PER_SECOND`). No nodes, `Input`, `Time`, `Engine`, `OS`, global
  randomness, frame `delta` or `float`: CI greps for them. Randomness, once a rule needs it, comes
  from a generator kept in `GameState`. `GameState.state_hash()` fingerprints the whole state; a
  new field goes into the hash too.
- **Commands** (`sim/command.gd`): the only way into the simulation. One per player per tick,
  integers only. The starting state plus every tick's commands is a replay.
- **`input/`, the input layer:** devices to commands. Every device presses the same InputMap actions
  (keys, the touch stick, later controllers). `LocalInput` turns them into the local player's
  command, and `HexInput.direction_toward` is where floats become a hex direction.
- **`view/`, the presentation:** scenes that read the state and draw it, interpolating between ticks
  (`GameDriver.tick_fraction()`). They never write the state. `HexLayout` is the only tile-to-world
  conversion.
- **`game/`, the driver:** `GameDriver` runs whole ticks from accumulated real time and collects
  the commands. Real time decides when ticks happen, never what they do. Later, network and replay
  commands come in here too.
- A new mechanic puts its rules and data into `sim/` with a replay check, its controls into
  `input/` as commands, and its look into `view/`.

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

### Testing and CI

- **Every user flow has one coherent e2e test** (owner's rule): one flow for booting into the
  world, one for moving on the hex grid, one for a full catch or combat encounter, and so on. A
  change to an area extends the flow that covers it with new steps; a new flow file
  (`tests/e2e/test_<flow>.gd`) is only for a new user flow. No collections of small unrelated tests.
- **Start with a minimal runner of our own.** Once there are five or more full flows of real game
  mechanics, switch to a test framework (owner's rule).
- **A fresh checkout needs `godot --headless --path . --import`** before headless runs.
- **A script error in the runner itself leaves the SceneTree running forever.** Every CI step that
  runs Godot needs a `timeout`, and every job a `timeout-minutes`.
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
- **No measured numbers in docs or comments** (durations, sizes, counts): they go stale. They belong
  in the PR or issue that measured them.

### Repository and accounts

- **`main` is protected by the ruleset "protect main"**, with no bypass: pull requests only, one
  approval (later pushes don't dismiss it), review threads resolved, the `headless` check from GitHub
  Actions green on a branch that is up to date with `main`, squash merges only, no force-push or
  deletion. The required check is named after the CI job: renaming the job means changing the
  ruleset in the same PR (owner's `gh`).
- **Pull requests opened with the owner's account can't be approved by the owner.** The bot opens
  them.

### Toolchain

- **Install tools with scoop** (owner's rule). The development machine runs Windows, so Homebrew isn't
  available.
- **`git push` hung on a Windows credential prompt.** In this repository the repo-local credential
  helper above avoids it. For the owner's own pushes elsewhere, `gh auth setup-git` makes git use the
  `gh` login.
