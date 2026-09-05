# Features

The concrete capabilities swaco will have, tracked against the
[goals](GOALS.md). This is a working list: items move between sections, get
split, or get dropped. Status is one of *planned*, *in progress*, *done*.

Legend: `[ ]` planned · `[~]` in progress · `[x]` done

## Vocabulary

Fixed now, before code. Each word means one thing.

- **Event**: anything that enters or leaves the agent, recorded as it happens.
  One word for inbound events and loop events, distinguished by subtype
- **Source**: where an inbound event came from: a person, a shortcut, a
  notification, a URL, a share, the system, a schedule, a sensor
- **Turn**: one request to the model and everything until the model stops
- **Loop**: continuing with another turn while the model asks for tools
- **Run**: swaco's unit of work; a loop from a starting event to a final
  result. Lives in the runtime, not the core
- **Session**: swaco's grouping of runs into a persistent history. Optional
- **Agent**: the configured executor of a run: model, tools, extensions
- **Tool**: something the model can ask to have done
- **Toolset**: a named group of tools; a single tool is a toolset of one
- **Extension**: a value that acts at one or more moments of the loop
- **Provider**: the translation between swaco's vocabulary and one model API

## Core

- [ ] One event vocabulary for everything that enters or leaves the agent.
      Inbound events carry a source (person, shortcut, notification, URL,
      share, system, schedule, sensor), a payload of content parts or
      structured data, and the execution context they arrived in. A
      message from a person is one kind of inbound event
- [ ] Source travels with the content into the model's context, so the
      model and extensions can tell what a person said from what the system
      delivered
- [ ] Canonical message and content types: text, image, tool call, tool
      result, reasoning, provider-executed tool use and result, citations
- [ ] Canonical streaming event set shared by all providers
- [ ] Messages are a projection of the event log, not a separate store
- [ ] Content parts can hold a reference to stored bytes instead of the bytes
      themselves, loaded on demand, so a long history with media stays cheap
      in memory
- [ ] `Tool` protocol with JSON Schema parameters and typed results
- [ ] `ToolSet` protocol: name, description, expansion into tools; a single
      tool is a toolset of one
- [ ] Tool execution is a pair of events, call issued and result arrived,
      never an awaited function. A tool either delivers its result at once
      or registers that the result will arrive later; the loop advances only
      on the result event. This is what lets a wait survive relaunch
- [ ] Tools may run on the main actor; the loop performs the hop
- [ ] Safety floor: in a turn triggered by an event whose source is not a
      person, every tool call is held for the app's release. The app may
      lift this per source or per tool; it is the one rule that is on
      unless switched off
- [ ] Rendering of inbound events into model-readable content is a
      protocol with one default implementation the app may replace whole
- [ ] `Provider` protocol: one streaming call, declared capabilities
      (vision, reasoning, provider-executed tools, context size)
- [ ] Model described as data (provider, identifier, capabilities)
- [ ] Agent loop: context in, event stream out; request, stream, execute
      tool calls, repeat until the model stops. Knows nothing about runs or
      sessions
- [ ] Extension protocol whose hooks are exactly the moments of the loop:
      before a request, after a response, before a tool call, after a tool
      call, end of turn, end of loop. The app declares extensions as an
      ordered list; swaco applies them strictly in that order and imposes no
      ordering of its own. Rewrites chain, any refusal wins
- [ ] Cancellation at any point with no inconsistent state. Nothing received
      is ever discarded: a partial reply is recorded as received and marked
      with why it stopped, by a person or by the system. Whether it is shown
      or sent back to the model is the app's decision
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
- [ ] Event intake policy when a run is in progress: start a new run, inject
      into the next turn, or queue. Declared by the app when it uses
      sessions; there is no default
- [ ] Execution context exposed to extensions: foreground, background,
      app extension process, remaining time, whether a person is present
- [ ] A loop can stop after one turn and hand the rest to a later process;
      the handover survives the process boundary
- [ ] Session registry and lookup
- [ ] Concurrency limit across all runs, with or without
      sessions
- [ ] Recovery on relaunch according to last persisted state
- [ ] A tool may wait on a person indefinitely; the wait survives relaunch
- [ ] Sub-agent as a tool (longer term)

## Storage

Swaco fixes what must be stored and with what guarantees; the app decides
where. No store is chosen by default: an app that uses sessions names one.

- [ ] `EventStore` protocol with a strict contract: ordered append, durable
      on return, read by group in write order, replay from a position
- [ ] Conformance test suite that any `EventStore` implementation runs
- [ ] Reference implementations: in-memory, and a plain file store that can
      live in an App Group container so an app extension and the main app
      share it
- [ ] `ContentStore` protocol for bytes referenced from content parts, with
      the same contract-plus-conformance approach
- [ ] SQLite, SwiftData and CloudKit stores as satellites or third-party
      packages, not in swaco

## Media (satellite)

A package under our name, outside swaco. Turns media as it exists on a phone
into content the chosen model accepts. Presenting a picker is the app's;
everything after the person has chosen is this package's. Toolsets that
retrieve media on the agent's behalf pass their results through it.

- [ ] Read from the forms iOS hands over: picker results, item providers
      from the share sheet, security-scoped URLs, camera output, raw data
- [ ] Download iCloud placeholders before use
- [ ] Images: convert HEIC and other formats, apply EXIF orientation, resize
      and recompress to the limits the target provider declares
- [ ] PDF: extract text, or render pages as images when text is absent
- [ ] Video: sample frames and transcribe audio locally (later)
- [ ] Store originals as references in the app or App Group container;
      never hold more than needed in memory

