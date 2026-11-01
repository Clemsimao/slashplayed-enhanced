// Writes the small identity file login needs from the Mac: the Mac user's login name (getpwuid; what
// NSUserName() returns on the Mac), no NUL, which the device's NSUserName() answers with for the
// client (spfoundation.m). The device reads it from <container>/Library/spidentity. The companion
// writes the same bytes itself (MacIdentity in apps/companion/Sources/GameStore.swift). Prints size and
// hash only (spident.h's FNV-1a). Build and run:
//   clang -o <scratch>/mac-identity shims/ident/mac-identity.c
//   <scratch>/mac-identity <scratch>/spidentity
#include <pwd.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return fprintf(stderr, "usage: %s <out>\n", argv[0]), 2;
    struct passwd *pw = getpwuid(getuid());
    if (!pw || !*pw->pw_name) return fprintf(stderr, "no user name\n"), 1;
    size_t n = strlen(pw->pw_name);
    unsigned h = 2166136261u;
    for (size_t i = 0; i < n; i++) h = (h ^ (unsigned char)pw->pw_name[i]) * 16777619u;
    FILE *f = fopen(argv[1], "wb");
    if (!f || fwrite(pw->pw_name, 1, n, f) != n || fclose(f)) return perror(argv[1]), 1;
    printf("user name %zu chars #%08x\n", n, h);
    return 0;
}
