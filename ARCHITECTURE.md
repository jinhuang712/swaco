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
│ Companions            separate packages under our name           │
│ swaco-kits · swaco-media · swaco-stores                          │
├──────────────────────────────────────────────────────────────────┤
│ SwacoRuntime          Run · Session · intake extension           │  working
│                       stores: reference implementations          │  correctly
│                       recovery · concurrency · execution context │  in an app
├───────────────────────────────┬──────────────────────────────────┤
│ SwacoAI  (the AI layer)       │ SwacoInteraction                 │  optional,
│   SwacoAnthropic              │   ask · confirm · report         │  peers
│   SwacoOpenAI                 │ SwacoExtensions                  │
│   SwacoFoundationModels       │   environment · approval · retry │
│   ── built on ──              │                                  │
│   SwacoAI shared machinery    │                                  │
├───────────────────────────────┴──────────────────────────────────┤
│ Swaco                 vocabulary · Agent loop · protocols for    │  mechanics
│                       provider, tool, store · default rendering  │
├──────────────────────────────────────────────────────────────────┤
│ SwacoTesting          mock provider · conformance suites         │  cross-cutting
└──────────────────────────────────────────────────────────────────┘
```

Dependencies point downward only. Nothing below knows what is above it.

## Modules

### Swaco

The core. Depends on the standard library and Foundation, nothing else.

Holds the vocabulary as types: event, source, content, tool, toolset,
extension, provider, model, store. Holds the loop as `Agent`: context in,
events out, continue while the model asks for tools, callable on its own.
Holds the default rendering of inbound events into model-readable content, as
one implementation of a replaceable protocol. Holds the `EventStore` and
`ContentStore` protocols and their contracts, so that a content part can
point at bytes and a provider can fetch them, without holding a store of
either.

Groups nothing, keeps nothing, limits nothing, knows no platform, opens no
network connection. An app that links only this module and one provider can
run an agent.

### SwacoAI

The AI layer: one target of shared machinery and one target per vendor, all
under one directory. Providers are separate targets only so that an app links
the vendors it uses and nothing else; a provider that imports an Apple
framework must not be carried by an app that never calls it.

The shared machinery depends on Swaco only and knows no vendor.

HTTP and server-sent events over `URLSession`; connection configuration per
provider, an endpoint and an `Authenticator` (API key, bearer token, OAuth
with refresh, or the app's own scheme for its backend), with token storage
behind a protocol; assembly of streamed tool-call arguments; lossless conversion between swaco's vocabulary and vendor shapes;
normalisation of stop reasons, usage and errors; a generic implementation of
the OpenAI-compatible protocol; the model catalogue; the recorded fixtures
our providers are tested against.

A third party writing a provider may build on it or implement the core
protocol directly. Our own providers always build on it.

### Providers

`SwacoAnthropic`, `SwacoOpenAI`, `SwacoFoundationModels`, part of the AI
layer. Each a thin target over the shared machinery, translating one vendor's
API and declaring what its models can take. When content reaches a model that
has not declared the ability to take it, the mismatch is recorded as an event
and nothing else happens: the loop does not refuse, the provider does not
trim, the app decides. No provider is favoured; on-device models are one
among others.

### SwacoInteraction

The tools through which the agent reaches a person: `ask`, `confirm`,
`report`. Depends on Swaco only. Owns the mechanics: the model sees the tool,
a typed request appears in the event stream, the loop waits for the result
event, the wait survives relaunch. The app owns the presentation.

### SwacoExtensions

The three extensions nearly every app needs and no product would answer
differently: environment context, tool approval, retry. Approval holds the
calls the app's rule selects and nothing more; the facts it selects over, a
tool's access and an event's source, are declared in the core. Depends on
Swaco only.

### SwacoRuntime

What an agent needs to work correctly inside a real app. Depends on Swaco
only; never on a provider, an extension or a toolset.

`Run` as the unit of work, an `Agent` loop with its events recorded and
recoverable, and `Session` as the optional grouping of runs into history. The
standard intake extension. The in-memory and plain-file reference
implementations of the core's store protocols. Recovery from the last
persisted event, including handing every tool call that was left waiting back
to its tool to resume. Concurrency across runs. The execution context exposed
to extensions: foreground, background, app extension process, remaining time,
whether a person is present.

### SwacoTesting

Public, so companions and third parties use it. The replayable mock provider.
The conformance suites for `EventStore`, `ContentStore` and providers. The
crash-at-every-event replay harness.

### Companions

Separate repositories under our name, depending on swaco's public products
through the same protocols any third party uses. Each is a bridge from
something the platform has to a protocol swaco defines: platform toolsets
(`swaco-kits`), media normalisation (`swaco-media`), SQLite, SwiftData and
CloudKit stores (`swaco-stores`). Each has its own version and pace. None
widens what swaco promises. Extensions that carry a strategy rather than a
bridge are templates under `Examples/`, not companions.

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
4. **The core has no network, no storage and no platform.** It defines the
   protocols for all three and holds an implementation of none. Anything that
   touches `URLSession` is SwacoAI or above. Anything that touches disk is
   SwacoRuntime or a store. Anything that touches an Apple framework beyond
   Foundation is a provider or a companion.
5. **Every module is independently linkable.** The core works with every
   other module absent. The canonical first program imports the core and one
   provider.
6. **Protocols evolve by addition.** New hooks, new event subtypes and new
   capabilities arrive with defaults; existing conformances keep compiling
   and existing event logs keep replaying.

## File tree

One Swift Package, one target per module. Inside a module, directories follow
the vocabulary; file names are left to the code and will change.

```
swaco/
├── Package.swift
├── README.md · ORIGIN.md · PHILOSOPHY.md · GOALS.md · ARCHITECTURE.md · FEATURES.md
│
├── Sources/
│   ├── Swaco/                   core
│   │   ├── Events/              event, source, execution context, rendering
│   │   ├── Content/             content parts, references, message projection
│   │   ├── Tools/               tool, toolset, tool call, schema
│   │   ├── Providers/           provider protocol, model, capabilities, stream events
│   │   ├── Extensions/          extension protocol, decisions
│   │   ├── Stores/              event store and content store protocols, contracts
│   │   └── Loop/                agent, loop, cancellation
│   │
│   ├── SwacoAI/                 the AI layer: shared machinery plus one target per vendor
│   │   ├── Core/                target SwacoAI
│   │   │   ├── HTTP/            client, connection, server-sent events
│   │   │   ├── Authentication/  authenticator and implementations, token store
│   │   │   ├── Streaming/       tool-call assembly
│   │   │   ├── Conversion/      vendor shapes ↔ swaco vocabulary, normalisation
│   │   │   ├── OpenAICompatible/ the generic protocol implementation
│   │   │   └── Catalogue/       models
│   │   ├── Anthropic/           target SwacoAnthropic
│   │   ├── OpenAI/              target SwacoOpenAI
│   │   └── FoundationModels/    target SwacoFoundationModels
│   │
│   ├── SwacoInteraction/        ask, confirm, report
│   ├── SwacoExtensions/         environment, approval, retry
│   │
│   ├── SwacoRuntime/
│   │   ├── Runs/                run, session, state, intake extension
│   │   ├── Scheduling/          concurrency, execution context, handover
│   │   ├── Recovery/            replay from the last persisted event
│   │   └── Stores/              reference implementations
│   │
│   └── SwacoTesting/            mock provider, conformance suites, crash replay
│
├── Tests/                       one directory per module, plus recorded fixtures
├── Examples/                    first program, templates, sample app
└── .github/                     CI
```

Companions live in their own repositories with the same conventions.

## Why this shape

The layers come from the [origin](ORIGIN.md): an AI layer and an agent core
kept apart as pi keeps them, a runtime added because apps on this platform
are suspended, killed and relaunched, and no product layer because the
product is the app's. Two smaller choices are ours alone. The loop lives with
the vocabulary rather than in its own module because neither means anything
without the other. The default event rendering lives in the core because it
is the step the loop takes to turn an event into model input; its
replaceability comes from a protocol, not a module boundary.

## Open

- The core module is named `Swaco` so that `import Swaco` is the first line
  of the first program. Rename to `SwacoCore` only if the package and module
  sharing a name causes trouble in practice.
