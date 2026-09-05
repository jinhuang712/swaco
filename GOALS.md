# Goals

This document turns the [philosophy](PHILOSOPHY.md) into commitments: what
swaco sets out to achieve, what it deliberately will not do, which way it leans
when forced to choose, and the constraints it imposes on itself. Unlike the
philosophy, this document is expected to evolve. Unlike code, it should evolve
slowly and on purpose.

## Goals

These are outcomes we commit to. Each can be checked.

1. **An iOS app becomes agentic in a single step.** From adding the package to
   the first conversation that calls a tool is one screen of code. Sensible
   defaults cover everything not explicitly configured.
2. **Any model, without changing the app.** Switching between hosted models
   and Apple's on-device models is a configuration change. Tools, sessions and
   extensions are untouched.
3. **On-device models are first class.** An app can be agentic with no API
   key and no network, using the model that ships with the system.
4. **Behaviour is shaped without modifying swaco.** Permission prompts,
   context compaction, memory, tracing, environment injection, tool discovery
   and tool gating can all be implemented outside swaco.
5. **Correct under the real app lifecycle.** A session survives suspension,
   termination and relaunch. Its state is always explainable and, where
   possible, resumable. A tool may wait on a person indefinitely and that
   wait survives a relaunch.
6. **Multiple sessions coexist under control.** An app can hold many sessions
   at once, with concurrency and budgets governed in one place.
7. **A complete, serialisable, replayable event stream.** Any interface and
   any debugging view can be rebuilt from the events alone.
8. **Bounded by default.** Every run has limits on turns, tokens and time, so
   a misbehaving loop cannot drain a device.
9. **Platform capabilities arrive as toolsets.** System frameworks such as
   calendar, reminders, contacts, location, weather, health and photos are
   offered as coarse-grained, individually selectable toolsets that declare
   the authorisation they need.
10. **Zero third-party dependencies and zero intrusion.** Swaco imposes no
    storage, no UI framework and no architecture on the app that adopts it.

### Longer term

- **iPadOS and macOS.** Supported eventually, not now. Nothing in the design
  should prevent it, and nothing in the schedule should be spent on it.
- **Sub-agents.** A sub-agent is a tool that runs another agent. The core
  needs nothing to support it, so it comes after the core is solid.
- **System toolsets that only make sense on macOS**, such as shell and file
  system access.

## Non-goals

These are the concrete edges of "less is more". They are written down so they
are not eroded one convenience at a time.

- **No UI.** Not even a small one.
- **No built-in tools in the core.** Toolsets are separate, optional modules.
- **No MCP client or server.** It can be built outside; the core does not
  know it exists.
- **No memory, retrieval or knowledge base.** Same.
- **No multi-agent orchestration.** No workflows, graphs or planners. A
  sub-agent is a tool.
- **No prompt templating or prompt management.**
- **No cost accounting, evaluation or usage dashboards.** Usage reported by
  the model is passed through faithfully in the event stream; what to do with
  it is the app's decision.
- **No server, proxy or key hosting.** Providers support custom endpoints and
  authentication so an app can route through its own backend.
- **No platforms other than Apple's.** No Linux, no server-side Swift, no
  Windows.
- **No support for system versions below iOS 26.**
- **No command-line product.** Swaco is a capability layer for apps, not a
  port of a terminal agent.
- **No privacy machinery beyond visibility.** Data flows are explicit and
  observable; redaction and policy are external.

## Trade-offs

When two goods conflict, this is the way we lean.

- **Simple over complete.** An API that serves most cases cleanly beats one
  that serves all cases awkwardly. The rest is handled by extensions or by
  stepping around swaco.
- **Explicit over magic.** We would rather the adopter write two more lines
  than have swaco infer or act on its own.
- **Stable over novel.** Public surface is hard to take back, so we expose
  less.
- **Predictable recovery over perfect recovery.** A reply interrupted by the
  system is discarded and marked, not resumed. A reply stopped by the person
  is kept and marked as stopped.
- **The adopter's convenience over ours.** Internals may be complex; the
  public surface must be simple.
- **Refusal over compromise.** When it is unclear whether a feature belongs,
  it does not.
- **Coarse toolsets over many tools.** One tool per domain with an action
  parameter beats one tool per action; it costs less context and is misused
  less.

## Constraints

Rules we impose on ourselves. Breaking one is a bug.

- The core depends on nothing but the standard library and Foundation, and
  knows nothing about any provider, toolset, storage or UI framework.
- The core's understanding of a toolset is limited to its name, its
  description and its expansion into tools. A single tool is a toolset of
  one.
- The set of tools shown to the model on each turn can be rewritten from the
  outside before the request is made.
- Every tool call can be intercepted, rewritten, deferred or refused before it
  runs.
- Tools may require the main actor; the loop handles the hop.
- Every run can be cancelled at any moment and leaves no inconsistent state.
- Every event is persisted as it happens, append-only.
- All public types are `Sendable` and serialisable. All public symbols are
  documented and follow Swift naming conventions.
- Anything that touches the network can be replaced by a mock; the test suite
  never needs a network.
- Text shown to the model, such as tool names and descriptions, is stable and
  in one language. Text shown to people is the app's to localise.
- Every module beyond the core can be linked independently, and the core
  works when it is absent.
- Before 1.0, breaking changes are allowed and recorded. After 1.0, semantic
  versioning applies.

## Immediate focus

Swaco is developed by building a real app on it first. The first toolsets,
the first provider integrations and the first extensions are chosen by what
that app needs, not by what would look complete.