## Provider machinery (`SwacoAI`)

Everything providers share, done once. Depends on the core only; knows no
vendor. Our providers are built on it; a third party may use it or ignore it.

- [ ] HTTP and server-sent events over `URLSession`, with cancellation
- [ ] Connection configuration per provider: endpoint (vendor default,
      overridable) and an `Authenticator`
- [ ] `Authenticator` protocol: attach authentication to a request; refresh
      when the vendor signals it has expired. Implementations: static API
      key in the vendor's header, static bearer token, OAuth token pair with
      refresh, app-defined closure for an app's own backend. None is the
      default; the app names one
- [ ] `TokenStore` protocol for OAuth tokens; Keychain-backed reference
      implementation. Vendor-specific authorisation flows, which need a web
      view and vendor client ids, are satellites
- [ ] All configuration is passed explicitly in code. No configuration
      files, no environment variables
- [ ] Assembly of streamed tool-call arguments from partial fragments
- [ ] Lossless conversion of messages, tool definitions and tool results
      between swaco's vocabulary and vendor shapes, ids preserved
- [ ] Normalisation of stop reasons, usage and errors into swaco's types
- [ ] Generic implementation of the OpenAI-compatible protocol, configured
      per vendor rather than re-implemented
- [ ] Model catalogue: identifier, provider, declared capabilities
- [ ] Recorded request and response fixtures, and the provider conformance
      suite that runs against them

## Providers

Each is a thin module over `SwacoAI`.

- [ ] Anthropic (streaming, tool use, provider-executed web search)
- [ ] OpenAI, including OpenAI-compatible endpoints
- [ ] Apple Foundation Models (on-device)
- [ ] Gemini (later)
- [ ] Replayable mock provider for tests

## Interaction toolset (shipped, optional)

Tools through which the agent reaches the person. Swaco owns the mechanics
(the model sees the tool, a typed request appears in the event stream, the
loop suspends, the app answers, the loop continues, the suspension survives
relaunch). The app owns the presentation.

- [ ] `ask`: put a question to the person, free-form or with options
- [ ] `confirm`: have the person approve or refuse an action; also the shape
      used for requesting system authorisation
- [ ] `report`: tell the person about progress or an intermediate result
      without waiting and without ending the reply; payload may include
      media
- [ ] `ask` and `confirm` suspend the same way whether or not a person is
      present; the app decides how to bring the person back
- [ ] `schedule`: let the agent arrange a future wake-up that returns as an
      inbound event; the app supplies the mechanism (longer term)

## Extensions (shipped, optional)

Only what nearly every app needs and no product would answer differently.

- [ ] Environment context: time, time zone, locale, device
- [ ] Tool approval: route tool calls through `confirm`; the carrier of the
      safety floor
- [ ] Retry with backoff for transient network errors

## Extensions (satellites or templates)

Product strategy, or tied to platform frameworks. Not in swaco.

- [ ] Authorisation gating: hide or defer tools whose system permission is
      not granted (ships with the platform toolsets)
- [ ] Progressive tool disclosure: expose few tools plus a discovery tool
- [ ] Budget: stop a loop after a chosen number of turns, tokens or seconds
- [ ] Context compaction

## Platform toolsets (satellites)

Separate packages under our name, outside swaco, depending on it through the
same protocols any third party uses. Each toolset is coarse-grained,
individually selectable at tool granularity, and declares the system
authorisation it needs. Order follows the needs of the first app built on
swaco.

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

## Development and release

What swaco does for the life of an app around it: debugging, shipping,
upgrading. Build tooling, signing, distribution and onboarding are the app's.

- [ ] Event log export in a stable, documented format; a run is reproduced
      by replaying its log through the mock provider. A bug report is a log
- [ ] Recording: run once against a real provider, keep the exchange as a
      fixture, replay it thereafter. Development, previews and tests need no
      key and no network
- [ ] `os.Logger` by subsystem and signposts per turn and tool call, so a
      run is visible in Instruments. Structure is logged, content is not
- [ ] Privacy manifest shipped with the package: no tracking, no collection,
      no required-reason APIs
- [ ] Each module states its deployment requirements: entitlements, App
      Group, Info.plist usage strings. A debug-build check fails at launch,
      with a clear message, when a linked module's requirements are missing
- [ ] Event log format is versioned. A newer swaco replays logs written by
      an older one; unknown event types are preserved, never dropped
- [ ] Providers expose availability: not on this device, model downloading,
      ready. Apps decide before the first request, not after the first
      failure
- [ ] No initialisation step, no account, no configuration file. The core
      works the moment it is linked

## Declared by the app, no default

Every item here is one whose answer depends on the product. Adding an item
requires showing that it does. The list is kept short on purpose.

- Ordered list of extensions
- Event intake policy, when sessions are used
- Event store and content store, when sessions or referenced content are used
- Authenticator, when a hosted provider is used
- Lifting the safety floor, per source or per tool
- Concurrency limit across runs, when more than one may run

## Acceptance

- [ ] The canonical first program: one provider, one tool, one run, one
      `for await` over events, in twenty lines or fewer including the tool.
      Protocols bend to keep it so; the example does not grow

## Spike before design

- [ ] Can the event-pair loop, with a main-actor tool, a deferred result
      and external cancellation, compile under Swift 6 strict concurrency
      with no unchecked escapes?

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
- [ ] Templates: a minimal, complete, compiling example each of an app tool,
      a toolset and an extension, built in CI so they never drift from the
      API
