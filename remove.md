# remove.md: take the AI co-author off this repo's commits

## First: what's actually in this repo

Every commit's **author** is already you (`Tanay S Chithore`). The AI
appears only as a **trailer line** at the end of the commit message:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
```

GitHub reads that line and lists a second contributor. So changing the
author (`git commit --amend --author=...`) **does not fix it**. The line has
to be deleted from the commit messages.

Commits that carry it (9 of 10; the root commit `0d0c50a` is clean):

| Commit | Subject |
|---|---|
| `51bfb4f` | Rebuild the feel test as an endless expressway with viaduct ramps and a minimap |
| `10c9bfb` | Add context.md: one-page project overview and the atmosphere brief |
| `9bd6992` | Fix the freeze after killing the governor in a campaign |
| `7eff1da` | Make the AK-47 full-auto only, stop hot-reloading the Rust extension |
| `fb23f48` | Animate NPCs from the Quaternius library, add locational wounds, rope yank and tether, suppressed AK-47 |
| `57b8248` | Add death ragdolls, pistol/knife/grapple, drivable street cars, armoured guards |
| `16ddfd1` | Add the Pataliputra Exchange, Kestrel 80 wedge car with cockpit, reflex sight |
| `cf8b42e` | Rework gunfeel, menu, weather and visuals |
| `02532dd` | Build the first playable: feel test, Saptavarta vertical slice, war room |

Check this list again before you start (it changes with every new commit):

```bash
git log --format='%h %s%n    %(trailers:key=Co-Authored-By,valueonly)'
```

## 0. Back up first

Rewriting history changes every commit hash from the first edited commit
onward. Keep a way back:

```bash
git branch backup-before-rewrite
```

Commit or stash any work in progress first. Untracked files, such as
`Animation Library[Standard]/`, are not touched.

## Option A (recommended): strip the line from every commit at once

One command, no editor, keeps the original author and commit dates:

```bash
git filter-branch -f --msg-filter 'sed "/^Co-Authored-By: Claude/d" | git stripspace' -- main
```

- `sed` deletes the trailer line, and `git stripspace` removes the blank line
  left behind.
- Git prints a warning recommending `git filter-repo`. It is safe to ignore for
  a repo this size.

Check the result. This should print nothing:

```bash
git log --format='%(trailers:key=Co-Authored-By,valueonly)' | grep .
```

## Option B: the interactive-rebase way (by hand)

The same idea as the pasted guide, but you edit the **message**, not the author.

```bash
git rebase -i --root --committer-date-is-author-date
```

1. In the todo list, change `pick` to `reword` (or `r`) on each of the 9 commits above.
2. Save and close. Git opens each message in turn.
3. Delete the `Co-Authored-By: Claude ...` line (and the blank line above it).
   Save and close.
4. Repeat until the rebase finishes. If it stops, `git rebase --continue`.

Note: Claude Code can't run `rebase -i` for you, because it needs an
interactive editor. Run this one yourself in a terminal.

## Pushing the rewritten history

The remote is `origin` (`github.com/ChithoreTanay1/Atom-Punk-Mag`).
Commits that were already pushed now have new hashes, so a normal push is
refused. Overwrite the remote branch:

```bash
git push --force-with-lease origin main
```

- `--force-with-lease` refuses to overwrite if someone else pushed in the
  meantime. Use it, not `--force`.
- Anyone else with a clone must re-sync (`git fetch` then
  `git reset --hard origin/main`). If it's only you, there's nothing to do.

Once you're happy with the result, delete the backup:

```bash
git branch -D backup-before-rewrite
```

## Getting GitHub's contributor list to refresh

GitHub caches the contributors graph, and it can lag for a long time after
a rewrite. A workaround that often forces a recount is to rename the default
branch and rename it back. Do it on GitHub (Settings → Branches → rename
`main` to `main1`, then back to `main`) or with:

```bash
git push origin main:main1
# On GitHub: make main1 the default branch, delete main, push main again, make it default, delete main1.
```

This is not guaranteed: it's a community trick, not a documented feature.

## Stopping it on future commits

Claude Code adds the trailer when it commits for you, unless you tell it
not to. Put a line like this in a `CLAUDE.md` at the repo root:

```
Do not add Co-Authored-By or "Generated with Claude Code" lines to commits or PRs.
```

You can also turn attribution off in Claude Code's settings (`/config`).
