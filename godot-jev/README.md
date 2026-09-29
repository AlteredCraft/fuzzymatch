# godot-jev

A Godot 4 add-on for Jev, and *The Sunken Crypt*, a small D&D-style dungeon crawl whose parser
understands whatever the player types but can only choose moves the author made possible.

![The hall of pillars: a skeleton guards the north arch while the parser asks which torch action the player meant](docs/screenshot.png)

Classic parser games failed on vocabulary ("I don't know the word 'grab'"). LLM-driven games fail
the other way, inventing doors and items that don't exist. Here the author writes every room, item
and line. Each turn, the moves possible *right now* become the options of one Jev Choice, plus
"none of these". The model can't pick a door that isn't there, because it isn't an option.

```
player types: "grab the torch"
        │
world.possible_actions()  → take__torch, examine__torch, go__north, look__around, ... + none_of_these
        │
Jev Choice ─ confidence ≥ 0.75 → act:      world.apply("take__torch") → "You take the torch."
           ─ ≥ 0.40            → clarify:  "Did you mean: 1. examine the torch  2. drop the torch"
           ─ lower, or none    → unknown:  an authored "that doesn't seem possible" line
```

With more than 254 possible actions (Jev's Choice takes up to 255 options, and one is "none"), it
asks twice: first which verb, then which action with that verb.

## The dungeon

Six rooms, five items, and one chain of puzzles. The player starts at the bottom of a collapsed
stair and has to reach the vault.

```
                     [ Vault ]
                         │   black door: needs the silver key
                  [ Antechamber ]
                         │   guarded: the skeleton won't let you pass
  [ Ossuary ] ── [ Hall of pillars ] ── [ Armory ]
    dark: needs          │                sword, vellum
    a lit torch   [ Crypt stairs ]  ← start
                    torch, brazier
```

One route through it: take the torch and light it in the brazier. Go north to the hall, then east
to the armory for the shortsword (the vellum there hints at the rest). Back in the hall, attack the
skeleton. West, the ossuary is pitch black without a lit torch; with one, the silver key is on the
altar. Return through the hall, go north, unlock the black door, and go north into the vault.
`test_the_whole_dungeon_can_be_solved` plays exactly this route.

The player never has to type those words. "Set the rag on fire", "stab the bones" and "use the
little key on the door" all go through the same Choice, whose options are only what's possible
in that room at that moment.

## The screen

The game opens on a start menu over the crypt stairs: **Enter the crypt**, **Help** and **Quit**,
with a line saying whether Jev is listening (and which model) or offline for want of
`TYPESAFE_API_KEY`. Help is a scrolling page on what the experiment is about: the problem, how the
Choice over possible moves works, the act and clarify thresholds (read from the parser, not
written into the text), the hypothesis, and how to read the screen below. Back or Esc returns to
the menu.

| Area | What it shows |
| --- | --- |
| Room art (top left) | A 160×90 pixel scene for the current room, scaled 4×. Fires flicker and shed embers, and rooms change through a dithered dissolve. It drops to near-black in a dark room without light, and switches to a room's variant art once the variant's flag is set (the hall after the skeleton falls). The room's name sits on a plaque in the corner. |
| Status panel (bottom left) | Exits and what you're carrying, plus **Jev heard**: the latest outcome (act, clarify, unknown, or error when the API is unreachable), the action it chose, a confidence meter with ticks at the clarify (0.40) and act (0.75) thresholds, and the turn's latency. It's there to make the experiment visible while playing. |
| Transcript (right) | Room names as headings, your commands echoed in muted text, item lines highlighted, and new text revealed a few characters at a time. Clarify options are links: click one, or type 1 or 2. |
| Turn scores | Each command Jev answered ends with its outcome and confidence (`act 0.94`, `clarify 0.52`, `offline`). Click one to open that turn's card: what you typed, the outcome and move, confidence against the thresholds, latency, how many options were offered, API calls, the model, and the top three candidates with their probabilities. Esc or a click elsewhere closes it. |
| Input | Enter submits; ↑ and ↓ recall earlier commands. The input is locked while Jev is deciding. |

The layout is 1280×720 and scales with the window (`canvas_items` stretch). The fonts are
[VT323](https://fonts.google.com/specimen/VT323) for body text and
[Pixelify Sans](https://fonts.google.com/specimen/Pixelify+Sans) for headings, both under the SIL
Open Font License (licence files in `demo/fonts/`).

## Writing a world

Everything the game can say or do comes from `demo/world.json`. The engine (`demo/world.gd`) only
reads it.

**Rooms** are keyed by id.

| Field | Meaning |
| --- | --- |
| `title`, `text` | Shown when the player enters or looks around. The title becomes the transcript heading. |
| `exits` | `direction → {to}`. Add `locked_until: <flag>` and `locked_text` for a door, guard or anything else that blocks the way until a flag is set. The exit is still offered, so "go north" gets the authored refusal instead of "I don't understand". |
| `items` | Item ids lying in the room at the start. |
| `dark`, `dark_text` | The room shows `dark_text` and hides its items until the world's `light_flag` is set. |
| `variants` | `[{when, text, art}]`. The first variant whose `when` flag is set replaces the room's text and art. |

**Items** have a `name` (used in every generated option, like "take the torch"), the `text` shown
on examine, and `takeable`.

**Interactions** are the special moves: `id` (`verb__object`), `text`, `needs` (`holding` item
ids, `in` a room, `flag_unset`), the flag it `sets`, and what it `says`. Take care over `text`: it's
the option description the model reads when it matches the player's words, so it should say what
the move is ("attack the skeleton with the shortsword"), not how it turns out.

Built-in moves are generated for every room: look around, check inventory, go through each exit,
and take, examine or drop each item that is visible or carried.

## Room art

The PNGs in `demo/art/` are placeholders painted by code:

```bash
godot --headless --path . --script res://tools/paint_rooms.gd
```

`tools/paint_rooms.gd` draws each room in one-point perspective (brick walls, a flagstone floor
and a vaulted ceiling with ribs carried down the walls as pilasters), cuts doorways for the room's
exits in `world.json` (north is an arch in the back wall; east and west are passages in the side
walls; south is behind the viewer), and adds props from small ASCII sprites and painters: the
skeleton, braziers, sconces, banners, weapon racks, skull niches, the altar, chests and the crown.
Lighting is computed per pixel from each room's lights and then snapped to fixed colour ramps with
4×4 Bayer dithering, so the output stays a limited-palette pixel image rather than a smooth
gradient. Lights are warm (fire) or cool (daylight, bounce): where firelight dominates, stone,
floor and wood swap to warm twins of their ramps, with a dithered edge, so torchlight pools amber
against cold violet shadow. Seams between walls, floor and ceiling, and the floor under props,
are shaded darker.

In the game, `demo/room_fx.gd` animates the still image with a shader. Pixels in exactly the
flame ramp's colours step up and down that ramp, the scene brightens and dims slightly with the
firelight, and embers rise from the brightest flame pixels. Room changes dissolve pixel by pixel
in Bayer order. Hand-made art without those exact colours is shown as it is, with no flicker or
embers.

To use real art, replace any file with a 160×90 PNG of the same name: the room id, or the
variant's `art` name. `test_every_room_and_variant_has_art` fails if one is missing. Dark rooms
don't need separate art; the scene dims the room's image at runtime.

## What's here

| Path | Role |
| --- | --- |
| `addons/jev/` | The add-on: `Jev` autoload, `http_decider.gd` (HTTPRequest to the REST API, polled on a thread), `jev_q.gd` (question builders), `scripted_decider.gd` (tests and offline play) |
| `demo/world.json` | The authored dungeon: 6 rooms, 5 items, 3 interactions |
| `demo/world.gd` | Rules: possible actions, room variants, and authored responses only |
| `demo/parser.gd` | Player text to one possible action, gated by confidence |
| `demo/start_menu.gd` | The start menu (the main scene) and its help page |
| `demo/help.gd` | BBCode for the help page, and the menu's Jev status line |
| `demo/adventure.gd` | The playable scene: art, status panel, transcript and input |
| `demo/style.gd` | Palette, fonts, brass-cornered panels and theme shared by the menu and the game |
| `demo/room_fx.gd` | Flame flicker, embers and the dissolve between rooms, for the menu and the game |
| `demo/transcript.gd` | BBCode for the transcript; escapes all authored and typed text |
| `demo/art/`, `demo/fonts/` | Room images and the two pixel fonts |
| `tools/paint_rooms.gd` | Regenerates the placeholder room art |
| `tools/session.gd` | A scripted player: 16 lines that solve the dungeon, typed at a human pace |
| `tools/record_session.gd` | Plays `session.gd` under Movie Maker to record a video, or rehearses it headless |
| `tools/trailer.py` | Cuts a short trailer, with zooms, captions and spotlights, from a 2× recording |
| `tests/` | A headless runner and 50 tests; a script error inside a test counts as a failure |

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
2. **Speed.** p95 ≤ 500 ms per turn from input to response. The status panel shows each turn's
   latency; the corpus eval should record it. In the recorded session (16 turns, `jev-latest`,
   2026-09-29) every turn took 197–300 ms. The HTTPRequest runs on a thread: polled on the main
   thread it only advanced once per frame, which added about 170 ms per turn at 30 fps and 45 ms
   at 60 fps.
3. **Nothing invented.** The options offered are exactly the possible actions plus `none`, for
   every state of the demo. `[pass]` by construction: `test_options_are_exactly_the_possible_actions_plus_none`.
4. **Shippable.** An exported build works with no key in the client, through a small proxy.

## Run it

```bash
export TYPESAFE_API_KEY=sk-...        # read by the Jev autoload; local prototyping only
godot --path .                        # play (opens the start menu)
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

Without a key the game still runs, but every turn reports that the parser is offline.

## Recording a session

`tools/session.gd` plays the dungeon from the start menu to the crown in 16 lines of Snoop Dogg
slang ("roll on up north, cuz", "lay the smack down on Mr. Bones wit the blade"). The first,
"ayo where the gin and juice at, nephew?", asks for something the author never wrote and should
come back `unknown`. Each line names the move it means, so the session can check itself:

- It types about eight keys a second with a beat at each new word, then waits for Jev and for the
  transcript to finish revealing, and pauses 1.5–7 s to read, longer for more text.
- A clarify is answered with the intended option. An `unknown` is retried once in the option's own
  words ("go north"). A wrong move stops the session and exits 1, since the rest of the route no
  longer applies.

Rehearse against the live API first (headless, no pauses), then record with Movie Maker:

```bash
godot --headless --path . --script res://tools/record_session.gd -- --rehearse
godot --path . --write-movie session.avi --fixed-fps 30 --script res://tools/record_session.gd
ffmpeg -i session.avi -an -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart session.mp4
```

Both print each turn (what was typed, outcome, move, confidence, latency). A recording runs in
real time, about four minutes: Movie Maker renders as fast as it can, so the script holds the game
clock to the wall clock to keep each wait on Jev as long as it really was. The window can be
covered or minimized. macOS stops drawing a hidden window, and Movie Maker would then repeat the
last frame while play went on, so the script draws those frames itself. Don't type or click in it.

Every text entered is also logged as `mark <frame> typing|enter|shown <text>`, the frames where
typing starts, Enter is pressed, and the answer has finished revealing. `tools/trailer.py` uses
them to cut a 1920×1080 trailer: the gin line and the skeleton line, typing sped up 1.7×, eased
zooms onto the input, spotlights on each result and on the Jev panel, captions, and an end card.
It zooms to about 2×, so record at 2560×1440 for it, with a temporary `override.cfg` (gitignored)
that doubles the window without changing the layout:

```bash
printf '[display]\n\nwindow/size/window_width_override=2560\nwindow/size/window_height_override=1440\n' > override.cfg
godot --path . --write-movie session.avi --fixed-fps 30 --script res://tools/record_session.gd > session.log
rm override.cfg
uv run tools/trailer.py session.avi session.log trailer.mp4
```

The trailer's shots, zoom targets and spotlit areas are set for these two lines and this layout;
change the constants at the top of the script if either changes.

## Open

1. Write the check-1 corpus (`tests/corpus.json`: input, game state, expected action) and a
   headless eval script that plays it against the live API. The dungeon now has enough rooms,
   items and blocked exits to cover paraphrases, wrong-room requests and "none" cases.
2. D&D mechanics that stay authored: hit points, and d20 checks whose outcomes are all written
   (`"check": {"dc": 12, "pass": "...", "fail": "..."}`), so the parser still only chooses the move
   and code rolls the dice.
3. Creatures that react through `Noul` and `Score` questions about what they see ("the player is
   threatening me", "how afraid is the goblin"), alongside the parser.
4. Scenery the player can examine (the brazier, the altar, the pillars) without making it an item.
5. A tiny key-holding proxy for exported builds (check 4).
6. Package `addons/jev` for the Godot Asset Library.

Don't ship an API key inside an exported game: anyone can extract it. The HTTP decider takes a
`base_url` so a proxy can hold the key instead.
