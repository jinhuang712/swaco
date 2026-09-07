# Examples

What each of these is for, so none of them is here by accident.

| | What it is | Why it exists |
|---|---|---|
| `FirstProgram/` | Twenty lines: import, a provider, a tool, a loop | The acceptance test for adoption. If it ever needs a twenty-first line, a protocol is wrong, and the protocol is what changes |
| `Try/` | The same program against any model on any of the three protocols | Makes "any model, one voice" runnable rather than claimed. Nothing above the provider changes when the model does |
| `Record/` | Asks a real model once and keeps what it said | The recordings under `Tests/` and in the sample app came from here. Run by hand; CI has no key and needs none |
| `Templates/` | Strategies and an app's own tool, toolset and extension | Complete, compiling, copied into an app and owned by it from then on. Shipped to nobody |
| `ChatApp/` | The sample app: a chatbot on a phone | The first app, which decides what swaco builds next. It also runs on a recording, so it can be tried with no key |

Everything here is built in CI, so none of it can drift from the API.

## Running them

```sh
swift run FirstProgram                          # needs SWACO_MODEL_KEY
swift run Try deepseek-v4-flash chat            # chat completions
swift run Try minimax-m3 messages               # the messages protocol
swift run Try muse-spark-1.3-contributor responses
swift run Record                                # refresh a recording, by hand
```

The sample app opens in Xcode from `ChatApp/ChatApp.xcodeproj`. Launch it with
`-recorded` to run on the conversation it once had with a real model, which
needs no key and no network.
