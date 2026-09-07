# Working on swaco

Instructions for Claude Code in this repository. Humans may read them too.

## Read first

The documents are the source of truth, in this order of authority:

1. [PHILOSOPHY.md](PHILOSOPHY.md): what we believe and never violate.
   When a decision conflicts with it, the decision is wrong.
2. [GOALS.md](GOALS.md): what we are trying to achieve, the non-goals, and
   how to place something (core, swaco, or the app).
3. [ARCHITECTURE.md](ARCHITECTURE.md): modules and the rules between them.
4. [FEATURES.md](FEATURES.md): what we are building and its status.
5. [ORIGIN.md](ORIGIN.md): why any of this exists.

Before proposing a design or adding anything, check it against the placement
test in GOALS and the six rules in ARCHITECTURE. If it needs a new principle,
change PHILOSOPHY first, and say so.

## Default answers

- Should swaco also do this? **No**, until the addition proves its place.
- Does this belong in the core? Only if the loop fails without it.
- Does the answer depend on the product? Then it is the app's, and swaco
  asks for it explicitly rather than assuming one.
- Is there a default policy we could ship? **No.** Swaco owns facts, the app
  owns policy, not even a cautious one.

## Code rules

- Swift 6, strict concurrency, no `@unchecked Sendable`. If the design
  cannot be expressed without one, the design changes.
- The core depends on the standard library and Foundation, nothing else. No
  third-party dependencies anywhere in the package.
- Dependencies point down only; peers do not import each other. See
  ARCHITECTURE rules 1 and 2.
- Our own providers, extensions and toolsets use only public protocols. A
  needed private path means the core is deficient; fix the core.
- Every public symbol is documented and `Sendable`.
- Tests use Swift Testing and never touch the network. Provider tests run
  against recorded fixtures.
- The event log format is public API. Evolve it by addition only; never
  drop an unknown event type.
- The canonical first program stays at twenty lines or fewer. Protocols bend
  to keep it so; the example does not grow.

## Documentation rules

- Documents are in English, terse, and use one meaning per word. The
  vocabulary in FEATURES is fixed; do not introduce synonyms.
- Update FEATURES status as work lands. Items are `[ ]`, `[~]` or `[x]`.
- A design decision made in review is recorded in the document it affects,
  in the same commit as the change, not in a separate notes file.
- Do not create new top-level documents without being asked. The five
  design documents, this file and GITFLOW are enough.

## Workflow

Branching, commits and merging are in [GITFLOW.md](GITFLOW.md). In short:
branch from `main`, keep history linear, fast-forward only, one change per
commit with a sentence as its title.

## Not yet decided

- The spike in FEATURES ("Spike before design") has not run. Do not build
  SwacoAI, SwacoRuntime or any provider until it has an answer.
- The first real app is a simple chatbot, recorded in GOALS. It drives
  the order of FEATURES but not the shape of the vocabulary: nothing in the
  core may assume a chat. Do not reorder FEATURES beyond what that app needs.
