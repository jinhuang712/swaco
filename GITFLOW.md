# Git flow

How changes reach `main`. Few rules, all of them about keeping history
readable, because the log of what we decided is part of what swaco is.

## Small steps, landed often

A branch is a small step, not a project. It should land within a day or
two, carry one change that is complete on its own, and leave `main` in a
state anyone can build on. A step too big to finish soon is split before it
starts, not after it has drifted.

Why: `main` is where the design is tested against reality. The sooner a
change is there, the sooner it is seen, used, and corrected. Long branches
hide decisions, accumulate conflicts, and land as one large diff that nobody
reads. Many small commits on `main` read as a story; one large merge reads
as a wall.

In practice:

- If a change needs a second sentence to describe, it is probably two
  changes.
- A step may be incomplete as a feature but must be complete as a change:
  it builds, its tests pass, and the documents agree with it.
- FEATURES tracks progress with `[~]`; a branch does not need to move an
  item to `[x]` to land.
- When a branch has lived more than a few days, land what is finished and
  start a new branch for the rest.

## Branches

- `main` is always linear and always releasable. Nothing is committed to it
  directly.
- Every change starts on a branch from `main`. The name has two parts,
  `area/change`, lower-case with hyphens:

  | Area | Used for |
  |---|---|
  | `core/` | the `Swaco` module |
  | `ai/` | `SwacoAI` and providers |
  | `runtime/` | `SwacoRuntime` |
  | `interaction/`, `extensions/`, `testing/` | the module of that name |
  | `examples/` | the first program, templates, sample app |
  | `docs/` | the documents alone |
  | `spike/` | throwaway code that answers one question |
  | `ci/` | GitHub Actions and project configuration |

  The change part names the step, not the goal: `core/tool-protocol`, not
  `core/tools`; `docs/architecture-file-tree`, not `docs/update`.
- Tool-generated names such as `claude/...` are acceptable for work that
  lands the same day. Rename before opening a pull request otherwise.
- A branch lives for one change. When it lands, delete it.

## Commits

- One change per commit. If the title needs "and", split it, unless the
  parts are meaningless apart.
- The title is a sentence in the imperative or the indicative, capitalised,
  no trailing period, under about seventy characters. It says what changed
  and, where it fits, why:
  `Authentication belongs to SwacoAI: Authenticator, TokenStore, explicit configuration`.
- A body is optional. When present it explains the reasoning, not the diff.
- A design decision is recorded in the document it affects, in the same
  commit as the code or text it changes.
- Do not commit generated files, build products or local tool state. The
  `.gitignore` says what those are.

## Landing on `main`

1. Rebase the branch onto the current `main`. Resolve conflicts on the
   branch, never on `main`.
2. Open a pull request against `main`. The description is the commit title
   of a one-commit branch, or a short summary otherwise.
3. Merge by fast-forward only. No merge commits, no squash unless the branch
   history is noise. If `main` moved, rebase again and retry.
4. Delete the branch.

A fast-forward push from the command line is equivalent to merging the pull
request; GitHub marks it merged.

## Reverting

Revert with `git revert`, never by rewriting `main`. The revert commit's
title names what it undoes and its body says why. Reapply as a fresh commit
when the reason is gone.

## Releases

- Before 1.0, breaking changes are allowed and recorded in the commit that
  makes them. There is no changelog file; the log is the changelog.
- From 1.0, semantic versioning. A tag `vX.Y.Z` on `main` is a release. The
  event log format and the Swift API are versioned together.
- Companions release on their own schedule under their own tags.

## Checks

CI runs on every pull request: build every target on its own, run the test
suite without network access, build the examples. A pull request does not
land while CI is red.
