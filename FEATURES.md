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

- [x] One event vocabulary for everything that enters or leaves the agent.
      Inbound events carry a source (person, shortcut, notification, URL,
      share, system, schedule, sensor), a payload of content parts or
      structured data, and the execution context they arrived in. A
      message from a person is one kind of inbound event. What the loop and
      its extensions decide along the way is recorded the same way: a
      rewrite, a refusal, an injected or queued arrival, a capability the
      content asked for and the model had not declared. Replaying the log
      shows why the loop went the way it did, not only where it went
- [x] Source travels with the content into the model's context, so the
      model and extensions can tell what a person said from what the system
      delivered
- [x] Canonical message and content types: text, image, tool call, tool
      result, reasoning, provider-executed tool use and result, citations.
      Adjacent runs of words become one part, so two messages that say the
      same thing are the same message
- [~] Canonical streaming event set shared by all providers
- [x] Messages are a projection of the event log, not a separate store
- [x] Content parts can hold a reference to stored bytes instead of the bytes
      themselves, loaded on demand through the `ContentStore` protocol, so a
      long history with media stays cheap in memory. A request names the
      store; the provider fetches through it and holds none. A part that
      points somewhere with no store named is an error the app is told
      about, never a picture quietly dropped
- [x] `EventStore` and `ContentStore` protocols with their contracts: ordered
      append, durable on return, read by group in write order, replay from a
      position; bytes by reference. The core defines both and holds neither.
      Each contract is written where its protocol is, and the suite that
      checks it is the one every third-party store runs
- [~] `Tool` protocol: JSON Schema parameters, typed results, and a
      declared access of read-only or writing. Access has no default and is
      a fact for extensions and the app to read; the loop acts on it in no
      way
- [x] `ToolSet` protocol: name, description, expansion into tools; a single
      tool is a toolset of one, so `Tool` is a `ToolSet` and nothing needs
      wrapping to be handed over. An app takes part of a set at the
      granularity of a tool, by name or by a rule over what a tool declared
- [~] Tool execution is a pair of events, call issued and result arrived,
      never an awaited function. A tool either delivers its result at once
      or registers that the result will arrive later; the loop advances only
      on the result event. A tool that registers a later result also states
      how to resume it: given the call it once registered, in a fresh
      process, it re-arms whatever will deliver the result. This pair,
      register and resume, is what lets a wait survive relaunch
- [x] Tools may run on the main actor; the loop performs the hop
- [x] Rendering of inbound events into model-readable content is a
      protocol with one default implementation the app may replace whole
- [x] `Provider` protocol: one streaming call, declared capabilities
      (vision, reasoning, provider-executed tools, context size)
- [x] Model described as data (provider, identifier, capabilities)
- [x] `Agent`: the loop, callable on its own. Context in, event stream out;
      request, stream, execute tool calls, repeat until the model stops.
      Knows nothing about runs or sessions; the first program calls it
      directly
- [x] Extension protocol whose hooks are exactly the moments of the loop:
      an event arrives while the loop is running, before a request, after a
      response, before a tool call, after a tool call, end of turn, end of
      loop. Each hook may pass, rewrite or refuse; the arrival hook may also
      inject the event into the next turn, queue it, or leave it for whatever
      runs the loop. The app declares extensions as an ordered list; swaco
      applies them strictly in that order, chains rewrites, and lets any
      refusal win. A refusal before a call becomes that call's result so
      the model is told, and a refusal at the end of a turn ends the loop;
      a failed request is the one moment an extension may ask for another
      go. Things that arrive mid-loop are handed to an `Inbox` the app
      holds, drained at the start of each turn and again before the loop
      would end
- [x] Cancellation at any point with no inconsistent state. Nothing received
      is ever discarded: a partial reply is recorded as received and marked
      with why it stopped, by a person or by the system. Whether it is shown
      or sent back to the model is the app's decision
- [x] Zero dependencies beyond the standard library and Foundation

## Runtime

- [x] `Run`: swaco's standard unit of work; an `Agent` loop with every event
      recorded to the named store as it happens. Instructions, input, tools
      and model in; events and a final result out. Needs no session. Each
      event is recorded before it reaches the app, so the app never acts on
      an event the log is missing
- [x] `Session`: swaco's standard grouping of runs into a persistent
      history. Optional; apps with no history never touch it
- [x] Agent configuration decoupled from history: one session can be
      continued by differently configured agents, one configuration can
      serve many sessions
- [x] Session state machine: idle, running, awaiting a result, interrupted,
      failed. Awaiting a result covers every tool that registered a later
      result, a person's answer among them. State is read off the log rather
      than kept beside it, so the two can never disagree
- [x] Intake extension: the runtime's implementation of the arrival hook.
      The app supplies a mapping from source and session state to inject,
      queue or leave; left events start a new run. An app that does not list
      the extension starts a new run for every event that arrives during
      another
- [~] Execution context exposed to extensions: foreground, background,
      app extension process, remaining time, whether a person is present.
      The type is declared and reaches every hook; what fills it in from the
      system is the runtime's and is not written yet
