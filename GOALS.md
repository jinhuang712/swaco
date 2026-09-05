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
8. **Never let an agent run away with the device.** Every run is bounded by
   default.
9. **Bring the platform's own capabilities to the agent.** What the system
   already knows how to do should be easy to hand to the agent, in pieces the
   app chooses.
10. **Assume nothing about the shape of the app.** A set of one-shot prompts,
    a single timeline served by many agents, a chat with long histories, or
    something not yet imagined: all are equally natural.
11. **Ask nothing of the app's own choices.** No dependencies, no imposed
    storage, interface or architecture.

## Longer term

- Support for iPadOS and macOS.
- Agents that delegate to other agents.
- Capabilities that only make sense on a desktop.
- Reaching the web from the agent.

## Non-goals

Written down so they are not eroded one convenience at a time.

- We do not build user interface.
- We do not assume the app is a chat.
- We do not ship capabilities inside the core.
- We do not build memory, retrieval, or knowledge management.
- We do not build orchestration of many agents.
- We do not manage prompts.
- We do not account for cost or measure quality.
- We do not run servers or hold credentials on anyone's behalf.
- We do not target platforms other than Apple's.
- We do not support system versions before the current one.
- We do not build a command-line product.
- We do not build privacy machinery beyond making data flows visible.

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
