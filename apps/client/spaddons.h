// Optional addons fetched directly from their publisher, before the game loads. Nothing is fetched
// after a valid package is cached; a failure is logged and never prevents playing the game.
#import "spcdn.h"

NS_ASSUME_NONNULL_BEGIN
BOOL sp_bagnon_place(NSString *cache, NSString *game, NSString *flavor, SPFetch fetch, NSString *_Nullable *_Nonnull line);

// Shared package installer, also exercised with made-up ZIPs in the companion tests. SHA-256 is pinned
// by the caller. Only files under `names` are accepted, with every <name>/<name>.toc required. All bytes
// are checked before writing anything, and identical installed files keep their modification dates.
BOOL sp_addon_download(NSString *cache, NSString *game, NSURL *url, NSString *sha256,
                       NSArray<NSString *> *names, SPFetch fetch, NSString *_Nullable *_Nonnull line);
NS_ASSUME_NONNULL_END
