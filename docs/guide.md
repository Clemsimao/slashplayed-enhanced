# Slashplayed guide

Everything past the [README](../README.md)'s getting started. When something goes wrong,
[troubleshooting](troubleshooting.md) has the fix for each message.

## Setup

Slashplayed comes in two parts: **Slashplayed Companion** on the Mac, which builds, signs, and
installs the app, and **Slashplayed** on the device, which runs the game.

The companion's setup assistant goes one step at a time and offers a fix for each problem it finds:
Xcode, your Apple ID and team, your devices, LocalDevVPN, and which games go on each device. An
optional step shows which games are installed on the Mac, if any. Then it installs Slashplayed on
each device you pick, and a last optional step sets up
[Update Games on This Device](#update-games-on-this-device). **Help > Setup Assistant…** runs the
checks again later.

- **Xcode** needs an administrator's password once, the first time it's set up. After that, a
  standard macOS account works ([details](troubleshooting.md#xcode)).
- **An iPad or iPhone** pairs over USB: click Allow when macOS asks to let the accessory connect,
  then tap Trust on the device.
- **Vision Pro** pairs in Xcode > Open Developer Tool > Device Hub, with Settings > General > Remote
  Devices open on the headset.

## Playing

Open Slashplayed on the device and tap a game. The Mac can be asleep or away.

Or press **Play** in the companion, with the game picked in the menu next to it. Battle.net doesn't
need to be running. Play updates the app first when it needs to: after a game patch, after you
change a device's games, and every 7 days on a free Apple ID. Keep the device awake while it works:
unlock the iPad or iPhone and connect its cable, or wear the headset.

The first start of each game takes a few minutes while it fetches its data from Blizzard (about 2.5
minutes to character select for Classic Era on an iPhone over Wi-Fi). After that, it fetches what
each zone needs while the game is on screen.

### Touch mouse controls

On iPad and iPhone, tap the game to left-click. Hold the **R** square with one thumb while tapping
elsewhere with a finger or Apple Pencil to right-click at that position. Holding the square alone does
not click or move the cursor. A click keeps the same button until the finger or Pencil lifts, even if
you release your thumb first. Holding the square while dragging a finger or Pencil gives a right-button
drag.

Drag the square itself to move it; its position is saved on this device and adapts to the available
screen area after rotation or resizing. Small thumb movements do not move it. In the start screen's
**Settings > Controls > Right-click Button**, **Size** adjusts the square and its R label from about 58% to 200%
of the default size; your choice is saved on this device. The default square is 76 points wide, larger
than the original 52-point button. **Right-Click Thumb Button** hides or shows it, and **Reset Thumb Button
Position** returns it to the lower-left side. The existing two-finger right click and three-finger
middle click remain available.

### Keyboard buttons

In **Settings > Controls > Keyboard Buttons**, turn **Ctrl**, **Shift**, **Alt**, and **Space** on or off
individually. They start hidden. Hold a modifier square while clicking with a finger or Apple Pencil,
using **R**, or pressing another key. Releasing the square releases that modifier. You can hold more
than one modifier together, and the buttons also work alongside a physical keyboard.

Drag a modifier square to reposition it, just like **R**. Press anywhere in **Space**'s visible circle
to hold the spacebar, and lift to release it. Holding still fills the outer ring for **two seconds**;
once it turns gold, Space releases and you can drag the button to reposition it. Lifting relocks it.
Early movement cancels the unlock, while continuing to hold Space until you lift. An invisible margin
of about **one centimeter** absorbs stray finger contacts around the circle, just like the joystick.
A contact starting in that margin cannot become a jump or a drag, even if it drifts into the circle.

**Button Size** adjusts the keyboard buttons, including Space's surrounding ring.
**Reset Keyboard Button Positions** restores their default locations. Sizes and positions are saved
on this device and stay inside the available screen area after resizing or rotation. Hiding a held
button, resizing it, or leaving the app releases its key and cancels pending move gestures.

### Left joystick

On iPad and iPhone, drag the round joystick to send analog left-thumbstick input to the game. A small
push sends a smaller movement value, and lifting your thumb returns it to neutral. It appears as a
connected controller through Apple's GameController framework; the game must support and enable
controller input. No keyboard bindings are substituted. You can still tap the game and hold **R**
while moving.

An invisible touch shield extends about **one centimeter** beyond the joystick's edge. A finger that
lands in this margin does nothing, even if it then drifts into the joystick or onto the game. Only
touches that start beyond the shield reach the game. The shield moves with the joystick and keeps the
same width when you resize it. The **R** square stays usable if it overlaps this margin, and hardware
pointer clicks pass through the invisible margin.

Hold the small **↔** handle at the joystick's upper-right corner for **two seconds**, then drag to
reposition the whole control. Its border fills while you hold, and the arrow turns gold when unlocked.
Releasing relocks it. A quick tap or early drag does not move the control; keep your thumb still until
it unlocks. Character movement with the stick itself stays immediate.
Dragging the stick itself moves your character. The start screen's **Settings > Controls > Joystick** has
an on/off switch, a size slider, and **Reset Joystick Position**. Position and size are saved on this
device, and the control stays inside the game and safe area after resizing. Leaving the app, cancelling
a touch, or changing the size releases movement. An **!** in the stick means its controller connection
failed; turn **Left Joystick** off and on to retry.
The virtual controller connects after the game presents its first frame, so the game can see the
connection without switching away from the app.

## Signing in

The first time, Slashplayed asks for your **Battle.net email and password**. It keeps them in the
device's keychain (that device only, never synced) and signs the game in with them at every start.
If your account has an authenticator, type its code on the hardware keyboard. To sign in with another
account, tap **Forget My Sign-In** in Settings on Slashplayed's start screen (the gear).

If the device's sign-in stops working and the game is installed on the Mac, **Play with My Mac's
Battle.net** in the menu next to Play signs in through the Mac's Battle.net for that one launch. Click
the game's Play button in Battle.net when the companion asks. The companion catches the launch, moves
your Battle.net launch credentials to the device (it never reads their values), and closes the Mac's
copy of the game. Your saved sign-in stays for the next Play.

## Update Games on This Device

With this on, a device updates a game itself when Blizzard patches it, with no Mac. It's off until
you turn it on, per device, in the companion's Settings > **Updates on Devices**.

When you open a game and Blizzard has a newer build, Slashplayed says so before the game starts,
downloads the new build's game program (about 50 MB; on cellular data or in Low Data Mode it asks
first), and checks that this version of Slashplayed can run it. Tap **Update**, and a few seconds
later the new version starts and fetches the patch's data as you play. With the setting off, the
screen says to update on your Mac instead: the next Play from the companion installs the new build.

The device signs the new game program itself, so it needs a signing key from your team. Turning the
setting on says what will be sent and asks first.

- **A free Apple ID** sends a copy of the key the companion signs Slashplayed with: your team's
  Apple Development certificate and its private key. macOS asks once to allow the export.
- **A paid team** sends a certificate made only for Slashplayed, so nothing else on your Mac signs
  with it and you can revoke it on its own. Set it up once in Settings > Updates on Devices:
  1. **Make Certificate Request** saves `Slashplayed.certSigningRequest` to Downloads. Its key stays
     in a keychain of the companion's own, which Xcode never uses.
  2. On developer.apple.com, open Certificates, IDs & Profiles > Certificates, click +, choose Apple
     Development, upload the request, and download the certificate.
  3. **Choose Certificate…**, or drop it on the section. The companion checks it's for its key and
     your team.

  **Stop Using the Slashplayed Certificate** deletes it from the Mac, and each device deletes its
  copy at its next Play or Update Client. Revoke it on developer.apple.com to end it everywhere at
  once.

At every Play and Update Client, the companion checks with Apple that the certificate hasn't expired
or been revoked. If it has, nothing is sent, and the companion says what to make instead. When the
key changes, a game the device updated with the old key is signed again with the new one at its next
start; if no key on the device can sign it, the device plays the version the companion installed.

On the device, the key lives in Slashplayed's keychain only (that device only, never synced or backed
up) and signs only game programs. Turning the setting off deletes it at Slashplayed's next start;
**Forget Signing Identity** in Slashplayed's Settings deletes it at once. More in
[troubleshooting](troubleshooting.md#update-games-on-this-device).

## Game files on the device

Each game's folder is in the Files app, under On My iPad, On My iPhone, or On My Apple Vision Pro >
Slashplayed. A game's **Open in Files** in Slashplayed's Settings opens it.

- **Settings:** edit `WTF/Config.wtf`.
- **Addons:** put an addon's folder in `Interface/AddOns/`, making the folders if they aren't there.
- **Leave `Data/` and `.build.info` alone.** Deleting files there makes the game quit with
  ["installation is damaged"](troubleshooting.md#your-world-of-warcraft-installation-is-damaged).

**Bagnon** downloads automatically the first time you start a game, combining your bags into one
movable, resizable window. Drag its title bar to move it toward the center, and open its settings to
adjust scale and columns. The download includes BagBrother and the bank and configuration modules.
It is cached for later launches, including offline; a failed download lets you play and retries on
the next launch. Saved settings and WoW's AddOns enable/disable choices are preserved.

Forever includes **SPTouchBars**, installed automatically when you start the game. Open **WoW Settings >
AddOns > SPTouchBars > Edit layout**, or type `/sptouch`, to choose how many circular spell buttons appear, move and resize them, and arrange
the bottom utility bar. The new buttons start empty and use their own saved assignments: drag spells
from the spellbook, items from your bags, and macros from the macro window while editing. The normal
player action bars are hidden by default; **More... > Default bars: hidden / shown** restores them for setup.
Pet, stance, vehicle, and special-action controls stay available. Ctrl, Alt, and Shift show alternate
spells; the circular arrows button switches the main spell set. The selected icon turns teal in the
editor. Buttons have soft halos and show a gold tint when pressed. Drag any utility icon to move the
whole bar, and choose its icon count, rows, shared size, and spacing with the native sliders and steppers.
The compact inspector follows the selected control, with **Spells**, **Utility**, and **Controls** tabs.
**Border & glow** and **Visibility** open the selected group's options; **More...** holds modifier layers
and reset/clear actions. **Preview** shows the play appearance while actions remain disabled. **Undo**
restores the current editing session; **Done** keeps changes.
Separate **Interact** and **Target** controls can each be moved, resized, or turned off in Settings.
Interact follows the game's talk/loot/attack behavior; **Nearby interaction** enables detection for
touch input while the control is active. Move close and face the NPC or corpse. Target cycles
enemies (Shift cycles backward). Ctrl, Alt, and Shift each have their own layer toggle in Settings
and the editor; turn off any modifier layer you want to use for macros instead. **Quest steps** makes
Interact open, accept, continue, and turn in quests in list order, one step per press. Multiple reward
choices require a manual selection before the turn-in press. **Outline colour** opens the native colour
picker. The **Spell buttons** and **Utility bar** settings pages have separate colour, outline opacity,
and glow sliders, plus whole-bar and empty-slot visibility toggles. Empty slots hide during play by
default and return in Edit layout. The movable **Map** button toggles the world map and starts near
the minimap; **Map** and **Set arrows** have independent on/off switches. The set arrows have a
transparent background. New app
builds update the addon while keeping your saved layout. Disable it in WoW's AddOns list if you prefer
the standard bars.

## Copying game files from the Mac

If the game is installed on the Mac through Battle.net, turn on **Copy Game Files from This Mac** for
a device, and the companion copies the game's data before Play, instead of the device fetching it.
That helps on a slow connection. The first copy takes a while: Classic Era is ~25 GB, at ~33 MB/s over
the USB 2 cable an iPad or iPhone comes with (a USB 3 cable is several times faster). Later copies
send only what a patch changed.

The games share one store of data on the Mac, and Mists of Pandaria Classic's files are spread across
all of it, so copying it takes the whole store (~150 GB), though only about 23 GB is its own. Fetched
on the device, a game takes only what you've played: Classic Era is about 5 GB after 15 minutes
across three zones.

## Free Apple IDs and paid teams

A free Apple ID (a Personal Team) plays every game, with limits:

- The app's signature lasts **7 days**. The companion warns two days ahead and signs it again at the
  next Play.
- The first launch asks you to trust your Apple ID on the device.
- A free team can have only a few apps on a device.

A paid **Apple Developer Program** membership signs for a year, with none of those limits.
[Details](troubleshooting.md#free-apple-ids-personal-teams).

## Settings

- **The companion** (⌘,): team, bundle ID prefix, devices and their games, copying game files,
  updating games on devices, the game install, and update checks. Changing the team or bundle ID
  prefix makes a new app on each device, with no game files: they're fetched or copied again.
- **The device** (the gear on Slashplayed's start screen): Controls, Display, Games, Account, and About.
  iPad uses a category sidebar; narrow windows use normal back navigation. Control instructions stay
  visible below their settings. Each game's build, region, Open in Files, and Reset Game Settings are
  under Games; the saved sign-in is under Account, and the signing identity under Games > Game Updates.

All supported resolutions appear directly in WoW's **Graphics > Resolution**. On a full-screen
12.9-inch iPad Pro, the choices are **1366×1024**, **1920×1440**, **2560×1920**, and **2732×2048**.
The initial default remains the lower-power mode; once you choose another, the game remembers it
for the next launch. Existing resolution choices and older scale preferences are kept when updating.
**Settings > Display** explains the available choices with pixel dimensions and battery/detail
tradeoffs. Higher resolutions usually use more GPU power. Dimensions follow the game window's
aspect ratio and swap when you rotate into portrait. WoW's separate Render Scale slider still
controls how sharply the 3D world is rendered within the chosen resolution.

## Updates

The companion checks for its own updates (turn that off in Settings), or use **Slashplayed
Companion > Check for Updates…**. A game patch can need a new companion version: the companion then
says the game version isn't supported yet, and the device says "This patch needs a Slashplayed
update". If no update is out, the companion's **Report It…** opens a pre-filled issue.

## Known issues

- **Leaving the game for more than about 30 seconds can disconnect it**: closing its window, taking
  off the headset, or another app in front. The system suspends Slashplayed, and changes from that
  session can be lost. Use the game menu's **Exit** or **Log Out** first.
  [Details](troubleshooting.md#closing-the-window).
- **LocalDevVPN has to be on at every start.** Slashplayed's helper attaches to the game for a second
  or two to prepare its code, and reaches the device's developer services through LocalDevVPN. If
  it's off, Slashplayed opens LocalDevVPN and starts the game once it's on.
- **No on-screen keyboard in the game.** Chat and authenticator codes need a hardware keyboard.
  [Details](troubleshooting.md#no-on-screen-keyboard).
- **A mouse on an iPhone needs AssistiveTouch** for its cursor.
  [Details](troubleshooting.md#no-cursor-with-a-mouse-on-an-iphone).
- **No intro movie on a game's first launch.** On an empty device the intro never plays, so
  Slashplayed marks it seen; watch it from the game's Cinematics menu.
  [Details](troubleshooting.md#no-intro-movie).
- **A cinematic can stay black** in the game. Tap the screen, then **Yes**, to skip it.
  [Details](troubleshooting.md#a-cinematic-stays-black).
- **The window can vanish** after the headset has been off for a few minutes. Press Play again: it
  stops the running client first. [Details](troubleshooting.md#the-window-vanished).
- **Heat.** Capping the frame rate in game helps. [Details](troubleshooting.md#heat).
- **No voice chat yet.** The game shows "Can't connect to a voice chat server right now", and
  Slashplayed doesn't ask for the microphone. [Details](troubleshooting.md#no-voice-chat).
- **A game patch can break it** until Slashplayed catches up. See [Updates](#updates).

To report something else, attach the zip from **Help > Export Diagnostics…**. It leaves out your
launch credentials and blanks your devices' identifiers and personal details.
