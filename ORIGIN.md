# Origin

Where swaco starts from, and what it borrows. This document comes before the
[philosophy](PHILOSOPHY.md): the philosophy says what we believe, this says
why there is anything to believe about.

## The situation

An agent is a small thing. A model is given some context and some tools, it
answers or asks for a tool, the tool runs, the answer goes back, and this
repeats until the model stops.

```
                 ┌───────────┐
    context ────▶│   model   │────▶ answer ────▶ done
                 └───────────┘
                    │     ▲
          asks for  │     │  result
          a tool    ▼     │
                 ┌───────────┐
                 │   tool    │
                 └───────────┘
```

Everything else built around that loop is scaffolding. Almost all of it
today assumes a process that stays alive: a terminal session, a server, a
desktop app that is open while the agent works. The loop starts, the loop
finishes, and in between nothing happens to the process it runs in.

```
    a server, a terminal, a desktop app

    process  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▶
    loop         ├── turn ──┼── tool ──┼── turn ──┼── tool ──┼── done
```

A native Swift app does not always live like that. A macOS app may stay alive
for hours across many windows. An iOS app is suspended when the person switches
away, killed when the system wants memory, and relaunched into a different
state. An iPadOS app moves between both styles. Any of them may run in a share
sheet or a widget as a separate process, and be woken by a notification, a
shortcut, or a location with nobody watching. None of this is exceptional. It
is how apps on these platforms live.

```
    a suspended, killed, relaunched app

    process  ━━━━━━━━━━━━━╸        ╺━━━━━━━━━━━╸     ╺━━━━━━━━━━━━━━━━━▶
                        suspended  relaunched  killed  woken with
                        by the     by the             nobody watching
                        person     person
    loop         ├── turn ──┼── tool ───?                 ?── tool ──┼──
                                       │                  │
                                 the tool asked      whose result
                                 a person and the    is this, and
                                 process is gone     who is there?
```

Put the loop into that life and naive scaffolding breaks. A tool that awaits a
person never gets its answer because the process that was awaiting is gone.
A half-received reply is lost with the process. A run started by a notification
has no idea whether anyone is there. The loop itself is fine; what some hosts
need around it is different: a way to persist what happened, to resume after
relaunch, to hand a wait across a process boundary, to keep several agents from
stepping on each other.

That is the gap. Not the loop, which is well understood, and not the product,
which is the app's. The part in between: making the same small loop correct
inside apps whose lives differ, without forcing every app to pay for a life it
does not have.

## The inspiration

[pi](https://github.com/badlogic/pi-mono), by Mario Zechner, is a coding
agent built as three separable layers.

```
    ┌─────────────────────────────────────────┐
    │  pi-coding-agent      the product       │  opinion lives here
    ├─────────────────────────────────────────┤
    │  pi-agent-core        the loop          │  tool calling, state
    ├─────────────────────────────────────────┤
    │  pi-ai                the AI layer      │  many vendors, one API
    └─────────────────────────────────────────┘
```

Two things about pi stayed with us.

The first is the separation. The AI layer knows nothing about agents, the
core knows nothing about the product, and each is useful alone. The loop is
small and readable. The product is where opinion lives, and it is the only
place opinion lives.

The second is what pi refuses to do. It does not ship a permission system; it
says so, and points to containers when isolation is wanted. It extends itself
rather than growing a catalogue. It treats "we do not do that" as a design
decision worth writing down rather than a gap to apologise for.

## What swaco takes, changes and leaves

```
    pi                                   swaco

    ┌───────────────────────┐            ┌───────────────────────┐
    │  product              │   left     │  the app              │  not ours
    ├───────────────────────┤   to the   ├───────────────────────┤
    │                       │   app      │  optional runtime     │  added, but
    │                       │            │  persist · resume ·   │  optional:
    │                       │            │  wait across process  │  some lives
    │                       │            │                       │  demand it
    ├───────────────────────┤            ├───────────────────────┤
    │  agent core           │   taken    │  core                 │
    ├───────────────────────┤            ├───────────────────────┤
    │  AI layer             │   taken    │  AI layer             │
    └───────────────────────┘            └───────────────────────┘
```

**Taken.** The AI layer and the agent core as separate things, each linkable
on its own. One vocabulary for all vendors, differences absorbed at the edge.
A loop small enough to be read in one sitting. Non-goals written down.

**Changed.** Between the core and whatever sits on top, swaco adds an optional
runtime. It exists for the lives that need it: suspended, killed, and
relaunched apps where the loop must remember where it was, resume, and let a
wait outlive the process that started it. An app whose process stays alive
never touches it. pi does not need this because its process stays alive. Swaco
offers it because some hosts cannot do without it, and refuses to force it on
hosts that can.

**Left.** The product. pi is a coding agent; swaco is not an agent of any
kind. It has no interface, no bundled tools, no opinion on what the agent is
for. That layer belongs to the app that adopts swaco, and swaco makes no
decision on its behalf.

## In one line

pi showed that an AI layer, an agent core and a product can be three things.
Swaco keeps the first two, makes durability an option between them, and leaves
the third to whoever is building the app.

What follows from this is in the [philosophy](PHILOSOPHY.md).
