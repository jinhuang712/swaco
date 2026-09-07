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
- **Agent**: the loop, configured and callable: model, tools, extensions in;
  a stream of events out. Lives in the core
- **Run**: swaco's unit of work; an agent's loop from a starting event to a
  final result, recorded and recoverable. Lives in the runtime, not the core
- **Session**: swaco's grouping of runs into a persistent history. Optional
- **Tool**: something the model can ask to have done
- **Toolset**: a named group of tools; a single tool is a toolset of one
- **Extension**: a value that acts at one or more moments of the loop
- **Provider**: the translation between swaco's vocabulary and one model API

## Core

- [ ] One event vocabulary for everything that enters or leaves the agent.
      Inbound events carry a source (person, shortcut, notification, URL,
      share, system, schedule, sensor), a payload of content parts or
      structured data, and the execution context they arrived in. A
      message from a person is one kind of inbound event. What the loop and
      its extensions decide along the way is recorded the same way: a
      rewrite, a refusal, an injected or queued arrival, a capability the
      content asked for and the model had not declared. Replaying the log
      shows why the loop went the way it did, not only where it went
- [ ] Source travels with the content into the model's context, so the
      model and extensions can tell what a person said from what the system
      delivered
- [ ] Canonical message and content types: text, image, tool call, tool
      result, reasoning, provider-executed tool use and result, citations
- [ ] Canonical streaming event set shared by all providers
- [ ] Messages are a projection of the event log, not a separate store
- [ ] Content parts can hold a reference to stored bytes instead of the bytes
      themselves, loaded on demand through the `ContentStore` protocol, so a
      long history with media stays cheap in memory
- [ ] `EventStore` and `ContentStore` protocols with their contracts: ordered
      append, durable on return, read by group in write order, replay from a
      position; bytes by reference. The core defines both and holds neither
- [ ] `Tool` protocol: JSON Schema parameters, typed results, and a
      declared access of read-only or writing. Access has no default and is
      a fact for extensions and the app to read; the loop acts on it in no
      way
- [ ] `ToolSet` protocol: name, description, expansion into tools; a single
      tool is a toolset of one
- [ ] Tool execution is a pair of events, call issued and result arrived,
      never an awaited function. A tool either delivers its result at once
      or registers that the result will arrive later; the loop advances only
      on the result event. A tool that registers a later result also states
      how to resume it: given the call it once registered, in a fresh
      process, it re-arms whatever will deliver the result. This pair,
      register and resume, is what lets a wait survive relaunch
- [ ] Tools may run on the main actor; the loop performs the hop
- [ ] Rendering of inbound events into model-readable content is a
      protocol with one default implementation the app may replace whole
- [ ] `Provider` protocol: one streaming call, declared capabilities
      (vision, reasoning, provider-executed tools, context size)
- [ ] Model described as data (provider, identifier, capabilities)
- [ ] `Agent`: the loop, callable on its own. Context in, event stream out;
      request, stream, execute tool calls, repeat until the model stops.
      Knows nothing about runs or sessions; the first program calls it
      directly
- [ ] Extension protocol whose hooks are exactly the moments of the loop:
      an event arrives while the loop is running, before a request, after a
      response, before a tool call, after a tool call, end of turn, end of
      loop. Each hook may pass, rewrite or refuse; the arrival hook may also
      inject the event into the next turn, queue it, or leave it for whatever
      runs the loop. The app declares extensions as an ordered list; swaco
      applies them strictly in that order, chains rewrites, and lets any
      refusal win
- [ ] Cancellation at any point with no inconsistent state. Nothing received
      is ever discarded: a partial reply is recorded as received and marked
      with why it stopped, by a person or by the system. Whether it is shown
      or sent back to the model is the app's decision
- [ ] Zero dependencies beyond the standard library and Foundation

## Runtime

- [ ] `Run`: swaco's standard unit of work; an `Agent` loop with every event
      recorded to the named store as it happens. Instructions, input, tools
      and model in; events and a final result out. Needs no session
- [ ] `Session`: swaco's standard grouping of runs into a persistent
      history. Optional; apps with no history never touch it
