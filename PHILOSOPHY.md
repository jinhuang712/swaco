# Philosophy

This document sits above everything else in swaco. It is not a design, not a
roadmap, and not a list of features. It is the set of foundations we build on
and the standards we do not break. Code, architecture, and API may change;
these do not.

When a decision conflicts with this document, the decision is wrong.

## Less is more

We believe an agent does not need much to be useful. The value of swaco lies in
what it refuses to be as much as in what it is. Every addition must earn its
place, and the burden of proof is on the addition. The default answer to
"should swaco also do this?" is no.

We measure ourselves by how little there is to learn, not by how much there is
to offer.

## One core, many homes

There is no macOS agent, iPadOS agent, and iOS agent. There is one agent.
Different environments provide different surroundings: a macOS app may keep an
agent alive for hours, an iOS app may be suspended seconds later, an iPadOS app
may move between both. Those are runtime facts. They must not redefine the
agent itself.

## The core knows mechanics, not meaning

The core understands model requests, model responses, content, tool calls, tool
results, turns, cancellation, steering, and agent events. It does not
understand projects, documents, timelines, filesystems, repositories, tasks,
calendars, media libraries, games, editors, or workflows. Those are application
concepts. An application exposes whichever pieces of its world it wants the
agent to see.

## The application owns state

Swaco never becomes the application's source of truth. It neither mirrors nor
replaces the application's structured state. The application decides what
portion of that state becomes model context and what capabilities may change
it. Conversation history is one form of context, not more authoritative than
application state.

## Capability is injected, never assumed

Swaco ships no universal environment. There is no implicit shell, filesystem,
browser, MCP universe, database, repository, or search system. An agent acts
only through capabilities its host deliberately provides. A small application
may expose three tools, another thirty; neither pays architectural complexity
for capabilities it does not use.

## Any model, one voice

An agent should not care which model it speaks to. Swaco speaks in one
vocabulary, and the differences between models are absorbed at the edge, never
allowed to reach the centre.

## Native where native matters

Swaco belongs in Swift applications. It uses Swift concurrency, value semantics
where appropriate, actors and isolation, structured cancellation, and Foundation
types, and it reaches application lifecycles through optional layers. But native
implementation never leaks platform policy into the core. The core runs wherever
swaco is supported; platform behaviour sits above it.

## Composition over framework

Swaco is a library, not a harness. An application does not adopt a swaco
architecture, lifecycle, storage model, navigation, dependency injection, or
interface. It imports the pieces it needs. The dependency direction is always
app into swaco, never swaco into app.

## Observable, not event-sourced by decree

Everything the agent does is observable. Swaco emits a complete trace of its own
behaviour: turn started, content streamed, tool requested, tool completed, turn
ended, cancelled, failed. An application may persist that trace, replay it, or
ignore it. Swaco never requires the application's own world to be represented as
an event log.

## Explicit over magical

Swaco never secretly discovers tools, infers permissions, trims context,
compacts history, selects models, switches providers, retries expensive
operations, mutates application state, or creates sub-agents. Where the
application wants one of these, it opts in explicitly. Invisible autonomy makes
a small core impossible to reason about.

## Policy belongs above the core

Swaco owns facts; the app owns policy. Swaco declares up front whatever a
decision needs to know: whether a tool reads or writes, where an event came
from, what a model can take, how long a call has run. The app decides what to
allow, hold, retry, delay, or route elsewhere. Swaco holds no policy of its
own, not even a cautious one. Where the right answer depends on the product,
swaco asks for it explicitly rather than assuming one; where it does not, swaco
does not ask.

In one line: swaco is responsible for making an agent work correctly inside
an app; the app is responsible for deciding what that agent is as a product.

---

These principles are few on purpose. If a decision cannot be traced back to
one of them, reconsider the decision. If a principle needs to change, change
this document first, and only with great reluctance.
