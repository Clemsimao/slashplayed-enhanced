// Play-session stats for triage. #included in the generated libspAppKit.m (gen_stubs.py
// EXTRA_INCLUDES), before sphover.m, whose present hooks call sp_stats_frame.
//
// Every 30 s one line: frames presented and the worst gap between two, how many gaps ran over 50 ms,
// the footprint jetsam counts (and its peak), what's left before the app's limit, and the thermal
// state. Lifecycle changes (scene activation, background, memory warnings, thermal and low-power
// changes) are logged as they happen. With SP_HOVER_OFF=1 the presents aren't hooked and fps reads 0.
// For the heat: CPU (the process's threads, summed, and the busiest three by name) and GPU (the time
// each committed command buffer spent on the GPU, summed over the 30 s; overlaps count twice).
#import <Metal/Metal.h>
#include <mach/mach.h>
#include <stdatomic.h>
#include <time.h>

extern size_t os_proc_available_memory(void);

// Its own lines, "[sp:AppKit] stats: …" and "[sp:AppKit] lifecycle: …", as sploading.m's: not through
// sp_stub_log, whose "stub hit:" is for the client's calls into stubs, which these aren't.
static void sp_stats_say(const char *s) {
    os_log(OS_LOG_DEFAULT, "[sp:AppKit] %{public}s", s);
    fprintf(stderr, "[sp:AppKit] %s\n", s);
}

static _Atomic uint64_t sp_stats_frames, sp_stats_slow, sp_stats_worst_ns, sp_stats_last_ns;

static void sp_stats_frame(void) {
    uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    uint64_t last = atomic_exchange(&sp_stats_last_ns, now);
    sp_stats_frames++;
    if (!last) return;
    uint64_t gap = now - last;
    if (gap > 50000000) sp_stats_slow++;
    uint64_t worst = sp_stats_worst_ns;
    while (gap > worst && !atomic_compare_exchange_weak(&sp_stats_worst_ns, &worst, gap)) {}
}

static _Atomic uint64_t sp_stats_gpu_ns, sp_stats_cbs;
static void (*sp_stats_commit_orig)(id, SEL);

static void sp_stats_commit(id<MTLCommandBuffer> cb, SEL _cmd) {
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
        CFTimeInterval t = done.GPUEndTime - done.GPUStartTime;
        if (t > 0 && t < 10) sp_stats_gpu_ns += (uint64_t)(t * 1e9);
        sp_stats_cbs++;
    }];
    sp_stats_commit_orig(cb, _cmd);
}

// Called from sp_hover_attach with the device's command buffer class, the same one the client's are.
static void sp_stats_hook_gpu(Class c) {
    static BOOL done;
    Method m = done ? NULL : class_getInstanceMethod(c, @selector(commit));
    if (!m) return;
    done = YES;
    sp_stats_commit_orig = (void *)method_setImplementation(m, (IMP)sp_stats_commit);
}

// CPU use of the process (100 = one core), and its busiest three threads, from the scheduler's
// decaying per-thread usage.
static NSString *sp_stats_cpu(void) {
    thread_act_array_t threads;
    mach_msg_type_number_t n;
    if (task_threads(mach_task_self(), &threads, &n) != KERN_SUCCESS) return @"cpu ?";
    struct { int usage; char name[64]; } top[3] = {{0}};
    int total = 0;
    for (mach_msg_type_number_t i = 0; i < n; i++) {
        thread_extended_info_data_t info;
        mach_msg_type_number_t count = THREAD_EXTENDED_INFO_COUNT;
        if (thread_info(threads[i], THREAD_EXTENDED_INFO, (thread_info_t)&info, &count) == KERN_SUCCESS) {
            total += info.pth_cpu_usage;
            for (int k = 0; k < 3; k++) {
                if (info.pth_cpu_usage <= top[k].usage) continue;
                memmove(&top[k + 1], &top[k], sizeof top[0] * (2 - k));
                top[k].usage = info.pth_cpu_usage;
                snprintf(top[k].name, sizeof top[k].name, "%s", info.pth_name[0] ? info.pth_name : "?");
                break;
            }
        }
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads, n * sizeof *threads);
    NSMutableString *out = [NSMutableString stringWithFormat:@"cpu %d%% (%u threads:", total * 100 / TH_USAGE_SCALE, n];
    for (int k = 0; k < 3 && top[k].usage; k++)
        [out appendFormat:@"%s %s %d%%", k ? "," : "", top[k].name, top[k].usage * 100 / TH_USAGE_SCALE];
    [out appendString:@")"];
    return out;
}

