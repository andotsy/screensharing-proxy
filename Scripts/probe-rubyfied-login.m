// Appended to the real transport source in an isolated, ad-hoc-signed copy.
// Only the synthetic peer receives the fixed dummy password. No keychain reads
// or writes, accessibility grants, original-viewer termination or real login.
static BOOL fixtureSubmitted;
static void (*fixtureReadyOriginal)(id, SEL);

static void fixtureFields(NSView *view, NSMutableArray *fields, NSMutableArray *buttons) {
    if ([view isKindOfClass:NSTextField.class] && [(NSTextField *)view isEditable]) [fields addObject:view];
    if ([view isKindOfClass:NSButton.class]) [buttons addObject:view];
    for (NSView *child in view.subviews) fixtureFields(child, fields, buttons);
}

static void fixtureReady(id session, SEL selector) {
    fixtureReadyOriginal(session, selector);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{
        BOOL desktop = NO;
        for (NSWindow *window in NSApp.windows) {
            if (window.visible && [window.title isEqual:@"Rubyfied synthetic login fixture"]) desktop = YES;
        }
        fprintf(stderr, "RUBIED_LOGIN_FIXTURE desktop=%d submitted=%d\n", desktop, fixtureSubmitted);
        stopRelay();
        dispatch_sync(eventQueue, ^{});
        _exit(desktop && fixtureSubmitted ? 0 : 1);
    });
}

static void *fixtureNoKeychain(id self, SEL selector, id type, id account, id *name) {
    (void)self; (void)selector; (void)type; (void)account; (void)name;
    return NULL;
}
static void fixtureNoSave(id self, SEL selector) { (void)self; (void)selector; }

__attribute__((constructor)) static void fixtureLogin(void) {
    @autoreleasepool {
        // The ordinary UI runs; only transport fixture ports are overridden.
        probeMode = YES;
        mediaBase = FIXTURE_MEDIA_BASE;
        probeRemoteBase = FIXTURE_MEDIA_BASE + 3;
        listenerPort = FIXTURE_LISTENER_PORT;
        Class view = NSClassFromString(@"SSSessionView");
        Method keychain = class_getInstanceMethod(view,
            NSSelectorFromString(@"findCredentialInKeychainForAuthType:inRequestedAccountName:outAccountName:"));
        Method save = class_getInstanceMethod(view, NSSelectorFromString(@"saveCredentialsToKeychain"));
        Method ready = class_getInstanceMethod(NSClassFromString(@"SSSession"), NSSelectorFromString(@"delegateSessionReady"));
        if (!keychain || !save || !ready) _exit(2);
        method_setImplementation(keychain, (IMP)fixtureNoKeychain);
        method_setImplementation(save, (IMP)fixtureNoSave);
        fixtureReadyOriginal = (void *)method_setImplementation(ready, (IMP)fixtureReady);
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
            object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
                [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(__unused NSTimer *timer) {
                    if (fixtureSubmitted) return;
                    for (NSWindow *window in NSApp.windows) {
                        if (!window.visible) continue;
                        NSMutableArray *fields = [NSMutableArray new], *buttons = [NSMutableArray new];
                        fixtureFields(window.contentView, fields, buttons);
                        BOOL secure = NO;
                        for (NSTextField *field in fields) secure |= [field isKindOfClass:NSSecureTextField.class];
                        if (!secure || fields.count > 2) continue;
                        NSButton *submit = nil;
                        for (NSButton *button in buttons) {
                            if ([button.title isEqual:@"Remember password"]) button.state = NSControlStateValueOff;
                            if ([NSStringFromSelector(button.action) isEqual:@"connectClicked:"]) submit = button;
                        }
                        if (!submit) continue;
                        for (NSTextField *field in fields) {
                            field.stringValue = @"rubyfied-fixture";
                            [[NSNotificationCenter defaultCenter] postNotificationName:NSControlTextDidChangeNotification object:field];
                        }
                        if (!submit.enabled) continue;
                        fixtureSubmitted = YES;
                        fprintf(stderr, "RUBIED_LOGIN_FIXTURE loginPrompt=1\n");
                        [submit performClick:nil];
                        return;
                    }
                }];
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSAppleEventDescriptor *event = [NSAppleEventDescriptor appleEventWithEventClass:kInternetEventClass
                        eventID:kAEGetURL targetDescriptor:[NSAppleEventDescriptor descriptorWithProcessIdentifier:getpid()]
                        returnID:kAutoGenerateReturnID transactionID:kAnyTransactionID];
                    [event setParamDescriptor:[NSAppleEventDescriptor descriptorWithString:FIXTURE_URL] forKeyword:keyDirectObject];
                    NSError *error = nil;
                    [event sendEventWithOptions:NSAppleEventSendNoReply timeout:3 error:&error];
                    if (error) _exit(3);
                });
            }];
    }
}