- [ ] Agent configuration decoupled from history: one session can be
      continued by differently configured agents, one configuration can
      serve many sessions
- [ ] Session state machine: idle, running, awaiting a result, interrupted,
      failed. Awaiting a result covers every tool that registered a later
      result, a person's answer among them
- [ ] Intake extension: the runtime's implementation of the arrival hook.
      The app supplies a mapping from source and session state to inject,
      queue or leave; left events start a new run. An app that does not list
      the extension starts a new run for every event that arrives during
      another
- [ ] Execution context exposed to extensions: foreground, background,
      app extension process, remaining time, whether a person is present
- [ ] A loop can stop after one turn and hand the rest to a later process;
      the handover survives the process boundary
- [ ] Session registry and lookup
- [ ] Concurrency limit across all runs, with or without
      sessions
- [ ] Recovery on relaunch according to last persisted state: the log is
      read, every call left without a result is handed back to its tool to
      resume, and the loop continues from where the events stop
- [ ] Sub-agent as a tool (longer term)

## Storage

The core fixes what must be stored and with what guarantees; the app decides
where. No store is chosen by default: an app that uses sessions or referenced
content names one.

- [ ] Conformance test suites that any `EventStore` or `ContentStore`
      implementation runs, in `SwacoTesting`
- [ ] Reference implementations in the runtime: in-memory, and a plain file
      store that can live in an App Group container so an app extension and
      the main app share it
- [ ] SQLite, SwiftData and CloudKit stores as companions or third-party
      packages, not in swaco

## Media (companion)

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
      view and vendor client ids, are companions
- [ ] All configuration is passed explicitly in code. No configuration
      files, no environment variables
- [ ] Assembly of streamed tool-call arguments from partial fragments
- [ ] Lossless conversion of messages, tool definitions and tool results
      between swaco's vocabulary and vendor shapes, ids preserved
- [ ] Normalisation of stop reasons, usage and errors into swaco's types
- [ ] Generic implementation of the OpenAI-compatible protocol, configured
      per vendor rather than re-implemented
- [ ] Model catalogue: identifier, provider, declared capabilities
- [ ] Recorded request and response fixtures for every provider we ship;
      the conformance suite that runs them lives in `SwacoTesting`

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
- [ ] Tool approval: route chosen tool calls through `confirm`. Which calls
      are chosen is the app's rule over the facts swaco declares, a tool's
      access and an event's source; with no rule, nothing is held
- [ ] Retry with backoff for transient network errors

## Extensions (templates)

Strategies an app may want and would answer in its own way. Each is a
complete, compiling example under `Examples/`, built in CI, copied into the
app and owned by it from then on. Not shipped, not versioned.

- [ ] Progressive tool disclosure: expose few tools plus a discovery tool
- [ ] Budget: stop a loop after a chosen number of turns, tokens or seconds
- [ ] Context compaction

Authorisation gating, which hides or defers tools whose system permission is
not granted, is a bridge to the platform and ships with the platform toolsets
in `swaco-kits`.

## Platform toolsets (companions)

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

- [ ] The event log format is public API, on the same terms as the Swift
      API: documented, versioned, evolved by addition only. A newer swaco
      replays logs written by an older one, and unknown event types are
      preserved, never dropped. A run is reproduced by replaying its log
      through the mock provider; a bug report is a log
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
- [ ] Providers expose availability: not on this device, model downloading,
      ready. Apps decide before the first request, not after the first
      failure
- [ ] No initialisation step, no account, no configuration file. The core
      works the moment it is linked

## Declared by the app, no default

Every item here is one whose answer depends on the product. Adding an item
requires showing that it does. The list is kept short on purpose.

- Ordered list of extensions
- Event store and content store, when sessions or referenced content are used
- Authenticator, when a hosted provider is used
- Which tool calls require approval, by declared access or by source, when
  the approval extension is used
- Concurrency limit across runs, when more than one may run

## Acceptance

- [ ] The canonical first program: `import Swaco`, one provider, one tool,
      one `Agent`, one `for await` over its events, in twenty lines or fewer
      including the tool. No runtime, no store. Protocols bend to keep it
      so; the example does not grow

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