- [x] A loop can stop after one turn and hand the rest to a later process;
      the handover survives the process boundary. A handover is its own
      verdict and its own event, told apart from an ending and from a
      refusal, and a handed-over run is the one state that means resume me.
      The rule is the app's: after a turn, or when the process is nearly out
      of time
- [x] Session registry and lookup, through the store rather than a second
      list to keep in step
- [x] Concurrency limit across all runs, with or without
      sessions. One run at a time per log, always, which is what keeps two
      loops from writing a history in an order neither chose. Across
      unrelated runs the app says the number and there is no default. A run
      waiting on a person holds no place, because waiting is not working and
      a limit that counted it would deadlock an app that asked two questions
      at once
- [x] Recovery on relaunch according to last persisted state: the log is
      read, every call left without a result is handed back to its tool to
      resume, and the loop continues from where the events stop. Checked
      across two stores over one directory, with a tool that remembers
      nothing
- [ ] Sub-agent as a tool (longer term)

## Storage

The core fixes what must be stored and with what guarantees; the app decides
where. No store is chosen by default: an app that uses sessions or referenced
content names one.

- [x] Conformance test suites that any `EventStore` or `ContentStore`
      implementation runs, in `SwacoTesting`. Our own stores run them, so a
      wrong contract is wrong for everyone at once
- [x] Reference implementations in the runtime: in-memory, and a plain file
      store that can live in an App Group container so an app extension and
      the main app share it. The file store is one JSON object per line,
      flushed before append returns
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

- [x] HTTP and server-sent events over `URLSession`, with cancellation.
      Lines are split from the bytes, not through `AsyncLineSequence`, which
      drops the blank line that separates one event from the next
- [x] Connection configuration per provider: endpoint (vendor default,
      overridable), an `Authenticator`, and the headers an endpoint of its
      own requires
- [~] `Authenticator` protocol: attach authentication to a request; refresh
      when the vendor signals it has expired. Implementations: static API
      key in the vendor's header, static bearer token, OAuth token pair with
      refresh, app-defined closure for an app's own backend. None is the
      default; the app names one. Done except OAuth. The shipped ones are
      static members of one `Authentication` value so a call site names one
      with a leading dot; the protocol stays the door, and
      `Authentication.custom` carries a third party's own through it
- [ ] `TokenStore` protocol for OAuth tokens; Keychain-backed reference
      implementation. Vendor-specific authorisation flows, which need a web
      view and vendor client ids, are companions
- [x] All configuration is passed explicitly in code. No configuration
      files; an environment variable is read only where an authenticator
      is asked to
- [~] Assembly of streamed tool-call arguments from partial fragments.
      The Responses protocol also delivers them whole when the item is done,
      which is what we read; assembly matters for the protocols that do not
- [~] Lossless conversion of messages, tool definitions and tool results
      between swaco's vocabulary and vendor shapes, ids preserved. Done for
      the Responses protocol, including a tool's JSON Schema reaching the
      vendor as JSON rather than as a string
- [x] Normalisation of stop reasons, usage and errors into swaco's types.
      Usage is what the vendor counted, carried and not interpreted: swaco
      does not price it, add it up or decide when there has been too much
- [~] Generic implementation of the OpenAI-compatible protocol, configured
      per vendor rather than re-implemented. The Responses protocol is
      implemented; chat completions is not
- [x] Model catalogue: identifier, provider, declared capabilities. A
      convenience and never an authority: vendors change weekly, and an app
      that describes its own model loses nothing
- [~] Recorded request and response fixtures for every provider we ship;
      the conformance suite that runs them lives in `SwacoTesting`. One
      recorded exchange exists; the suite is still tests in the AI layer

## Providers

Each is a thin module over `SwacoAI`.

- [ ] Anthropic (streaming, tool use, provider-executed web search)
- [~] OpenAI, including OpenAI-compatible endpoints. Any endpoint that
      speaks the Responses protocol is reached by naming a connection
- [x] Apple Foundation Models (on-device). It runs tools itself rather than
      handing calls back, so it declares no tool support and a request with
      tools is recorded as a mismatch
- [ ] Gemini (later)
- [x] Replayable mock provider for tests

## Interaction toolset (shipped, optional)

Tools through which the agent reaches the person. Swaco owns the mechanics
(the model sees the tool, a typed request appears in the event stream, the
loop suspends, the app answers, the loop continues, the suspension survives
relaunch). The app owns the presentation.

- [x] `ask`: put a question to the person, free-form or with options
- [x] `confirm`: have the person approve or refuse an action; also the shape
      used for requesting system authorisation
- [~] `report`: tell the person about progress or an intermediate result
      without waiting and without ending the reply; payload may include
      media. Text now; media when content parts carry references
- [x] `ask` and `confirm` suspend the same way whether or not a person is
      present; the app decides how to bring the person back. Both are
      re-armed against the desk the relaunched app holds, so a question put
      before the process died is waiting when it comes back
- [ ] `schedule`: let the agent arrange a future wake-up that returns as an
      inbound event; the app supplies the mechanism (longer term)

