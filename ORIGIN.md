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

An iOS app does not live like that. It is suspended when the person switches
away, killed when the system wants memory, relaunched into a different state,
run in a share sheet or a widget as a separate process, and woken by a
notification, a shortcut or a location with nobody watching. None of this is
exceptional. It is how every app on the platform lives, all the time.

```
    an iOS app

    process  ━━━━━━━━━━━━━╸        ╺━━━━━━━━━━━╸     ╺━━━━━━━━━━━━━━━━━▶
                        suspended  relaunched  killed  woken by a
                        by the     by the             notification,
                        person     person             nobody watching
    loop         ├── turn ──┼── tool ───?                 ?── tool ──┼──
                                       │                  │
                                 the tool asked      whose result
                                 a person and the    is this, and
                                 process is gone     who is there?
```

Put the loop into that life and the scaffolding breaks. A tool that awaits a
person never gets its answer because the process that was awaiting is gone.
A half-received reply is lost with the process. A run started by a
notification has no idea whether anyone is there. The loop itself is fine;
what it needs around it is different.

So every app that wants an agent rebuilds the surroundings: a way to persist
what happened, to resume after relaunch, to hand a wait across a process
boundary, to keep several agents from stepping on each other, to talk to more
than one model vendor through one shape. Each app does it slightly
differently and none of it is the app's product.

That is the gap. Not the loop, which is well understood, and not the product,
which is the app's. The part in between: making the loop correct inside an
app that is interrupted, suspended, killed and relaunched as a matter of
course.

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
    │                       │   app      │  runtime              │  added:
    │                       │            │  persist · resume ·   │  the phone
    │                       │            │  wait across process  │  demands it
    ├───────────────────────┤            ├───────────────────────┤
    │  agent core           │   taken    │  core                 │
    ├───────────────────────┤            ├───────────────────────┤
    │  AI layer             │   taken    │  AI layer             │
    └───────────────────────┘            └───────────────────────┘
```

**Taken.** The AI layer and the agent core as separate things, each linkable
on its own. One vocabulary for all vendors, differences absorbed at the edge.
A loop small enough to be read in one sitting. Non-goals written down.

**Changed.** Between the core and whatever sits on top, swaco adds a runtime.
It exists because of the situation above: apps on this platform are
suspended, killed and relaunched, and the loop needs something that
remembers where it was, resumes it, and lets a wait outlive the process that
started it. pi does not need this because its process stays alive. Swaco
cannot do without it.

**Left.** The product. pi is a coding agent; swaco is not an agent of any
kind. It has no interface, no bundled tools, no opinion on what the agent is
for. That layer belongs to the app that adopts swaco, and swaco makes no
decision on its behalf.

## In one line

pi showed that an AI layer, an agent core and a product can be three things.
Swaco keeps the first two, adds what a phone demands between them, and leaves
the third to whoever is building the app.

What follows from this is in the [philosophy](PHILOSOPHY.md).
