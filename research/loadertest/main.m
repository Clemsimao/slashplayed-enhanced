// Phase 2 loader proof: a macOS AppKit program, built against the macOS SDK like the client, whose
// load commands are then rewritten (shims/generated/rewrite-map.txt) to run on visionOS over the
// shims. refs.c (gen_refs.py) imports every symbol the client imports, from the same library, so
// reaching main() on the device means dyld bound the client's whole import table.
// Results go to stdout and Documents/sploader.log ($SP_LOADER_LOG overrides; the Mac run uses it).
#import <AppKit/AppKit.h>
#import <GameController/GameController.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <sys/mman.h>
#include <unistd.h>

extern const void *const sp_refs[];
extern const char *const sp_ref_names[];
extern const size_t sp_ref_count;

static int logfd = -1;
static int failures;

static void say(const char *fmt, ...) {
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof buf, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof buf - 1) n = sizeof buf - 1;
    write(1, buf, n);
    if (logfd >= 0) {
        write(logfd, buf, n);
        fsync(logfd);
    }
}

static void check(int ok, const char *what) {
    say("%s %s\n", ok ? "ok  " : "FAIL", what);
    if (!ok) failures++;
}

// The client subclasses these five (its OBJC_METACLASS_$ imports); on visionOS all are stubs.
@interface SPApplication : NSApplication
- (int)spPing;
@end
@implementation SPApplication
- (int)spPing { return 42; }
@end
@interface SPResponder : NSResponder
@end
@implementation SPResponder
@end
@interface SPView : NSView
- (int)spPing;
@end
@implementation SPView
- (int)spPing { return 43; }
@end
@interface SPWindow : NSWindow
@end
@implementation SPWindow
@end
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@interface SPGLContext : NSOpenGLContext
@end
@implementation SPGLContext
@end
#pragma clang diagnostic pop

static void superchain(Class c) {
    char buf[256] = "";
    for (; c; c = class_getSuperclass(c)) {
        strlcat(buf, class_getName(c), sizeof buf);
        if (class_getSuperclass(c)) strlcat(buf, " < ", sizeof buf);
    }
    say("     %s\n", buf);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        const char *path = getenv("SP_LOADER_LOG");
        char buf[1024];
        if (!path) {
            snprintf(buf, sizeof buf, "%s/Documents/sploader.log", getenv("HOME"));
            path = buf;
        }
        logfd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        say("=== sploader (pid %d) %s\n", getpid(),
            NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String);

        // 1. Every client import bound. Only the client's weak imports may be NULL.
        size_t null = 0;
        for (size_t i = 0; i < sp_ref_count; i++)
            if (!sp_refs[i]) {
                say("     NULL %s\n", sp_ref_names[i]);
                null++;
            }
        snprintf(buf, sizeof buf, "%zu/%zu imports bound (%zu NULL)", sp_ref_count - null, sp_ref_count,
                 null);
        check(1, buf);

        // 2. libSystem shim: dlsym hides the JIT toggle and hands out its own mprotect/memcpy.
        check(dlsym(RTLD_DEFAULT, "pthread_jit_write_protect_np") == NULL,
              "dlsym(pthread_jit_write_protect_np) == NULL");
        void *dm = dlsym(RTLD_DEFAULT, "mprotect"), *dc = dlsym(RTLD_DEFAULT, "memcpy");
        say("     dlsym mprotect %p (bound %p), memcpy %p (bound %p)\n", dm, (void *)mprotect, dc,
            (void *)memcpy);
        check(dm && dc, "dlsym(mprotect/memcpy) non-NULL");

        // 3. Subclasses of the stubbed AppKit classes realize and dispatch.
        for (Class c in @[ SPApplication.class, SPResponder.class, SPView.class, SPWindow.class,
                           SPGLContext.class ])
            superchain(c);
        // The stub has no +sharedApplication (it's forwarded and returns nil); real AppKit makes one.
        SPApplication *app = (SPApplication *)[SPApplication sharedApplication];
        say("     [SPApplication sharedApplication] = %p\n", app);
        if (!app) app = [[SPApplication alloc] init];
        check(app.spPing == 42, "SPApplication spPing");
        SPView *view = [[SPView alloc] init];
        check(view && [view spPing] == 43, "[[SPView alloc] init] spPing");
        [view setNeedsDisplay:YES];  // stubbed: logged and ignored

        // 4. Real frameworks through re-exporting shims and direct paths.
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        say("     Metal device: %s\n", dev ? dev.name.UTF8String : "(none)");
        check(dev != nil, "MTLCreateSystemDefaultDevice");
        say("     GCController.controllers: %lu\n", (unsigned long)GCController.controllers.count);
        CFStringRef bid = CFBundleGetIdentifier(CFBundleGetMainBundle());
        say("     main bundle: %s\n", bid ? CFStringGetCStringPtr(bid, kCFStringEncodingUTF8) : "(none)");
        say("     NSColor.redColor: %s\n", object_getClassName(NSColor.redColor));

        say("=== done, %d failure(s)\n", failures);

        // SP_LOADER_LOOP=<s>: pump events like the client's main loop (the AppKit shim runs UIKit from
        // sharedApplication above and nextEventMatchingMask:... below).
        int loop = getenv("SP_LOADER_LOOP") ? atoi(getenv("SP_LOADER_LOOP")) : 0;
        NSDate *start = [NSDate date];
        for (int frames = 0, next = 0; -start.timeIntervalSinceNow < loop; frames++) {
            @autoreleasepool {
                [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:nil inMode:NSDefaultRunLoopMode
                                     dequeue:YES];
                if (-start.timeIntervalSinceNow >= next) {
                    say("     looping %d s, %d frames\n", next, frames);
                    next += 5;
                }
            }
            usleep(16000);
        }

        // SP_LOADER_SLEEP=<s>: stay alive without UIApplicationMain, to see whether visionOS kills an
        // app that never brings up a scene, and when.
        int nap = getenv("SP_LOADER_SLEEP") ? atoi(getenv("SP_LOADER_SLEEP")) : 0;
        for (int t = 0; t < nap; t += 5) {
            say("     alive %d s\n", t);
            sleep(5);
        }
    }
    return failures ? 1 : 0;
}
