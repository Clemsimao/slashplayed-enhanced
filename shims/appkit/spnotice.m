// CFUserNotification: the Mac's out-of-process alert, which the client uses for one thing, its
// progress dialog while it sets up game data that isn't on disk yet (an empty or partial store, or a
// build whose content it has to stream first). The dialog has one button, Cancel; the client shows it
// with a run loop source for the response, hides its window, streams, updates the progress, and
// cancels the dialog itself when it's done. A Cancel response means the person gave up, and the client
// quits so "the Launcher" can finish the install.
// iOS and visionOS have no alert server for apps: the real CFUserNotificationCreate returns a
// notification whose response arrives at once as kCFUserNotificationCancelResponse, so the client quit
// a few seconds into every launch that had data to fetch. Here the notification is the shim's own
// object and nobody answers it: the progress is logged, the run loop source never fires, and the
// client's own Cancel takes it down. The progress goes to the loading screen (the AppKit shim's
// sploading.m) as an SPDataSetupProgress notification, a number only: the dialog's text isn't shown.
// #included at the end of the generated libspCoreFoundation.m (gen_stubs.py EXTRA_INCLUDES);
// __asm__("_symbol") wins over the shim's re-export of CoreFoundation.

// The dictionary keys' values (kCFUserNotificationAlertHeaderKey and the message key are macOS-only in
// the iOS SDK, but the client passes the strings).
#define SP_NOTICE_HEADER @"AlertHeader"
#define SP_NOTICE_MESSAGE @"AlertMessage"

// The header is the percentage ("37%"). -1 if it isn't one.
static int sp_notice_percent(CFDictionaryRef dict) {
    NSString *header = ((__bridge NSDictionary *)dict)[SP_NOTICE_HEADER];
    return [header isKindOfClass:[NSString class]] && header.length ? MAX(header.intValue, 0) : -1;
}

// To the loading screen, if there is one (no observer otherwise). -1: the setup is over.
static void sp_notice_progress(int percent) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"SPDataSetupProgress" object:nil
                                                    userInfo:@{@"percent": @(percent)}];
}

// The notification: a copy of what the client asked for, which gives it a CF type to retain and release.
CFUserNotificationRef sp_notice_create(CFAllocatorRef alloc, CFTimeInterval timeout, CFOptionFlags flags,
                                              SInt32 *error, CFDictionaryRef dict)
    __asm__("_CFUserNotificationCreate");
CFUserNotificationRef sp_notice_create(CFAllocatorRef alloc, CFTimeInterval timeout, CFOptionFlags flags,
                                              SInt32 *error, CFDictionaryRef dict) {
    NSDictionary *d = (__bridge NSDictionary *)dict;
    sp_stub_log([NSString stringWithFormat:@"CFUserNotificationCreate: \"%@\" / \"%@\" (no alert server here: "
                                            "shown to nobody, never answered)",
                 d[SP_NOTICE_HEADER],
                 d[SP_NOTICE_MESSAGE]].UTF8String);
    if (error) *error = 0;
    sp_notice_progress(sp_notice_percent(dict));
    return (CFUserNotificationRef)CFDictionaryCreateCopy(alloc, dict);
}

// Progress: logged when it changes by 10 points or more, and shown on the loading screen.
SInt32 sp_notice_update(CFUserNotificationRef note, CFTimeInterval timeout, CFOptionFlags flags,
                               CFDictionaryRef dict) __asm__("_CFUserNotificationUpdate");
SInt32 sp_notice_update(CFUserNotificationRef note, CFTimeInterval timeout, CFOptionFlags flags,
                               CFDictionaryRef dict) {
    static int logged = -100;
    int percent = sp_notice_percent(dict);
    if (percent < 0 || percent >= logged + 10 || percent < logged) {
        logged = percent;
        sp_stub_log([NSString stringWithFormat:@"CFUserNotificationUpdate: \"%@\"",
                     ((__bridge NSDictionary *)dict)[SP_NOTICE_HEADER]].UTF8String);
    }
    if (percent >= 0) sp_notice_progress(percent);
    return 0;
}

SInt32 sp_notice_cancel(CFUserNotificationRef note) __asm__("_CFUserNotificationCancel");
SInt32 sp_notice_cancel(CFUserNotificationRef note) {
    sp_stub_log("CFUserNotificationCancel (the client's own: its setup is done)");
    sp_notice_progress(-1);
    return 0;
}

// A source that's never signalled: the response it would deliver is the person's, and there's no one.
static void sp_notice_perform(void *info) {}
CFRunLoopSourceRef sp_notice_source(CFAllocatorRef alloc, CFUserNotificationRef note,
                                           CFUserNotificationCallBack callout, CFIndex order)
    __asm__("_CFUserNotificationCreateRunLoopSource");
CFRunLoopSourceRef sp_notice_source(CFAllocatorRef alloc, CFUserNotificationRef note,
                                           CFUserNotificationCallBack callout, CFIndex order) {
    CFRunLoopSourceContext context = {.perform = sp_notice_perform};
    return CFRunLoopSourceCreate(alloc, order, &context);
}

// A blocking wait for the response: none comes. With a timeout, wait it out and report the timeout as
// the real call does; with none (wait forever), report failure at once rather than hang the caller.
SInt32 sp_notice_receive(CFUserNotificationRef note, CFTimeInterval timeout, CFOptionFlags *response)
    __asm__("_CFUserNotificationReceiveResponse");
SInt32 sp_notice_receive(CFUserNotificationRef note, CFTimeInterval timeout, CFOptionFlags *response) {
    sp_stub_log([NSString stringWithFormat:@"CFUserNotificationReceiveResponse(timeout %g): no response", timeout]
                    .UTF8String);
    if (timeout > 0) [NSThread sleepForTimeInterval:timeout];
    return -1;
}
