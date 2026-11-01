// Assembly on the device (spassemble.m): a client's thin arm64 slice made into the unsigned client image,
// byte for byte what the Mac's tools make of it (the companion's ClientAssembly.prepareClient and
// apps/client/build.sh). Foundation only, so the companion's tests build it for the Mac too and compare it
// with theirs.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The unsigned client image from `slice` (a thin 64-bit MH_EXECUTE, as spcdn.m's sp_cdn_slice writes it):
// what `install_name_tool` with every `-change` of `rewriteMap` (rewrite-map.txt's text: "<from> -> <to>"
// per line) and `-add_rpath @executable_path/Frameworks`, then `vtool -set-build-version <platform>
// <minOS> <minOS> -replace`, then the retype (retype.py, MachO.retype) write. `platform` is LC_BUILD_VERSION's
// (PLATFORM_IOS, PLATFORM_VISIONOS) and `minOS` its xxxx.yy.zz encoding (26.0 is 0x1A0000). Only the
// header and its load commands change; the slice's LC_CODE_SIGNATURE and its bytes are kept as they are,
// no longer valid, as the tools leave them (signing replaces them). *changes gets a line per section the
// retype changed, as MachO.retype words them. nil and *problem when the tools would refuse it too (the
// commands don't fit, the rpath is already there), when it isn't a slice this reads, or when its signature
// is only the linker's (the tools re-sign those, and this doesn't: a shipped client's never is).
NSData *_Nullable sp_assemble(NSData *slice, NSString *rewriteMap, uint32_t platform, uint32_t minOS,
                              NSArray<NSString *> *_Nullable *_Nullable changes, NSString *_Nullable *_Nullable problem);

NS_ASSUME_NONNULL_END
