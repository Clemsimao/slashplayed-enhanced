// Classifies macOS symbols as function or data by where the running system's copy lives.
// Usage: symkind <dylib-install-name> < symbols (one per line, with leading '_')
// Output: "<symbol> function|data|absent" per line.
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <stdio.h>
#include <string.h>

static const char *kind_of(const void *p) {
  Dl_info info;
  if (!dladdr(p, &info) || !info.dli_fbase) return "data";
  const struct mach_header_64 *mh = info.dli_fbase;
  const struct load_command *lc = (const void *)(mh + 1);
  intptr_t slide = 0;
  for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64 *seg = (const void *)lc;
    if (!strcmp(seg->segname, "__TEXT")) slide = (intptr_t)mh - (intptr_t)seg->vmaddr;
  }
  uintptr_t addr = (uintptr_t)p - slide;
  lc = (const void *)(mh + 1);
  for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64 *seg = (const void *)lc;
    const struct section_64 *sect = (const void *)(seg + 1);
    for (uint32_t j = 0; j < seg->nsects; j++, sect++) {
      if (addr >= sect->addr && addr < sect->addr + sect->size)
        return (sect->flags & S_ATTR_PURE_INSTRUCTIONS) ? "function" : "data";
    }
  }
  return "data";
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  void *h = dlopen(argv[1], RTLD_LAZY);
  if (!h) { fprintf(stderr, "%s\n", dlerror()); return 1; }
  char line[1024];
  while (fgets(line, sizeof line, stdin)) {
    line[strcspn(line, "\n")] = 0;
    if (line[0] != '_') continue;
    void *p = dlsym(h, line + 1);
    printf("%s %s\n", line, p ? kind_of(p) : "absent");
  }
  return 0;
}