## Extensions (shipped, optional)

Only what nearly every app needs and no product would answer differently.

- [x] Environment context: time, time zone, locale, device, as instructions
      ahead of the first turn
- [x] Tool approval: route chosen tool calls through `confirm`. Which calls
      are chosen is the app's rule over the facts swaco declares, a tool's
      access and an event's source; with no rule, nothing is held. The
      extension holds the call and asks however the app says; it does not
      import the interaction toolset, so routing through `confirm` is the
      app's line of code and not swaco's decision
- [x] Retry with backoff for transient network errors, and for the commonest
      transient failure of all: a vendor asking us to wait. Whether a failure
      may pass is a fact the failing side declares through `TransientFailure`
      in the core, so the extension reads it without knowing any vendor, and
      a vendor's own number beats our guess

## Extensions (templates)

Strategies an app may want and would answer in its own way. Each is a
complete, compiling example under `Examples/`, built in CI, copied into the
app and owned by it from then on. Not shipped, not versioned.

- [x] Progressive tool disclosure: expose few tools plus a discovery tool
- [x] Budget: stop a loop after a chosen number of turns, tokens or
      seconds. Turns and seconds; also one that spends what the process has
      left, which is the honest budget in an app extension. Tokens wait on
      usage being carried
- [x] Context compaction. It rewrites what is sent and leaves the log
      alone, so what happened is still what happened

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

- [~] The event log format is public API, on the same terms as the Swift
      API: documented, versioned, evolved by addition only. A newer swaco
      replays logs written by an older one, and unknown event types are
      preserved, never dropped. A run is reproduced by replaying its log
      through the mock provider; a bug report is a log. The format has
      stable names and keeps the event types it does not know, checked by
      the store contract; replaying a log through the mock provider is next
- [x] Recording: run once against a real provider, keep the exchange as a
      fixture, replay it thereafter. Development, previews and tests need no
      key and no network. One JSON object per line, plain enough to trim by
      hand, and an attempt a vendor turned away leaves no empty turn. The
      mock and the recording are their own module, without the test
      framework, so a preview and an app can use them
- [x] `os.Logger` by subsystem and signposts per turn and tool call, so a
      run is visible in Instruments. Structure is logged, content is not:
      an event can say its kind, and a kind never carries what was said.
      The signposts are an extension, written through the same doors as any
      other, because the moments worth measuring are the moments the loop
      already offers
- [x] Privacy manifest shipped with the package: no tracking, no collection,
      no required-reason APIs. One with each library target
- [~] Each module states its deployment requirements: entitlements, App
      Group, Info.plist usage strings. A debug-build check fails at launch,
      with a clear message, when a linked module's requirements are missing.
      The App Group is stated and checked, and a store in one names the
      failure rather than letting a file error surface later. The check is a
      call the app makes, because explicit beats magic. Usage strings arrive
      with the toolsets that need them
- [x] Providers expose availability: not on this device, model downloading,
      ready. Apps decide before the first request, not after the first
      failure
- [x] No initialisation step, no account, no configuration file. The core
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

- [x] The canonical first program: `import Swaco`, one provider, one tool,
      one `Agent`, one `for await` over its events, in twenty lines or fewer
      including the tool. No runtime, no store. Protocols bend to keep it
      so; the example does not grow. Twenty lines, and it talks to a real
      model, not a mock

## Spike before design

- [x] Can the event-pair loop, with a main-actor tool, a deferred result
      and external cancellation, compile under Swift 6 strict concurrency
      with no unchecked escapes? Yes. `Tool.execute` returns a result or
      `.deferred`; a deferred tool later calls the `ResultDelivery` it was
      handed; an actor holds the waits so delivery, awaiting and
      cancellation cannot race. A `@MainActor` class satisfies the async
      requirements and the loop hops implicitly. Cancelling the consuming
      task is recorded as the system; `AgentRun.cancel()` as a person

## Project

- [~] Swift Package with independently linkable modules; the core works
      when every other module is absent. Four modules build alone for the
      simulator
- [x] iOS 26 minimum; macOS 26 compiles but is not yet supported
- [~] Swift 6 strict concurrency; all public types `Sendable` and
      serialisable
- [ ] Every public symbol documented, Swift naming conventions
- [~] Swift Testing suite that never touches the network
- [x] CI on GitHub Actions: every module linked on its own, the suite run
      on macOS and the simulator with warnings as errors, the examples
      built, and two acceptance checks that a person would otherwise have
      to remember: the first program stays at twenty lines, and no test
      carries a credential
- [ ] Breaking changes allowed and recorded before 1.0; semantic versioning
      after
- [x] A sample app demonstrating one-step adoption: a chatbot under
      `Examples/ChatApp`, four things to adopt swaco (a store, a desk, an
      agent, a session), and it restores a question a previous process left
      unanswered
- [x] Templates: a minimal, complete, compiling example each of an app tool,
      a toolset and an extension, built in CI so they never drift from the
      API. Two tools, because the shape that matters most is the one whose
      result comes later, in a process that did not ask for it
