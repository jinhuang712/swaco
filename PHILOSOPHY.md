# Swaco Design Philosophy

Swaco is a small, extensible agent core written in Swift. This document is the
set of principles every design decision in the project is measured against.
When a proposal conflicts with these principles, the principles win; when the
principles themselves need to change, this document changes first.

## 1. The core is one loop

An agent is a loop: send messages to a model, receive a reply, execute the
tool calls it asks for, feed the results back, repeat until the model stops.
That loop *is* the core. Everything else is layered on top of it or plugged
into it.

The core therefore has no built-in tools, no memory, no retrieval, no planner,
no MCP client, no persistence, and no UI. These are not missing features. They
are deliberately kept outside so that the core stays small enough to
understand in one sitting and stable enough to never break the apps built on
it.

## 2. Less is more

Every addition must justify itself against the cost of existing at all. The
default answer to "should the core also do X?" is no. If X can be built as an
extension, a tool, or a separate module, it is built there.

We measure success by how little an app has to learn and how few lines it has
to write, not by how many capabilities the framework lists.

## 3. Swift native, not Swift-flavoured

Swaco uses the language and the platform instead of re-implementing what they
already provide.

- Structured concurrency replaces callbacks, abort controllers, and manual
  cancellation. An agent run is a `Task`; cancelling the task cancels
  everything beneath it.
- `actor` isolation replaces locks. `Sendable` is enforced everywhere.
- Enums with associated values model messages, content parts, and events, so
  an unhandled case is a compile error, not a runtime surprise.
- `Codable` handles every wire format. `AsyncSequence` carries every stream.
- `URLSession` is the only network layer. There are no third-party
  dependencies.
- Apple platform capabilities are integrated as providers and tools (on-device
  models, Keychain, EventKit, and so on), never baked into the core.

The minimum deployment target is iOS 26 and macOS 26. We do not carry
compatibility code for older systems.

## 4. Providers translate; they do not decide

Swaco defines one canonical vocabulary for talking to models: messages,
content parts, tool definitions, and a single set of streaming events. A
provider's only job is to translate that vocabulary to and from one vendor's
API. The agent loop never sees a vendor-specific type.

Models are data, not code. Switching a model is switching a record. Adding a
vendor is adding one translation module and never touches the core.

## 5. Behaviour changes through extensions

The agent loop exposes a small, fixed set of hook points: before a run, before
each model request, before and after each tool call, on every event, and after
a run. An extension is a value that implements some of those hooks.

Permission prompts, context compaction, memory, tracing, retrieval, and tool
injection are all extensions. The loop does not know they exist. Extensions
compose; the core does not grow.

## 6. Apps are the product; Swaco is the capability

Swaco ships no UI and makes no product decisions. It emits a complete,
serialisable stream of events and exposes explicit session state, and stops
there. What a conversation looks like, how approvals are presented, and what
"agentic" means for a given app are decided by the app.

This is what makes the framework worth having: any iOS or macOS app can adopt
it without adopting anyone else's opinion about their product.

## 7. Designed for how apps actually run

Swaco is not a desktop process that runs until it finishes. It lives inside
apps that are suspended, backgrounded, killed, and relaunched.

- Sessions are the persistent entity; agents are disposable executors created
  to advance a session.
- Every event is persisted as it happens, as an append-only log, so a run
  interrupted at any point can be inspected and resumed.
- Recovery is simple and predictable: a half-streamed reply is discarded and
  marked interrupted; a completed reply with pending tool calls resumes.
- Multiple sessions coexist under a thin runtime that owns scheduling,
  concurrency limits, and state. Multi-agent is composition (a sub-agent is a
  tool), not orchestration machinery.
- Tools are platform-specific packs, never assumptions. A shell exists on
  macOS and does not exist on iOS; the core is indifferent to both.

## 8. Adoption in three steps

The measure of the public API is that an app becomes agentic by doing three
things: register a provider, define a few tools, open a session. Sensible
defaults cover everything else. Anything that makes those three steps longer
needs a very good reason.

## 9. Boring, explicit, and documented

Public API follows Swift conventions rather than borrowing names from other
ecosystems. Every public symbol is documented. Behaviour is explicit over
clever, and predictable over flexible. Tests use a replayable mock provider so
the loop is verified without a network.

---

These principles are deliberately few. If a decision cannot be traced back to
one of them, that is a signal to reconsider the decision, or to revisit this
document.
