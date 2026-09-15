# Goals

The [philosophy](PHILOSOPHY.md) says what we believe. This document says what
we are trying to achieve, what we are choosing not to achieve, and which way we
lean when goals collide. What we will actually build to get there is tracked
separately in the [feature list](FEATURES.md).

## Goals

1. **Remain genuinely small.** A developer reads the complete core and
   understands the entire execution model. Additions never make this less true.
2. **One agent core across Apple platforms.** The same `Agent`, `Provider`,
   `Tool`, `Content`, and event vocabulary work unchanged on macOS, iPadOS,
   and iOS. Platform differences belong outside the loop.
3. **Be easy to embed.** Adding swaco never requires restructuring the app.
   The host provides model, context, and capabilities, and receives agent
   events. That stays the essential integration.
4. **Make no assumptions about the product.** Conversational, document-oriented,
   creative, ambient, one-shot, or continuously interactive: all are equally
   natural. No one category distorts the vocabulary.
5. **Expose application state without owning it.** The host turns live state
   into context and capabilities efficiently. Swaco never copies that state
   into a swaco-owned model.
6. **Support multimodal agents naturally.** Text, image, audio, and video are
   legitimate content, not later exceptions. Large content stays referenceable
   rather than copied through every message.
7. **Be indifferent to the model.** An app changes which model it talks to,
   hosted or on-device, without changing anything else.
8. **Make interactive steering first-class.** An interactive agent is easy to
   interrupt, redirect, and cancel. This never depends on whether the host is
   a chat interface.
9. **Make durability optional.** Persistent sessions and recovery after relaunch
   are available when required, without burdening agents that live comfortably
   in one process.
10. **Remain Swift-native.** The API feels like Swift, not a translated
    server framework or coding harness.

## Boundary

Swaco is responsible for making an agent work correctly inside a native Swift
app. The app is responsible for deciding what that agent is as a product.

Within swaco there are two circles:

- **The core** holds only mechanics: the context sent to a model, the events
  that come back, the loop that continues while the model asks for tools,
  tools and the sets they come in, and the points where behaviour can be
  shaped. It defines what a store must do without holding one, groups
  nothing, limits nothing and knows no platform.
- **Swaco as a whole** adds everything an agent needs to work correctly in a
  real app and that every app would otherwise rebuild: standard ways of
  grouping work and keeping its history, state and recovery, concurrency
  control, access to models, persistence, shipped extensions and platform
  capabilities. These are optional modules, but they are ours to design and
  keep coherent.

Some things are necessary for correctness yet their medium depends on the
product: where events are recorded, where content is kept, how requests are
authenticated and where tokens live. For these swaco fixes the contract and leaves the medium to the app: a
strict protocol, a conformance test suite any implementation must pass, one or
two reference implementations, and no default. The app names what it uses.

Alongside swaco sit **companions**: packages we write under our own name that
depend on swaco but do not live in it. A companion is a bridge and nothing
more: it connects something the platform already has, a framework or a
storage medium, to a protocol swaco already defines. Platform toolsets, media
handling and stores are the first of these. A companion uses exactly the same
doors as any third party, so it doubles as proof that the doors are enough;
it has its own version and its own pace; and it never widens what swaco
itself promises. When a companion cannot be written through the public doors,
the protocol has failed to express a fact about the platform, and the core is
fixed.

What is not a bridge is not a companion. Extensions that embody a strategy,
such as budgets, compaction or progressive disclosure, are shown as templates
in the examples: complete, compiling, built in CI, copied into an app and
owned by it from then on. We write them once to prove the doors are enough
and to spare the first adopter a blank page; we do not version or ship them.

Interaction patterns such as `ask`, `confirm`, and `report` are useful, but
they are not universal properties of an agent. They live as an optional
interaction package above the core, not at its centre.

The app owns the rest: the interface, which capabilities to expose, what to
allow, what to say to the model, and what to call things.

To place something, ask: without it, does the loop fail? Then it is core.
Without it, would agents misbehave in real apps or would every app rebuild
it? Then it is swaco. Does the answer depend on the product? Then it is the
app's.

## Longer term

- Agents that delegate to other agents.
- Capabilities that only make sense on a desktop.
- Reaching the web from the agent.

## Non-goals

Written down so they are not eroded one convenience at a time.

- We do not build user interface, pickers and import screens included.
- We do not assume the app is a chat, or any other single product shape.
- We do not favour any model or provider. On-device models are one provider
  among others.
- We do not ship capabilities inside the core.
- We do not build memory, retrieval, or knowledge management.
- We do not build orchestration of many agents, sub-agents, workflows, DAGs,
  or task planning.
- We do not manage prompts.
- We do not curate a library, catalogue or marketplace of capabilities,
  tools, plugins, or MCP servers. What ships inside swaco stays deliberately
  few; our own companions are few and named; everything else belongs to
  independent packages, which we make easy to write.
- We do not ship a shell, filesystem, browser automation, or sandbox.
- We do not account for cost or measure quality.
- We do not run servers or hold credentials on anyone's behalf.
- We do not target platforms other than Apple's.
- We do not support system versions before the current one.
- We do not build a command-line product.
- We do not build tooling for building, signing, distributing or onboarding
  an app.
