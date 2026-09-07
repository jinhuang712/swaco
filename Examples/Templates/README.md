# Templates

Strategies an app may want and would answer in its own way.

Each file here is complete, compiles, and is built in CI so it cannot drift
from the API. None of it is shipped or versioned: copy the file into your app
and it is yours from then on, to change as your product requires.

They are here for two reasons. The first is to spare the first adopter a blank
page. The second is proof: each one is written through the same public
protocols any third party has, so if one of them needed a private path, the
core would be deficient and the core would be fixed.

| Template | What it does | The door it uses |
|---|---|---|
| `Budget.swift` | Stops a loop after so many turns, or so long | a refusal at the end of a turn |
| `ProgressiveDisclosure.swift` | Shows the model a few tools and one for finding the rest | rewriting the request, plus a tool |
| `Compaction.swift` | Keeps a long history inside a model's context | rewriting the request |

What is missing from this list is deliberate. Authorisation gating belongs with
the platform toolsets, because it is a bridge to the system rather than a
strategy. Anything that is only a bridge is a companion, not a template.
