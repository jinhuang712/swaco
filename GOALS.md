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
3. **Work offline and without accounts.** An app should be able to be agentic
   using only what the device already has.
4. **Let apps shape behaviour without touching swaco.** Whatever an app needs
   the agent to do differently, it should be able to arrange from the outside.
5. **Be correct in the life an app actually has.** Being interrupted,
   suspended, killed and relaunched is normal, and nothing should be lost or
   left unexplained because of it.
6. **Let many agents work at once, safely.** An app may run several agents
   simultaneously, and it should stay in control of them.
7. **Make everything observable and reproducible.** Whatever happened, the app
   can see it, store it, and rebuild any view of it later.
8. **Bring the platform's own capabilities to the agent.** What the system
   already knows how to do should be easy to hand to the agent, in pieces the
   app chooses.
9. **Let the agent reach the person, on the person's terms.** On a phone the
   agent must be able to ask, confirm and report. Swaco makes those exchanges
   work correctly; the app decides how they look.
10. **Assume nothing about the shape of the app, or about who wakes the
    agent.** A set of one-shot prompts, a single timeline served by many
    agents, a chat with long histories, or something not yet imagined: all
    are equally natural. So is an agent woken by a shortcut, a notification,
    another app, a place, a time or a sensor, with no person watching.
11. **Ask nothing of the app's own choices.** No dependencies, no imposed
    storage, interface or architecture.

## Boundary

Swaco is responsible for making an agent work correctly inside an iOS app.
The app is responsible for deciding what that agent is as a product.

Within swaco there are two circles:

- **The core** holds only mechanics: the context sent to a model, the events
  that come back, the loop that continues while the model asks for tools,
  tools and the sets they come in, and the points where behaviour can be
  shaped. It groups nothing, stores nothing, limits nothing and knows no
  platform.
- **Swaco as a whole** adds everything an agent needs to work correctly in a
  real app and that every app would otherwise rebuild: standard ways of
  grouping work and keeping its history, state and recovery, concurrency
  control, access to models, persistence, shipped extensions and platform
  capabilities. These are optional modules, but they are ours to design and
  keep coherent.

Around swaco sit **satellites**: packages we write under our own name that
depend on swaco but do not live in it. Wrappers around the platform's
frameworks are the first of these. A satellite uses exactly the same doors as
any third party, so it doubles as proof that the doors are enough; it has its
own version and its own pace; and it never widens what swaco itself promises.

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
- We do not ship capabilities inside the core.
- We do not build memory, retrieval, or knowledge management.
- We do not build orchestration of many agents.
- We do not manage prompts.
- We do not curate a library, catalogue or marketplace of capabilities.
  What ships inside swaco stays deliberately few; our own satellites are few
  and named; everything else belongs to independent packages, which we make
  easy to write.
- We do not account for cost or measure quality.
- We do not run servers or hold credentials on anyone's behalf.
- We do not target platforms other than Apple's.
- We do not support system versions before the current one.
- We do not build a command-line product.
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
