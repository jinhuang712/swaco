# swaco

A minimal, product-agnostic agent core for native Swift applications.

Swaco is responsible for making an agent work correctly inside an app.
The app is responsible for deciding what that agent is as a product.

Swaco gives any Swift app on macOS, iPadOS, or iOS the same small agent
underneath: one loop, one voice for any model, capabilities injected by the
host, and everything the agent does observable as events. Durability,
platform bridges, and product patterns live above the core, as optional
layers. No UI, no bundled tools, no third-party dependencies.

- [Origin](ORIGIN.md): where swaco starts from, and what it borrows.
- [Philosophy](PHILOSOPHY.md): what we believe and never violate.
- [Goals](GOALS.md): what we are trying to achieve, and what we are not.
- [Architecture](ARCHITECTURE.md): how swaco is divided, and the rules between the parts.
- [Features](FEATURES.md): what we are building to get there, and its status.
- [Git flow](GITFLOW.md): how changes reach `main`.
- [Examples](Examples/README.md): what each example is for, and how to run it.
