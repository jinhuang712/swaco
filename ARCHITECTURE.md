# Architecture

How swaco is divided into modules, what each is responsible for, and the rules
that hold between them. This document follows from the [goals](GOALS.md) and
their boundary; the [feature list](FEATURES.md) says what each module will
contain.

## Layers

```
┌──────────────────────────────────────────────────────────────────┐
│ App                                                              │  the product
├──────────────────────────────────────────────────────────────────┤
│ Satellites            separate packages under our name           │
│ swaco-kits · swaco-media · swaco-stores · swaco-extras           │
├──────────────────────────────────────────────────────────────────┤
│ SwacoRuntime          Run · Session · intake policy              │  working
│                       stores: protocols and references           │  correctly
│                       recovery · concurrency · execution context │  in an app
├───────────────────────────────┬──────────────────────────────────┤
│ SwacoAnthropic                │ SwacoInteraction                 │  optional,
│ SwacoOpenAI                   │   ask · confirm · report         │  peers
│ SwacoFoundationModels         │ SwacoExtensions                  │
│   (built on SwacoAI)          │   environment · approval · retry │
├───────────────────────────────┤                                  │
│ SwacoAI                       │                                  │
│   shared provider machinery   │                                  │
├───────────────────────────────┴──────────────────────────────────┤
│ Swaco                 vocabulary · Provider protocol · loop      │  mechanics
│                       default event rendering                    │
├──────────────────────────────────────────────────────────────────┤
│ SwacoTesting          mock provider · conformance suites         │  cross-cutting
└──────────────────────────────────────────────────────────────────┘
```

Dependencies point downward only. Nothing below knows what is above it.

## Modules

### Swaco

The core. Depends on the standard library and Foundation, nothing else.

Holds the vocabulary as types: event, source, content, tool, toolset,
extension, provider, model. Holds the loop: context in, events out, continue
while the model asks for tools. Holds the default rendering of inbound events
into model-readable content, as one implementation of a replaceable protocol.

Groups nothing, stores nothing, limits nothing, knows no platform, opens no
network connection. An app that links only this module and one provider can
run an agent.

### SwacoAI

Machinery shared by providers, done once. Depends on Swaco only and knows no
vendor.

HTTP and server-sent events over `URLSession`; assembly of streamed tool-call
arguments; lossless conversion between swaco's vocabulary and vendor shapes;
normalisation of stop reasons, usage and errors; a generic implementation of
the OpenAI-compatible protocol; the model catalogue; recorded fixtures and the
provider conformance suite.

A third party writing a provider may build on it or implement the core
protocol directly. Our own providers always build on it.

### Providers

`SwacoAnthropic`, `SwacoOpenAI`, `SwacoFoundationModels`. Each a thin module
over SwacoAI translating one vendor's API. Each declares what its models can
do; the loop's response to a missing capability is fixed in the core, not in
the provider. No provider is favoured; on-device models are one among others.

### SwacoInteraction

The tools through which the agent reaches a person: `ask`, `confirm`,
`report`. Depends on Swaco only. Owns the mechanics: the model sees the tool,
a typed request appears in the event stream, the loop waits for the result
event, the wait survives relaunch. The app owns the presentation.

### SwacoExtensions

The three extensions nearly every app needs and no product would answer
differently: environment context, tool approval (the carrier of the safety
floor), retry. Depends on Swaco only.

### SwacoRuntime

What an agent needs to work correctly inside a real app. Depends on Swaco
only; never on a provider, an extension or a toolset.

`Run` as the unit of work and `Session` as the optional grouping of runs into
history. The event intake policy the app declares. The `EventStore`,
`ContentStore` and `CredentialProvider` protocols with their contracts, and
the in-memory and plain-file reference implementations. Recovery from the
last persisted event. Concurrency across runs. The execution context exposed
to extensions: foreground, background, app extension process, remaining time,
whether a person is present.

### SwacoTesting

Public, so satellites and third parties use it. The replayable mock provider.
The conformance suites for `EventStore`, `ContentStore` and providers. The
crash-at-every-event replay harness.

### Satellites

Separate repositories under our name, depending on swaco's public products
through the same protocols any third party uses. Platform toolsets
(`swaco-kits`), media normalisation (`swaco-media`), SQLite, SwiftData and
CloudKit stores (`swaco-stores`), product-strategy extensions such as
disclosure, budget and compaction (`swaco-extras`). Each has its own version
and pace. None widens what swaco promises.

## Rules

1. **Dependencies point down.** Swaco depends on nothing. SwacoAI,
   SwacoInteraction, SwacoExtensions and SwacoRuntime depend on Swaco only.
   Providers depend on SwacoAI. SwacoTesting depends on Swaco and
   SwacoRuntime. Nothing depends on a provider, an extension or a toolset.
2. **Peers do not know each other.** A provider does not import an
   extension; an extension does not import the runtime; the runtime does not
   import a provider. Composition happens in the app.
3. **One door.** Our own toolsets, extensions and providers use only public
   protocols. If writing one of them needs a private path, the core is
   deficient and is fixed; the path is not opened.
4. **The core has no network, no storage and no platform.** Anything that
   touches `URLSession` is SwacoAI or above. Anything that touches disk is
   SwacoRuntime or a store. Anything that touches an Apple framework beyond
   Foundation is a provider or a satellite.
5. **Every module is independently linkable.** The core works with every
   other module absent. The canonical first program imports the core and one
   provider.
6. **Protocols evolve by addition.** New hooks, new event subtypes and new
   capabilities arrive with defaults; existing conformances keep compiling
   and existing event logs keep replaying.

## Why this shape

Compared with pi, which has an AI layer, an agent core and a product: swaco
keeps the AI layer and the core, adds a runtime because apps are suspended,
killed and relaunched, and has no product layer by design. The loop lives
with the vocabulary rather than in its own module because neither means
anything without the other. The default event rendering lives in the core
because it is the step the loop takes to turn an event into model input; its
replaceability comes from a protocol, not a module boundary.

## Open

- The core module is named `Swaco` so that `import Swaco` is the first line
  of the first program. Rename to `SwacoCore` only if the package and module
  sharing a name causes trouble in practice.