- We do not build privacy machinery.
- We do not manage the application's own state.

## Trade-offs

- **Simple over complete.**
- **Explicit over magic.**
- **Stable over novel.**
- **Predictable over perfect.**
- **The adopter's convenience over ours.**
- **Refusal over compromise.**
- **Fewer, broader capabilities over many narrow ones.**

## How we get there

Swaco is developed by building real apps on it first. What gets built, and in
what order, is decided by what those apps need, not by what would look complete.

The first app is a simple chatbot: one conversation with one model, a few
tools, on an iPhone. It is chosen because it is the form most adopters start
from and the easiest to demonstrate, not because swaco assumes it. Two
consequences follow and are accepted:

- The parts of the runtime that a chat exercises come first: sessions,
  persistence, recovery after relaunch, `ask` and `confirm` while a person
  is present.
- The parts a chat does not exercise, an agent woken with nobody watching
  and a run that spans processes, are not driven by this app. They stay in
  the design and wait for the second app or a deliberate test harness. The
  first app must not be allowed to bend the vocabulary toward chat.

The second driver is difference itself: a long-lived macOS application, a
stateful iPadOS application that moves between foreground and suspended, and
a short-lived iOS application that exercises relaunch and recovery. The
surroundings differ significantly while the core remains unchanged. That is
the conformance test for the architecture above.

## Milestones

The goals above are where we are going. These are the next things that can
be declared done, in order, each with the test that decides it. When one is
met it is marked here and the next becomes the current one.

1. **The spike has an answer.** A package with the `SwacoCore` target alone
   compiles under Swift 6 strict concurrency with the event-pair loop, a
   main-actor tool, a deferred result and external cancellation, and no
   unchecked escape. The answer is "yes" or "no, and this is what changes
   in the design". Needs no Xcode and no simulator. *Met: yes; the shape
   is recorded in FEATURES under the spike.*
2. **The first program runs.** `import SwacoCore`, one provider, one tool, one
   `Agent`, one `for await`, in twenty lines or fewer, against a real model
   rather than a mock. Protocols bent to fit; the example did not grow.
   *Met on the command line: twenty lines, a hosted model reached through
   the Responses protocol, a tool called and answered, two turns. What
   remains is the same code running on a simulator, and on iOS a program is
   an app, so that is the third milestone.*
3. **The first app works.** The chatbot described above, on a phone,
   through one hosted provider and one on-device provider, with a session
   that survives relaunch and an `ask` that survives relaunch. Every module
   it links is independently linkable and the crash-at-every-event harness
   passes on its log. *Current, and met but for a device. The app restores
   a conversation and a question a previous process left unanswered and
   picks the loop back up; the harness passes; each of the nine modules
   builds alone for the simulator; both a hosted model and the on-device one
   are wired in and either can be chosen. Four tests drive the app by
   tapping, on a conversation it once had with a real model and kept: they
   kill the process while the agent is waiting on an answer, relaunch, find
   the question where the person left it, and answer it into the loop that
   asked a process ago. What remains is an iPhone in somebody's hand, for
   the one thing a simulator cannot do: be killed by memory pressure, and be
   woken with nobody watching.*
4. **The doors are proven.** One companion toolset and one template
   extension exist, written through public protocols only, with nothing
   added to the core to make them possible. *Met. Six templates live under
   `Examples/`: three strategies, and an app's own tool, deferred tool,
   toolset and extension. The first companion, `swaco-kits`, is a separate
   package beside this one, bringing EventKit as a toolset. Both were
   written through the same public protocols a third party has, and swaco
   needed nothing added for any of it, which is what they were written to
   find out. What the companion still wants is a repository of its own
   under our name, and publishing is a decision rather than a task.*
5. **The definitions are rewritten.** `README`, `ORIGIN`, `PHILOSOPHY`, and
   `GOALS` describe a minimal product-agnostic core, an optional runtime,
   and bridges above it. *Met in this change: the four documents are
   rewritten and land with the code.*
6. **The core is small again.** The audit ran against a macOS, an iPadOS,
   and an iOS host: the source vocabulary opened above the core, content
   went multimodal with declared modalities, tools are described by effect,
   vendor-executed tools are gone, and `SwacoEnvironment` holds where the
   agent lives. *Current. What remains is proving the same core under
   different surroundings: a long-lived macOS host, a suspendable iPadOS
   host, and a short-lived iOS host.*

Nothing after the sixth is planned until the sixth is met.

## What is waiting on somebody

Not blocked by design, and not forgotten: these need something no amount of
work here provides.

- **A device.** The last of the third milestone, and now the only part of it
  left. A simulator can be killed and is, in the tests that drive the app;
  what it cannot do is be killed by memory pressure or woken with nobody
  watching.
- **A repository for the first companion.** `swaco-kits` exists as a package
  beside this one and passes its own checks; what it does not have is a
  repository under our name, and publishing is a decision rather than a
  task.
- **Keys for the vendors we do not have.** Anthropic and Gemini are written
  down and unwritten. The recording tool means each needs one exchange with
  a real key, once, and never again.
