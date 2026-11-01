# metaltest: macOS metallibs on visionOS and iPadOS

The game client's shader libraries are built for macOS, and the device refused them with
`MTLLibraryErrorDomain Code=1 "This library format is not supported on this platform"`. This harness
finds out why and whether a header edit fixes it, using **our own** shader only
(`sptest.metal`); it never reads the game's libraries. Background:
[docs/research.md](../../docs/research.md#metal-shader-libraries-metaltest).

- `sptest.metal`: a compute kernel (`sptest`) and a vertex/fragment pair (`spvert`/`spfrag`).
- `build.sh`: compiles it for the device (controls) and for macOS at deployment targets 10.11 to 14
  (which pick metallib container versions v2.2 to v2.7), makes a copy of each macOS build with the
  header's macOS flag cleared, bundles them all into `SPMetalTest.app/libs/`, signs and installs.
- `main.m`: for each library, `-[MTLDevice newLibraryWithData:error:]`, a compute dispatch over 256
  threads checking `out[i] == i*3 + 0x1234` and `fout[i] == sqrt(i)*0.5 + 1`, then a textured
  fullscreen triangle into an 8x8 target checking every pixel. Exits in about a second.
- `mtlb.py`: `dump FILE` prints a container's header, function list, bitcode hashes and AIR triple;
  `retag IN OUT` clears the macOS flag.

## Running it

Needs a paired device in Developer Mode, Xcode with the Metal toolchain
(`xcodebuild -downloadComponent MetalToolchain`), `config/local.env`, and a profile from
`apps/client/signing/regen.sh <device UDID>`.

```sh
research/metaltest/build.sh                 # build, retag, sign, install SPMetalTest (com.strawdynamics.spmetaltest)
research/metaltest/run.sh                   # run it and print load / compute / render results per library
SP_PLATFORM=ios research/metaltest/build.sh # the same on an iPad
python3 research/metaltest/mtlb.py dump research/metaltest/out/lib/b-mac11.0.metallib
```

## Results

Identical on Vision Pro (visionOS 27) and iPad Pro M2 (iPadOS 26.6):

| macOS deployment target | Container | As built | macOS flag cleared |
|---|---|---|---|
| 10.11 – 11.0 | v2.2 – v2.5 (no platform field) | Code=1 | loads; compute and render correct |
| 12.0 – 14.0 | v2.6 – v2.7 (platform field) | loads; correct | loads; correct |

The device rejects a library only when bit 15 of the 16-bit target field at offset 4 (the macOS flag)
is set **and** the container predates the platform field added in v2.6. Clearing that one bit is
enough; no hash, UUID or bitcode change is needed, and the AIR triple naming macOS is accepted. The
Metal shim applies this to a copy of each library the client loads.
