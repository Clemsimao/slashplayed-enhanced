// Gives libspSystem the real dlsym, which it shadows. A separate image, because a call to dlsym
// from inside libspSystem would bind to its own definition.
#include <dlfcn.h>
void *sp_real_dlsym(void *handle, const char *sym) { return dlsym(handle, sym); }
