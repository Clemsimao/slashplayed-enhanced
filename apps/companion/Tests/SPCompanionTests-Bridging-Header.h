// The launcher's own code the tests run on the Mac (apps/client: Foundation only): its CDN client, its
// bind check, and its assembly, against the companion's BlizzardCDN, BindCheck, and ClientAssembly, and
// its signer.
#import "../../client/spassemble.h"
#import "../../client/spbind.h"
#import "../../client/spcdn.h"
#import "../../client/spaddons.h"
#import "../../client/spsign.h"
// spzsign.cpp's entry (spsign.m declares it for itself): DeviceSigningTests reads zsign's messages from it.
int sp_zsign(const char *path, const char *identifier, const void *p12, size_t p12_len, const char *password,
             const void *profile, size_t profile_len, int logfd);
// The start screen's logo paths (spstartscreen.swift draws them), which StartScreenLogoTests checks against the app icon.
#import "../../client/splogo.h"
