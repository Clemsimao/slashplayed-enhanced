# loadertest: a macOS program on the device's dyld

A toy macOS AppKit program, built against the macOS SDK with the client's deployment target (so its
fixups have the same format), that imports every symbol the game client imports, each from the same
library, and subclasses the same AppKit classes. Its load commands are rewritten with the shims'
rewrite map, its platform is set with `vtool`, and the shims are bundled, exactly as the companion
does for the real client. If it reaches `main()` on the device, dyld bound the client's whole import
table. It also checks what the shims hand out (`dlsym`, stub classes, Metal, `NSColor`). Background:
[docs/research.md](../../docs/research.md#loading-a-macos-program-loadertest).

This is the model for test fixtures: a program of our own with the client's import shape, never the
client itself.

- `main.m`: the toy. Logs to stdout and `Documents/sploader.log` (`SP_LOADER_LOG` overrides it).
- `gen_refs.py`: writes `out/refs.c`, which references every imported symbol by name. It reads only
  names from the client (its imports and which are weak; `build.sh` also reads its library list),
  never code or data.

## Running it

Needs your own installed Classic Era client, thinned to `work/wow-arm64`
(`lipo -thin arm64 -output work/wow-arm64 "<install>/_classic_era_/World of Warcraft Classic.app/Contents/MacOS/World of Warcraft Classic"`),
and its import record from `scripts/recon/regen.sh <platform>` (in `work/regen/<platform>/classic_era/`).
For the device: a paired device in Developer Mode, `config/local.env`, and a profile from
`apps/client/signing/regen.sh <device UDID>`.

```sh
research/loadertest/build.sh mac        # build the toy and run it on the Mac, libSystem through the macOS shim build
research/loadertest/build.sh            # rewrite, bundle the shims, sign, install SPLoader (com.strawdynamics.sploader)
xcrun devicectl device process launch --device <UDID> --terminate-existing --console com.strawdynamics.sploader
SP_PLATFORM=ios research/loadertest/build.sh   # the same on an iPad
```

The toy honours `SP_LOADER_SLEEP=<s>` (sit without UIKit, to see the launch watchdog) and
`SP_LOADER_LOOP=<s>` (pump events through the AppKit shim's UIKit coroutine); pass them to the device
with a `DEVICECTL_CHILD_` prefix.

## Results

On Vision Pro (visionOS 27) and iPad Pro M2 (iPadOS 26.6): dyld binds all 1,062 references (none
NULL, 2 weak); `dlsym` hides `pthread_jit_write_protect_np` and hands out the shim's
`mprotect`/`memcpy`; subclasses of stub `NSApplication`, `NSView`, `NSWindow`, `NSResponder` and
`NSOpenGLContext` realize and dispatch; Metal finds the M2 GPU; `NSColor.redColor` comes back as
UIKit's. Exit 0, no debugger needed.

- Today's macOS SDK no longer exports `exp2`/`log2`/`modff` from CoreServices, where the client binds
  them, so the toy links against a patched copy of `CoreServices.tbd`.
- `SP_LOADER_SLEEP=120` was killed with signal 9 about 21 s after launch, with no crash report: the
  launch watchdog wants a UIKit scene. `SP_LOADER_LOOP=60` pumped at ~59 fps for 60 s through the
  coroutine.
