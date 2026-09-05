# Features

The concrete capabilities swaco will have, tracked against the
[goals](GOALS.md). This is a working list: items move between sections, get
split, or get dropped. Status is one of *planned*, *in progress*, *done*.

Legend: `[ ]` planned · `[~]` in progress · `[x]` done

## Core

- [ ] Canonical message and content types: text, image, tool call, tool
      result, reasoning, provider-executed tool use and result, citations
- [ ] Canonical streaming event set shared by all providers
- [ ] `Tool` protocol with JSON Schema parameters and typed results
- [ ] `ToolSet` protocol: name, description, expansion into tools; a single
      tool is a toolset of one
- [ ] Tools may run on the main actor; the loop performs the hop
- [ ] `Provider` protocol: one streaming call, declared capabilities
      (vision, reasoning, provider-executed tools, context size)
- [ ] Model described as data (provider, identifier, capabilities)
- [ ] Agent loop: context in, event stream out; request, stream, execute
      tool calls, repeat until the model stops. Knows nothing about runs or
      sessions
- [ ] Extension protocol whose hooks are exactly the moments of the loop:
      before a request, after a response, before a tool call, after a tool
      call, end of turn, end of loop. Extensions apply in registration
      order; rewrites chain, any refusal wins
- [ ] Cancellation at any point with no inconsistent state; distinguishes
      stop-by-person (partial reply kept and marked) from
      interrupt-by-system (partial reply discarded and marked)
- [ ] Custom endpoint and authentication on every hosted provider
- [ ] Zero dependencies beyond the standard library and Foundation

## Runtime

- [ ] `Run`: swaco's standard unit of work. Instructions, input, tools and
      model in; events and a final result out. Needs no session
- [ ] `Session`: swaco's standard grouping of runs into a persistent
      history. Optional; apps with no history never touch it
- [ ] Agent configuration decoupled from history: one session can be
      continued by differently configured agents, one configuration can
      serve many sessions
- [ ] Session state machine: idle, running, awaiting tool approval, awaiting
      person, interrupted, failed
- [ ] Session registry and lookup
- [ ] Concurrency limit across all runs, with or without
      sessions
- [ ] Recovery on relaunch according to last persisted state
- [ ] A tool may wait on a person indefinitely; the wait survives relaunch
- [ ] Sub-agent as a tool (longer term)

## Storage

- [ ] `SessionStore` protocol
- [ ] File-based store: per-session metadata plus append-only event log,
      written as events happen
- [ ] Keychain helper for credentials

## Providers

- [ ] Anthropic (streaming, tool use, provider-executed web search)
- [ ] OpenAI, including OpenAI-compatible endpoints
- [ ] Apple Foundation Models (on-device), with graceful degradation where
      capabilities are missing
- [ ] Gemini (later)
- [ ] Replayable mock provider for tests

## Extensions (shipped, optional)

- [ ] Environment context: time, time zone, locale, device
- [ ] Tool approval: defer side-effecting tools until the app confirms
- [ ] Authorisation gating: hide or defer tools whose system permission is
      not granted
- [ ] Progressive tool disclosure: expose few tools plus a discovery tool
- [ ] Retry with backoff for transient network errors
- [ ] Budget: stop a loop after a chosen number of turns, tokens or seconds
- [ ] Context compaction (later)

## Toolsets (shipped, optional)

Each toolset is coarse-grained, individually selectable at tool granularity,
and declares the system authorisation it needs. Order follows the needs of the
first app built on swaco.

- [ ] Calendar (EventKit)
- [ ] Reminders (EventKit)
- [ ] Contacts
- [ ] Location and places (CoreLocation, MapKit)
- [ ] Weather (WeatherKit)
- [ ] Photos (PhotoKit)
- [ ] Health (HealthKit)
- [ ] Music (MusicKit)
- [ ] Notifications (UserNotifications)
- [ ] Web: fetch a page locally; search via an app-supplied backend (later)
- [ ] Shell and file system, macOS only (longer term)

## Project

- [ ] Swift Package with independently linkable modules; the core works
      when every other module is absent
- [ ] iOS 26 minimum; macOS 26 compiles but is not yet supported
- [ ] Swift 6 strict concurrency; all public types `Sendable` and
      serialisable
- [ ] Every public symbol documented, Swift naming conventions
- [ ] Swift Testing suite that never touches the network
- [ ] CI on GitHub Actions
- [ ] Breaking changes allowed and recorded before 1.0; semantic versioning
      after
- [ ] A sample app demonstrating one-step adoption
