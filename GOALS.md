# Goals

The [philosophy](PHILOSOPHY.md) says what we believe. This document says what
we are trying to achieve, what we are choosing not to achieve, and which way we
lean when goals collide. What we will actually build to get there is tracked
separately in the [feature list](FEATURES.md).

## Goals

1. **Make any iOS app agentic in one step.** Adopting swaco should feel like
   adding a capability, not starting a project.
2. **Be indifferent to the model.** An app should be able to change which
   model it talks to, hosted or on-device, without changing anything else.
3. **Let apps shape behaviour without touching swaco.** Whatever an app needs
   the agent to do differently, it should be able to arrange from the outside.
4. **Be correct in the life an app actually has.** Being interrupted,
   suspended, killed and relaunched is normal, and nothing should be lost or
   left unexplained because of it.
5. **Let many agents work at once, safely.** An app may run several agents
   simultaneously, and it should stay in control of them.
6. **Make everything observable and reproducible.** Whatever happened, the app
   can see it, store it, and rebuild any view of it later.
7. **Bring the platform's own capabilities to the agent.** What the system
   already knows how to do should be easy to hand to the agent, in pieces the
   app chooses.
8. **Let the agent reach the person, on the person's terms.** On a phone the
   agent must be able to ask, confirm and report. Swaco makes those exchanges
   work correctly; the app decides how they look.
9. **Assume nothing about the shape of the app, or about who wakes the
    agent.** A set of one-shot prompts, a single timeline served by many
    agents, a chat with long histories, or something not yet imagined: all
    are equally natural. So is an agent woken by a shortcut, a notification,
    another app, a place, a time or a sensor, with no person watching.
10. **Ask nothing of the app's own choices.** No dependencies, no imposed
    storage, interface or architecture.

## Boundary

Swaco is responsible for making an agent work correctly inside an iOS app.
The app is responsible for deciding what that agent is as a product.

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

The app owns the rest: the interface, which capabilities to expose, what to
allow, what to say to the model, and what to call things.

To place something, ask: without it, does the loop fail? Then it is core.
Without it, would agents misbehave in real apps or would every app rebuild
it? Then it is swaco. Does the answer depend on the product? Then it is the
app's.

## Longer term

- Support for iPadOS and macOS.
- Agents that delegate to other agents.
- Capabilities that only make sense on a desktop.
- Reaching the web from the agent.

## Non-goals

Written down so they are not eroded one convenience at a time.

- We do not build user interface, pickers and import screens included.
- We do not assume the app is a chat.
- We do not favour any model or provider. On-device models are one provider
  among others.
- We do not ship capabilities inside the core.
- We do not build memory, retrieval, or knowledge management.
- We do not build orchestration of many agents.
- We do not manage prompts.
- We do not curate a library, catalogue or marketplace of capabilities.
  What ships inside swaco stays deliberately few; our own companions are few
  and named; everything else belongs to independent packages, which we make
  easy to write.
- We do not account for cost or measure quality.
- We do not run servers or hold credentials on anyone's behalf.
- We do not target platforms other than Apple's.
- We do not support system versions before the current one.
- We do not build a command-line product.
- We do not build tooling for building, signing, distributing or onboarding
  an app.
- We do not build privacy machinery.

## Trade-offs

- **Simple over complete.**
- **Explicit over magic.**
- **Stable over novel.**
- **Predictable over perfect.**
- **The adopter's convenience over ours.**
- **Refusal over compromise.**
- **Fewer, broader capabilities over many narrow ones.**

## How we get there

Swaco is developed by building a real app on it first. What gets built, and in
what order, is decided by what that app needs, not by what would look complete.

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

## Milestones

The goals above are where we are going. These are the next things that can
be declared done, in order, each with the test that decides it. When one is
met it is marked here and the next becomes the current one.

1. **The spike has an answer.** A package with the `Swaco` target alone
   compiles under Swift 6 strict concurrency with the event-pair loop, a
   main-actor tool, a deferred result and external cancellation, and no
   unchecked escape. The answer is "yes" or "no, and this is what changes
   in the design". Needs no Xcode and no simulator. *Met: yes; the shape
   is recorded in FEATURES under the spike.*
2. **The first program runs.** `import Swaco`, one provider, one tool, one
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
   are wired in and either can be chosen. What remains needs an iPhone in
   somebody's hand: a real relaunch after a real kill, and the two providers
   exercised by tapping rather than by test.*
4. **The doors are proven.** One companion toolset and one template
   extension exist, written through public protocols only, with nothing
   added to the core to make them possible. *Half met. Six templates exist
   under `Examples/`: three strategies, and an app's own tool, deferred
   tool, toolset and extension. Each is written through the same public
   protocols a third party has, each is built and checked in CI, and the
   core needed nothing added for any of them. The companion waits on a
   repository of its own, which is not ours to create.*

Nothing after the fourth is planned until the fourth is met.

## What is waiting on somebody

Not blocked by design, and not forgotten: these need something no amount of
work here provides.

- **A device.** The last of the third milestone. A simulator cannot be killed
  by memory pressure or woken with nobody watching.
- **A repository for the first companion.** Companions live under our name
  and outside swaco, so the first one begins with a repository, and that is
  a decision rather than a task.
- **Keys for the vendors we do not have.** Anthropic and Gemini are written
  down and unwritten. The recording tool means each needs one exchange with
  a real key, once, and never again.
