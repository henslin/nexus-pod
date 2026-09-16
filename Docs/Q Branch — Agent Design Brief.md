# Q Branch — designing the Nexus agent

*Overnight 2026-09-15/16. A working brief for the team, written from the
Lab as it stands. Opinions are marked as such.*

## What makes working with an assistant actually work

Working with an AI agent goes well for reasons that have nothing to do
with the model and everything to do with the conversation's shape. Each
of these is now something the Lab can show, not just describe.

1. **It shows it heard you.** Your ask is echoed back — typed, or word
   by word as you speak it. In the Lab: the ask bubble, the live
   transcript (Bloom Field, the Transcript adornment, the Talk surface).
2. **It shows what it is doing, and names it.** Not a spinner:
   *Thinking…*, *Checking the doorbell…*. The states are the product's
   verbs — Idle, Listening, Thinking, Searching, Speaking, Done, Error —
   and each has a look. In the Lab: Agent States, Q Branch's state slots.
3. **The answer arrives as it is made.** Streaming words, not a paragraph
   that lands. In the Lab: `Speaking`, the words blurring in.
4. **It answers, then offers the next move as a tap.** Follow-ups are
   chips, not a second paragraph. In the Lab: `Done`, the follow-up row.
5. **It knows where you are.** On Devices, the first suggestions are
   about the devices in front of you. In the Lab: the Ask Button's
   Context switch. This is the difference between "Ask Nexus" and a
   search field, and it is the whole argument for a button on every
   screen.
6. **You can interrupt.** *Tap to interrupt* while it speaks; hold to
   keep talking. In the Lab: the Talk surface, the Hold flow.
7. **It takes only the space the ask deserves.** A quick question is a
   sheet; a voice conversation is the screen; a proactive notice is a
   card; a status is a pill. In the Lab: Surfaces, and a surface per
   action in Q Branch.
8. **It is the same character everywhere.** The orb in the pod, in the
   sheet's corner, in the Ask button — one presence, in different states.
   In the Lab: a look per state, the hero riding through every surface.
9. **It fails honestly.** *I couldn't reach the doorbell — trying
   again.* In the Lab: the Error state (Play → Include Error).

## How the Lab is organised now

Five rooms, in the order a designer meets the parts of an agent:

| Room | The question | What's in it |
|---|---|---|
| **Orb** | What does it look like? | ~60 bases on six shelves (Light, Water, Frosted, Particles, Shape, 3D & Kits), and post effects that stack over any |
| **Controls** | What do you tap? | Ask Button, Gooey, Metal, Border Beam |
| **Surfaces** | What opens? | Morph — pill, card, sheet, full screen — with adornments (edge glow, beam, waveform, caption, transcript) |
| **Flows** | How does it move? | Journey, Agent States, Hold, Bloom Field |
| **Q Branch** | How does it all fit? | The spec: every slot filled, played end to end |

The rail beside any experiment is in the order of use: its own knobs
first, then the post stack, then the room it is judged in (Stage,
Colour, Audio, Export) as disclosures that remember whether you left
them open.

## The Q Branch loop

1. Start from a **Starter** (Specs menu): *Their Kit*, *Glass & Light*,
   *Water*. Play it — tap the phone to step, or click a step in the strip.
2. Find the weak slot. Click it → **Choose in the Lab…** The rail there
   shows the errand ("Choosing for Listening") and one **Use** button.
3. Tune, Use, you're back. Play again.
4. Surfaces edit in place: shape, what they carry, how they come and go.
5. Pick the conversation the play runs (Quick question, Device help,
   Onboarding & placement, Battery life) — a surface is judged on a real
   exchange, not placeholder copy.
6. **Save** the spec by name. **Copy JSON** → on the phone, Nexus Lab →
   The Agent → **Paste Spec**. The team plays whole agents against each
   other and rates them.

## Recommendations (mine — argue with them)

- **One character.** Pick one orb family for every state, and let the
  state change its *behaviour*, not its species. Their kit does this
  best today because its verbs are legible at 62pt. If we go with one
  of ours, Glass & Light's shelf (Aurora → Liquid Ring → Sphere) is the
  closest to a single character with moods.
- **Tap = Ask, hold = Talk.** The pod menu is a lovely control and one
  tap too many for the most common thing. Tap should open the Ask sheet
  with the field focused and three context suggestions; hold should go
  straight to full-screen listening. Keep the goo for the app-wide Ask
  button, where a menu earns its place.
- **Sheet for text, full screen for voice, card for the agent speaking
  first.** Full screen for a typed question feels like being shouted
  at. The card is the proactive surface ("John arrived home") and
  should carry the same follow-up chips.
- **Ask everywhere = floating goo with context**, nav-bar pill on list
  screens. The bar above the tab bar is the strongest for onboarding
  ("Ask Nexus about this screen") and the weakest once you know the app.
- **Voice-forward means the transcript is always visible** while it
  listens, and *Tap to interrupt* is always true while it speaks.
- **Bloom Field is the ambient mode**, not the default: a full-screen
  ethereal surface for when the phone is on the table and you're
  talking to the house. Worth keeping as the third surface for Talk.

## Open questions for the team

- Does the pod stay a ring at rest, or is the orb the pod? (Q Branch's
  Pod slot; try both starters.)
- One menu for the app-wide Ask and the pod, or different items? (The
  Items chips are shared today.)
- How much of the screen does Thinking get to take? A pill that grows
  is calmer than a sheet that appears.
- What does Error look like on the orb — a colour, a shape, a stillness?

## Not built yet

- A model behind it: the conversations are scripts.
- A spec becoming the *real* Nexus tab in the iOS app (the pod, sheet
  and Ask button reading a `LabSpec`) — the bridge from Q Branch to
  product, and the next big step.
- Two specs side by side.
- Typing in the sheet's field (it's a mock); dragging to reorder.
