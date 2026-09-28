# godot-jev

A Godot 4 add-on for Jev, and a text adventure whose parser understands whatever the player types
but can only choose moves the author made possible.

Classic parser games failed on vocabulary ("I don't know the word 'grab'"). LLM-driven games fail
the other way, inventing doors and items that don't exist. Here the author writes every room, item
and line; each turn, the moves possible *right now* become the options of one Jev Choice, plus
"none of these". The model can't pick a door that isn't there, because it isn't an option.

```
player types: "grab the lamp"
        │
world.possible_actions()  → take__lantern, examine__note, go__down, look__around, ... + none_of_these
        │
Jev Choice ─ confidence ≥ 0.75 → act:      world.apply("take__lantern") → "You take the brass lantern."
           ─ ≥ 0.40            → clarify:  "Did you mean: 1. take the lantern  2. examine the lantern"
           ─ lower, or none    → unknown:  an authored "that doesn't seem possible" line
```

Over 254 possible actions (Jev's Choice takes 255 options), it asks twice: which verb, then which
action with that verb.

## What's here

| Path | Role |
| --- | --- |
| `addons/jev/` | The add-on: `Jev` autoload, `http_decider.gd` (HTTPRequest to the REST API), `jev_q.gd` (question builders), `scripted_decider.gd` (tests and offline play) |
| `demo/world.json` | The authored world: 3 rooms, 3 items, a dark cellar and a locked door |
| `demo/world.gd` | Rules: possible actions, and authored responses only |
| `demo/parser.gd` | Player text to one possible action, gated by confidence |
| `demo/adventure.gd` | The playable scene |
| `tests/` | A headless runner and 17 tests |

Using the add-on in any game:

```gdscript
const JevQ := preload("res://addons/jev/jev_q.gd")

var out := await Jev.decide({"hp": 12, "enemy": "wolf", "weapon": "stick"}, {
	"flee": JevQ.noul("The character should run away."),
	"mood": JevQ.choice("How does the innkeeper feel about the player?", {"warm": "friendly", "wary": "suspicious", "hostile": "angry"}),
})
if out.has("error"):
	pass  # fall back to scripted behaviour
```

## Hypothesis

A Choice over the currently possible moves lets players type naturally with few dead ends, while
the game stays fully authored, and it's fast enough to feel like a parser, not a chat.

## Checks (done when)

1. **Understanding.** On a corpus of ≥ 100 player inputs across the demo (paraphrases, typos,
   indirect requests), ≥ 90% resolve to the intended action or a clarify that contains it, and
   ≥ 90% of impossible or off-topic inputs resolve to `unknown`.
2. **Speed.** p95 ≤ 500 ms per turn from input to response.
3. **Nothing invented.** The options offered are exactly the possible actions plus `none`, for
   every state of the demo. `[pass]` by construction: `test_options_are_exactly_the_possible_actions_plus_none`.
4. **Shippable.** An exported build works with no key in the client, through a small proxy.

## Run it

```bash
export TYPESAFE_API_KEY=sk-...        # read by the Jev autoload; local prototyping only
godot --path .                        # play
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Without a key the game still runs; the parser reports it's offline.

## Open

1. Write the check-1 corpus (`tests/corpus.json`: input, game state, expected action) and a
   headless eval script that plays it against the live API.
2. Try the add-on in a larger game: characters that react to the player through `Noul` and `Score`
   questions about what they see, alongside the parser.
3. A tiny key-holding proxy for exported builds (check 4).
4. Package `addons/jev` for the Godot Asset Library.

Don't ship an API key inside an exported game: anyone can extract it. The HTTP decider takes a
`base_url` so a proxy can hold the key instead.
