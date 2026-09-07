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

## The core is atomic and cohesive

At the heart of swaco is one thing: the ability for an agent to think, act, and
continue. That heart is small enough to be understood completely and stable
enough to be trusted completely.

Nothing that is not essential to that ability lives in the core. Everything
else lives around it and can be added, replaced, or removed without touching
it.

## Behaviour is shaped from the outside

The core does not grow to accommodate new needs. Needs are met by extending it
from the outside, through a small and deliberate set of points where its
behaviour can be shaped. Capability accumulates around the core; the core
itself stays still.

## Any model, one voice

An agent should not care which model it speaks to. Swaco speaks in one
vocabulary, and the differences between models are absorbed at the edge, never
allowed to reach the centre.

## We provide capability, not product

Swaco is a capability that any app can adopt. It makes no product decisions,
carries no interface, and holds no opinion about how an experience should look
or feel. What an agent means for a given app is decided by that app alone.

This is what makes swaco worth adopting: it brings agentic ability without
bringing anyone else's judgement.

The line between the two is facts and policy. Swaco owns the facts: it makes
sure that whatever a decision would need to know is declared up front and
visible when it matters, whether a tool reads or writes, what a model can
take, where an event came from. The app owns the policy: what to allow, what
to hold, what to do when the facts do not line up. Swaco holds no policy of
its own, not even a cautious one. Where the right answer depends on the
product, swaco asks for it explicitly rather than assuming one; where it does
not, swaco does not ask.

In one line: swaco is responsible for making an agent work correctly inside
an app; the app is responsible for deciding what that agent is as a product.

## Everything is an event

An agent's life is a sequence of things that happen: something arrives, the
agent thinks, the agent acts, something comes back. Swaco treats every one of
these as an event of the same standing, recorded as it happens, and builds
everything else on that record.

A person speaking to the agent is one kind of event among many. A shortcut, a
notification, another app, a place, a time: each is as natural a beginning as
a typed message, and none is assumed.

The record is not ours alone. An app cannot reach into the core, so the log
of what the core did is the one thing it holds in its own hands: to store, to
move, to read, to replay. Its format is therefore part of what swaco promises,
on the same terms as the code, and kept with the same care.

## Native to its home

Swaco belongs to the platform it runs on. It uses what the platform and the
language already provide instead of recreating them, and it respects how apps
on that platform actually live: they are interrupted, suspended, resumed, and
run alongside one another. We design for that reality rather than for an ideal
one.

## Adoption is effortless

An app should become agentic with almost no ceremony. If adopting swaco ever
feels like a project rather than a step, we have failed, and we fix swaco
rather than document the difficulty.

## Explicit, predictable, and honest

We prefer the boring choice to the clever one, the explicit to the implicit,
and the predictable to the flexible. What swaco does is visible, what it emits
is complete, and what it promises is what it delivers.

---

These principles are few on purpose. If a decision cannot be traced back to
one of them, reconsider the decision. If a principle needs to change, change
this document first, and only with great reluctance.