static const char *sp_stats_thermal(void) {
    switch (NSProcessInfo.processInfo.thermalState) {
    case NSProcessInfoThermalStateNominal: return "nominal";
    case NSProcessInfoThermalStateFair: return "fair";
    case NSProcessInfoThermalStateSerious: return "SERIOUS";
    case NSProcessInfoThermalStateCritical: return "CRITICAL";
    }
    return "?";
}

// Footprint (and its peak), what's left before the limit, thermal state.
static NSString *sp_stats_state(void) {
    task_vm_info_data_t vm;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &count) != KERN_SUCCESS) memset(&vm, 0, sizeof vm);
    return [NSString stringWithFormat:@"footprint %llu MB (peak %llu), %zu MB left | thermal %s%s",
        vm.phys_footprint >> 20, vm.ledger_phys_footprint_peak >> 20, os_proc_available_memory() >> 20,
        sp_stats_thermal(), NSProcessInfo.processInfo.lowPowerModeEnabled ? ", low power" : ""];
}

static void sp_stats_line(double secs) {
    uint64_t frames = atomic_exchange(&sp_stats_frames, 0), slow = atomic_exchange(&sp_stats_slow, 0);
    uint64_t worst = atomic_exchange(&sp_stats_worst_ns, 0);
    uint64_t gpu = atomic_exchange(&sp_stats_gpu_ns, 0), cbs = atomic_exchange(&sp_stats_cbs, 0);
    sp_stats_say([NSString stringWithFormat:@"stats: %.1f fps, worst %llu ms, %llu over 50 ms | gpu %.0f%% (%.1f ms/frame, "
                 "%llu buffers) | %@ | %@", frames / secs, worst / 1000000, slow, gpu / (secs * 1e7),
                 frames ? gpu / 1e6 / frames : 0.0, cbs, sp_stats_cpu(), sp_stats_state()].UTF8String);
}

// Every scene, its state, and its windows (hidden, alpha, frame), for app and scene events: once the
// window vanished after the headset was off a while, though the scene reported active.
static NSString *sp_stats_scenes(void) {
    static const char *states[] = {"foreground active", "foreground inactive", "background"};
    NSMutableString *out = [NSMutableString string];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        long st = scene.activationState;
        [out appendFormat:@"\n    scene %p %s, session %@", scene, st >= 0 && st <= 2 ? states[st] : "unattached",
                          [scene.session.persistentIdentifier substringToIndex:8]];
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows)
            [out appendFormat:@"\n      window %p%s%s alpha %.2f frame %@ layer sublayers %lu", w,
                              w.hidden ? " HIDDEN" : "", w.isKeyWindow ? " key" : "", w.alpha,
                              NSStringFromCGRect(w.frame), (unsigned long)w.rootViewController.view.layer.sublayers.count];
    }
    return out.length ? out : @"\n    no connected scenes";
}

static void *sp_stats_watch(void *unused) {
    (void)unused;
    uint64_t last = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    for (;;) {
        sleep(30);
        uint64_t now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        @autoreleasepool { sp_stats_line((now - last) / 1e9); }
        last = now;
    }
    return NULL;
}

static void sp_stats_start(void) {
    static BOOL started;
    if (started) return;
    started = YES;
    pthread_t t;
    pthread_create(&t, NULL, sp_stats_watch, NULL);
    pthread_detach(t);
    NSSet *thermal = [NSSet setWithObjects:NSProcessInfoThermalStateDidChangeNotification,
                                           NSProcessInfoPowerStateDidChangeNotification, nil];
    NSDictionary<NSNotificationName, NSString *> *events = @{
        UIApplicationWillResignActiveNotification: @"app will resign active",
        UIApplicationDidBecomeActiveNotification: @"app did become active",
        UIApplicationDidEnterBackgroundNotification: @"app entered background",
        UIApplicationWillEnterForegroundNotification: @"app will enter foreground",
        UIApplicationDidReceiveMemoryWarningNotification: @"MEMORY WARNING",
        UIApplicationWillTerminateNotification: @"app will terminate",
        UISceneWillConnectNotification: @"scene will connect",
        UISceneDidDisconnectNotification: @"scene disconnected",
        UISceneDidActivateNotification: @"scene activated",
        UISceneWillDeactivateNotification: @"scene will deactivate",
        UISceneDidEnterBackgroundNotification: @"scene entered background",
        UISceneWillEnterForegroundNotification: @"scene will enter foreground",
        NSProcessInfoThermalStateDidChangeNotification: @"thermal state changed",
        NSProcessInfoPowerStateDidChangeNotification: @"low power mode changed",
    };
    for (NSNotificationName name in events) {
        NSString *what = events[name];
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                    usingBlock:^(NSNotification *note) {
            sp_stats_say([NSString stringWithFormat:@"lifecycle: %@ | %@%@", what, sp_stats_state(),
                         [thermal containsObject:name] ? @"" : sp_stats_scenes()].UTF8String);
        }];
    }
}
