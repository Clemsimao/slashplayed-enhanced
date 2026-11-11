# Slashplayed Enhanced

**World of Warcraft on iPad, with touch controls shaped by real play.**

Slashplayed Enhanced is a hands-on, polish-focused fork of
[Slashplayed by Paul Straw / Straw Dynamics](https://github.com/paulstraw/slashplayed).
It builds on that project's native Apple Silicon compatibility layer, with a focus on how the
whole experience feels during an actual play session: reaching abilities, moving and targeting,
managing bags, and adjusting your layout without breaking your flow.

The direction is deliberate UI and UX, refined on a real iPad: comfortable touch targets, clear
feedback, readable settings, and controls that stay where you put them. Each change should make
playing feel more natural and the interface more finished.

## What Enhanced adds

| Area | In this fork |
|---|---|
| **Touch action bars for Forever** | Circular spell buttons with independent assignments, movable and resizable controls, two spell sets, and separate Ctrl, Alt, and Shift layers. |
| **A practical utility bar** | Consumables, buffs, and mounts in a movable group, with configurable count, rows, size, spacing, and separate appearance settings. |
| **Layout editing** | A compact native inspector, selection feedback, sliders, a safe preview, session Undo, and options to hide unused slots or whole bars. |
| **Finishing details** | Adjustable outline colour, opacity, and glow; pressed-state feedback; and smooth set-switch arrows in a lightly tinted circle with a readable set number. |
| **Everyday interactions** | Independent Interact, Target, and Map buttons. Interact steps through quests one press at a time and waits for manual reward selection. |
| **Movement and input** | An analog touch joystick, a right-click modifier for finger or Apple Pencil input, and optional Ctrl, Alt, Shift, and Space controls. |
| **Controls that stay put** | Saved positions and sizes, hold-to-move feedback for the joystick and Space, and touch margins that help prevent accidental game taps. |
| **Clearer settings and display choices** | A category sidebar, persistent control instructions, and in-game resolution choices that adapt to the display and orientation. |
| **Bag management** | Bagnon and its required modules download from the publisher on first launch, then use a verified offline cache. |

The native input and settings improvements target iPad and iPhone. **SPTouchBars is for Forever**;
the other game clients retain their existing action bars. The foundation still supports Apple
Vision Pro. See the [player guide](docs/guide.md) and [touch-bar guide](addon/SPTouchBars/README.md)
for controls and configuration.

## Project status

This is active development, shaped by hands-on iPad play and automated addon, input, display, and
installation checks. A polished everyday experience is the goal; device coverage and broader
in-game testing are still growing.

**Enhanced is currently available as source.** There is no Enhanced binary release or separate
update channel yet. The original project's releases do not include this fork's changes. Existing
application names and identifiers remain Slashplayed, so this repository name does not create a
second game installation or discard saved layouts.

The fork's default branch is **`enhanced`**. Its **`main`** branch preserves upstream's fork-time
state; upstream changes can be reviewed and integrated separately. The original project's work,
history, and MIT attribution are retained.

> **Unofficial and at your own risk.** Slashplayed isn't affiliated with or endorsed by Blizzard
> Entertainment. It includes no Blizzard files: the game downloads from Blizzard, and you need your
> own Battle.net account and subscription. Blizzard doesn't support playing this way, and your
> account could be actioned. It's early, and a game patch can break it until Slashplayed catches up.

## Games and devices

Every World of Warcraft game Battle.net offers for the Mac: **Classic Era** (Hardcore and Season of
Discovery included: switch the game mode in game), **TBC Anniversary**, **Mists of Pandaria
Classic**, and **Retail**. They run on an **iPad** with M1 or later (or the A17 Pro iPad mini), an **iPhone 15 Pro** or later,
and **Apple Vision Pro**. M1 iPads (the 2021 iPad Pros and the 5th-generation iPad Air) and the A17 Pro
iPad mini are untested: Slashplayed has only been played on M2 and later iPads. If you try one, please
[report how it goes](https://github.com/rollarz/slashplayed-enhanced/issues/new/choose), working or not,
with the zip from the companion's **Help > Export Diagnostics…**.
In-game voice chat isn't supported on the device yet
([#12](https://github.com/paulstraw/slashplayed/issues/12)).

## Requirements

- An **Apple Silicon Mac** with macOS 15 or later and Xcode. No Mac? For an iPad or iPhone, a tool for
  Windows and Linux is in testing: see [Setting up without a Mac](docs/setup-without-a-mac.md).
  Vision Pro needs a Mac.
- An **Apple ID signed in to Xcode**. A free one works, and the app is signed again every 7 days; a
  paid Apple Developer Program membership signs it for a year.
- Your device on **iPadOS 26, iOS 26, or visionOS 27**. Setup walks you through pairing it with the
  Mac and turning on Developer Mode.
- A **Battle.net account** with an active World of Warcraft subscription. The game doesn't need to be
  installed on the Mac.
- A **hardware keyboard** for typing in the game, which has no on-screen keyboard. On an iPhone, a
  mouse needs AssistiveTouch on.
- **[LocalDevVPN](https://apps.apple.com/app/id6755608044)**, free on the App Store, turned on when
  the game starts.
- **Free space** on the device:

  | Game | Space |
  |---|---|
  | Classic Era | ~25 GB |
  | Classic Era + TBC Anniversary | ~37 GB |
  | Mists of Pandaria Classic | ~150 GB |
  | Retail | ~150 GB |

  A game grows toward these sizes as you play. Retail on an iPad or iPhone needs a 512 GB device
  with 8 GB of memory.

## Get started

1. Clone this fork and its `enhanced` branch:

   ```sh
   git clone --branch enhanced https://github.com/rollarz/slashplayed-enhanced.git
   cd slashplayed-enhanced
   ```

2. Follow [Building from source](CONTRIBUTING.md#setup) for the Xcode, Rust, and dependency setup.
   Build with `apps/companion/build.sh`, then open the companion in `build/companion/`.
3. Use the companion's setup assistant to pair your device and install the app. SPTouchBars is bundled
   for Forever; Bagnon downloads on first game launch. In game, open **Settings > AddOns > SPTouchBars**
   or type `/sptouch` to arrange the touch bars.
4. Sign in using the normal Slashplayed flow, then play from the device. A hardware keyboard is still
   needed for game text entry. [The guide](docs/guide.md) covers setup and day-to-day use.

Until an Enhanced update channel exists, rebuild from this fork to receive its changes. The inherited
companion updater points to upstream Slashplayed; installing an upstream companion update replaces
Enhanced's companion build. Blizzard game patches are a separate update path.

Leaving the game for more than about 30 seconds (closing its window, taking off the headset, or
switching apps) can disconnect it. Use **Exit** or **Log Out** first to keep that session's settings.

The [guide](docs/guide.md) covers the rest: playing from the Mac, copying game files over, addons,
and free and paid Apple IDs. Something wrong? See [troubleshooting](docs/troubleshooting.md), then
[report an issue](https://github.com/rollarz/slashplayed-enhanced/issues/new/choose) with the zip from the
companion's **Help > Export Diagnostics…**.

## How it works

The companion downloads the Mac client from Blizzard, rewrites its load commands to point at
Slashplayed's shim libraries, and signs it with your Apple ID. On the device, the shims stand in for
AppKit, CoreAudio, and the other macOS frameworks, and a small helper prepares the client's
executable memory under TXM at each launch (that's what LocalDevVPN is for).
[architecture.md](docs/architecture.md) has the whole pipeline, and [research.md](docs/research.md)
the experiments behind it.

## Contributing

Bug reports, patch reports, and pull requests are welcome: [CONTRIBUTING.md](CONTRIBUTING.md) covers
them and building from source. Report security issues privately, as [SECURITY.md](SECURITY.md)
explains.

## Credits and license

The native compatibility layer, companion, launcher, and original project are the work of
[Paul Straw / Straw Dynamics and upstream contributors](https://github.com/paulstraw/slashplayed).
Enhanced builds on that foundation with a focus on touch interaction and practical UI refinements.
Bagnon remains a separate third-party addon, downloaded from its publisher rather than redistributed
in this repository.

[MIT](LICENSE). Copyright (c) 2026 Straw Dynamics. The third-party licenses ship in the companion
(About Slashplayed Companion > Acknowledgements) and in the device app.

World of Warcraft and Battle.net are trademarks of Blizzard Entertainment, Inc. Apple Vision Pro,
iPad, iPhone, visionOS, iPadOS, iOS, macOS, and Xcode are trademarks of Apple Inc.
