// The bind check on the device (spbind.m): a client image's imports, read from its Mach-O, against the
// exports.json the app carries. Foundation only, so the companion's tests build it for the Mac too
// (apps/companion/Tests: against BindCheck's results).
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The imports of a thin 64-bit Mach-O (arm64): each unique (install name, symbol) the image binds to, in
// the order its fixups first name them, less weak imports (they bind to NULL when missing, and BindCheck
// skips them too). Both kinds of fixup info: LC_DYLD_INFO's bind opcodes (the clients) and
// LC_DYLD_CHAINED_FIXUPS' imports table (what today's linker writes). An import from no
// particular library (flat or weak lookup, the image itself) is named <flat>, <weak>, <self>, or
// <executable>. nil and *problem when it isn't an image this reads.
NSArray<NSArray<NSString *> *> *_Nullable sp_bind_imports(NSData *image, NSString *_Nullable *_Nullable problem);

// The imports of `image` that `exports` (exports.json's bytes) doesn't provide, as "<library> <symbol>"
// with the library's short name (AppKit, libSystem), as the companion's BindCheck.Unresolved writes
// them. *total is the number of imports. nil and *problem when either can't be read. `withheld`: symbols
// treated as provided by nothing (the patch drill, sppatch.m), as BindCheck.Manifest's: one the image
// imports is reported under its library, and one it doesn't as "patch drill <symbol>", after the rest.
NSArray<NSString *> *_Nullable sp_bind_unresolved(NSData *image, NSData *exports, NSSet<NSString *> *_Nullable withheld,
                                                  NSUInteger *total, NSString *_Nullable *_Nullable problem);

NS_ASSUME_NONNULL_END
