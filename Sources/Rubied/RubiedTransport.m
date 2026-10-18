#import <AppKit/AppKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>
#include <xpc/xpc.h>

// Experimental, version-specific adapter. Apple's UI resolves the real host
// and retains its login identity. Only the engine's transport address changes.
typedef void (*ConnectIMP)(id, SEL, id, id, double);
static ConnectIMP originalConnect;
static void (*originalStreamStart)(id, SEL, id, BOOL, id);
static void (*originalFirstFrame)(id, SEL, id);
static void (*originalRTCP)(id, SEL, id, id);
static void (*originalRTPTimeout)(id, SEL, id);
static void (*originalRTCPTimeout)(id, SEL, id);
static uint16_t nativeMediaBase = 15900;
static NSTask *relay;
static NSPipe *relayInput;
static NSString *relayHost;
static uint16_t relayRemotePort;
static uint16_t listenerPort = 15900;
static uint16_t mediaBase = 5900;
static uint16_t probeRemoteBase;
static NSMutableData *pendingEvents;
static NSMutableDictionary *report;
static dispatch_queue_t eventQueue;
static BOOL probeMode;
static unsigned udpCalls;
static NSString *failure;

static void saveReport(void) {
    @synchronized(report) {
        report[@"nativeUDPHelperCalls"] = @(__atomic_load_n(&udpCalls, __ATOMIC_RELAXED));
        NSString *directory = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Screen Sharing Rubyfied"];
        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:nil];
        NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        NSString *path = [directory stringByAppendingPathComponent:@"latest-session.json"];
        [data writeToFile:path options:NSDataWritingAtomic error:nil];
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    }
}

static BOOL consumeEvents(NSData *data) {
    @synchronized(report) {
        [pendingEvents appendData:data];
        if (pendingEvents.length > 65536) { failure = @"relayProtocolError"; return NO; }
        BOOL ready = NO;
        for (;;) {
            const void *newline = memchr(pendingEvents.bytes, '\n', pendingEvents.length);
            if (!newline) break;
            NSUInteger length = (const uint8_t *)newline - (const uint8_t *)pendingEvents.bytes;
            NSData *line = [pendingEvents subdataWithRange:NSMakeRange(0, length)];
            [pendingEvents replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
            NSDictionary *event = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
            if (![event isKindOfClass:NSDictionary.class]) { failure = @"relayProtocolError"; continue; }
            NSDictionary *envelope = event[@"event"];
            if (![event[@"version"] isEqual:@1] || ![envelope isKindOfClass:NSDictionary.class] || envelope.count != 1) {
                failure = @"relayProtocolError"; continue;
            }
            NSString *kind = envelope.allKeys.firstObject;
            if ([kind isEqual:@"ready"]) ready = YES;
            // Relay events contain fixed labels and counters, never credentials or payloads.
            if ([kind isKindOfClass:NSString.class] && [@[@"ready", @"traffic", @"media", @"control", @"controlConnections", @"failureContext", @"failed", @"stopped"] containsObject:kind]) {
                report[kind] = envelope[kind];
                if ([kind isEqual:@"failed"]) failure = @"relayFailed";
            }
        }
        return ready;
    }
}

static void stopRelay(void) {
    if (!relay) return;
    @try { [relayInput.fileHandleForWriting closeFile]; } @catch (__unused NSException *exception) {}
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (relay.running && deadline.timeIntervalSinceNow > 0) usleep(10000);
    if (relay.running) [relay terminate];
    deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (relay.running && deadline.timeIntervalSinceNow > 0) usleep(10000);
    if (relay.running) kill(relay.processIdentifier, SIGKILL);
    // The event reader owns the remaining output and saves the terminal events.
}

static BOOL recordStartFailure(NSString *code) {
    @synchronized(report) {
        report[@"adapterFailure"] = @{@"code": code ?: @"relayStartupFailed"};
        saveReport();
    }
    return NO;
}

static NSString *relayFailureMessage(void) {
    @synchronized(report) {
        NSString *code = report[@"adapterFailure"][@"code"];
        NSString *detail;
        if ([code isEqual:@"differentHostSelected"]) {
            detail = @"This viewer already has a relay for another host address. Quit Rubyfied and reopen it to select this host.";
        } else if ([code isEqual:@"differentPortSelected"]) {
            detail = @"This viewer already has a relay for another TCP port. Quit Rubyfied and reopen it to change ports.";
        } else if ([code isEqual:@"relayStopped"]) {
            detail = @"The relay stopped before this connection attempt. Quit Rubyfied and reopen it before retrying.";
        } else {
            NSDictionary *context = report[@"failureContext"];
            NSString *backendCode = report[@"failed"][@"code"];
            detail = [NSString stringWithFormat:@"Ruby relay startup failed: %@.", backendCode ?: code ?: @"unknown"];
            if ([context isKindOfClass:NSDictionary.class]) {
                detail = [detail stringByAppendingFormat:@"\nStage: %@; port: %@; socket error: %@.",
                    context[@"operation"] ?: @"unknown", context[@"port"] ?: @"not reported",
                    context[@"systemError"] ?: @"not reported"];
            }
        }
        return [detail stringByAppendingString:@"\nReport: ~/Library/Logs/Screen Sharing Rubyfied/latest-session.json"];
    }
}

static BOOL startRelay(NSString *host, uint16_t port) {
    if (relay) {
        if (!relay.running) return recordStartFailure(@"relayStopped");
        if (![relayHost isEqual:host]) return recordStartFailure(@"differentHostSelected");
        if (relayRemotePort != port) return recordStartFailure(@"differentPortSelected");
        return YES;
    }
    relayHost = host;
    relayRemotePort = port;
    NSString *script = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"Rubied/loopback-relay.rb"];
    relay = [NSTask new];
    relay.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ruby"];
    relay.arguments = @[@"--disable-gems", script];
    relay.environment = @{@"PATH":@"/usr/bin:/bin", @"LC_ALL":@"C"};
    relayInput = [NSPipe pipe];
    NSPipe *output = [NSPipe pipe];
    relay.standardInput = relayInput;
    relay.standardOutput = output;
    relay.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![relay launchAndReturnError:&error]) { failure = @"rubyLaunchFailed"; return recordStartFailure(failure); }
    NSMutableDictionary *config = [@{@"version":@1, @"sessionID":NSUUID.UUID.UUIDString,
        @"remoteAddress":host, @"remoteControlPort":@(port), @"listenerPort":@(listenerPort),
        @"mediaBase":@(mediaBase), @"nativeMediaBase":@(nativeMediaBase), @"maximumDurationSeconds":@0} mutableCopy];
    if (probeMode && probeRemoteBase) config[@"remoteMediaBase"] = @(probeRemoteBase);
    NSMutableData *line = [[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] mutableCopy];
    [line appendBytes:"\n" length:1];
    @try { [relayInput.fileHandleForWriting writeData:line]; }
    @catch (__unused NSException *exception) { failure = @"relayInputClosed"; stopRelay(); return recordStartFailure(failure); }
    int fd = output.fileHandleForReading.fileDescriptor;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    BOOL ready = NO;
    while (deadline.timeIntervalSinceNow > 0 && !failure && !ready) {
        struct pollfd wait = {.fd=fd, .events=POLLIN};
        if (poll(&wait, 1, 100) <= 0) continue;
        uint8_t buffer[8192];
        ssize_t length = read(fd, buffer, sizeof(buffer));
        if (length <= 0) { failure = @"relayExitedBeforeReady"; break; }
        ready = consumeEvents([NSData dataWithBytes:buffer length:(NSUInteger)length]);
    }
    if (!ready) { if (!failure) failure = @"relayStartupTimeout"; stopRelay(); return recordStartFailure(failure); }
    dispatch_async(eventQueue, ^{
        for (;;) {
            uint8_t buffer[8192];
            ssize_t length = read(fd, buffer, sizeof(buffer));
            if (length < 0 && errno == EINTR) continue;
            if (length <= 0) break;
            consumeEvents([NSData dataWithBytes:buffer length:(NSUInteger)length]);
            saveReport();
        }
        [output.fileHandleForReading closeFile];
        saveReport();
    });
    return YES;
}

static id loopbackAddress(id original) {
    struct in6_addr address;
    inet_pton(AF_INET6, "::ffff:127.0.0.1", &address);
    // The login UI follows originalAddress to recover the resolved host and
    // reconnect after discovery. A bare loopback SSAddress loses that identity.
    return ((id (*)(id, SEL, struct in6_addr, uint16_t, id))objc_msgSend)(
        NSClassFromString(@"SSAddress"),
        NSSelectorFromString(@"ipv6AddressWithIn6Addr:port:resolvedFromAddress:"),
        address, listenerPort, original);
}

static void refuse(id session, NSString *message) {
    ((void (*)(id, SEL, int))objc_msgSend)(session, NSSelectorFromString(@"delegateConnectDidFail:"), -1);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Rubyfied could not start this connection";
        alert.informativeText = message;
        [alert runModal];
    });
}

static void connectThroughRuby(id session, SEL selector, id address, id options, double timeout) {
    struct in6_addr bytes = ((struct in6_addr (*)(id, SEL))objc_msgSend)(address, NSSelectorFromString(@"address"));
    uint16_t port = ((uint16_t (*)(id, SEL))objc_msgSend)(address, NSSelectorFromString(@"port"));
    if (!port) port = 5900;
    if (IN6_IS_ADDR_V4MAPPED(&bytes) && bytes.s6_addr[12] == 127 && port == listenerPort && relay.running) {
        originalConnect(session, selector, address, options, timeout);
        return;
    }
    if (!IN6_IS_ADDR_V4MAPPED(&bytes) || bytes.s6_addr[12] == 127 || port < 1024) {
        refuse(session, @"This experimental build supports a remote IPv4 address. Enter the sharing Mac’s address, not localhost. No direct fallback was started.");
        return;
    }
    char ip[INET_ADDRSTRLEN];
    if (!inet_ntop(AF_INET, &bytes.s6_addr[12], ip, sizeof(ip))) return;
    @synchronized(NSClassFromString(@"SSSession")) {
        if (!startRelay([NSString stringWithUTF8String:ip], port)) {
            refuse(session, relayFailureMessage());
            return;
        }
    }
    originalConnect(session, selector, loopbackAddress(address), options, timeout);
}

// Fixed counters at Apple's real media callbacks distinguish socket delivery,
// stream startup, accepted feedback and decoded first frames. Never inspect
// callback payloads, frame contents, negotiated keys or error descriptions.
static void mediaEvent(NSString *counter) {
    @synchronized(report) {
        NSMutableDictionary *media = [report[@"nativeMedia"] mutableCopy] ?: [NSMutableDictionary new];
        media[counter] = @([media[counter] unsignedIntegerValue] + 1);
        report[@"nativeMedia"] = media;
        saveReport();
    }
}

static void observeStreamStart(id session, SEL selector, id stream, BOOL started, id error) {
    mediaEvent(started && !error ? @"streamStarts" : @"streamStartFailures");
    originalStreamStart(session, selector, stream, started, error);
}
static void observeFirstFrame(id session, SEL selector, id client) {
    mediaEvent(@"firstFrames");
    originalFirstFrame(session, selector, client);
}
static void observeRTCP(id session, SEL selector, id stream, id packets) {
    mediaEvent(@"rtcpCallbacks");
    originalRTCP(session, selector, stream, packets);
}
static void observeRTPTimeout(id session, SEL selector, id stream) {
    mediaEvent(@"rtpTimeouts");
    originalRTPTimeout(session, selector, stream);
}
static void observeRTCPTimeout(id session, SEL selector, id stream) {
    mediaEvent(@"rtcpTimeouts");
    originalRTCPTimeout(session, selector, stream);
}

static id mediaAddress(uint16_t port) {
    id address = [NSClassFromString(@"AVCNetworkAddress") new];
    ((void (*)(id, SEL, id))objc_msgSend)(address, NSSelectorFromString(@"setIp:"), @"127.0.0.1");
    ((void (*)(id, SEL, BOOL))objc_msgSend)(address, NSSelectorFromString(@"setIsIPv6:"), NO);
    ((void (*)(id, SEL, uint16_t))objc_msgSend)(address, NSSelectorFromString(@"setPort:"), port);
    return address;
}

static int mediaFailure(NSString *stage, uint16_t port, int error) {
    @synchronized(report) {
        report[@"nativeMediaFailure"] = @{@"stage":stage, @"port":@(port), @"errno":@(error)};
        saveReport();
    }
    errno = error;
    return -1;
}

static int connectMediaThroughRuby(id cls, SEL selector, id config, uint16_t port) {
    (void)cls; (void)selector;
    __atomic_add_fetch(&udpCalls, 1, __ATOMIC_RELAXED);
    id remote = ((id (*)(id, SEL))objc_msgSend)(config, NSSelectorFromString(@"remoteAddress"));
    NSString *ip = ((id (*)(id, SEL))objc_msgSend)(remote, NSSelectorFromString(@"ip"));
    if (!relay.running || port < mediaBase || port >= mediaBase + 3 ||
        !([ip isEqual:@"127.0.0.1"] || [ip isEqual:@"::ffff:127.0.0.1"])) {
        return mediaFailure(@"unexpectedMediaEndpoint", port, EINVAL);
    }
    uint16_t localPort = nativeMediaBase + (port - mediaBase);
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return mediaFailure(@"socket", localPort, errno);
    NSString *stage = @"socketOptions";
    int receiveBuffer = 262144, sendBuffer = 131072;
    struct sockaddr_in local = {.sin_len=sizeof(local), .sin_family=AF_INET,
        .sin_addr.s_addr=htonl(INADDR_LOOPBACK), .sin_port=htons(localPort)};
    struct sockaddr_in peer = local;
    peer.sin_port = htons(port);
    // An exclusive, genuinely connected pair replaces the old duplicate-tuple
    // trick. Apple's XPC socket dictionary carries this descriptor into AVC.
    // Ruby alone owns LAN media ports; AVC receives and sends only on loopback.
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) ||
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, sizeof(receiveBuffer)) ||
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sendBuffer, sizeof(sendBuffer))) goto failed;
    stage = @"bind";
    if (bind(fd, (struct sockaddr *)&local, sizeof(local))) goto failed;
    stage = @"connect";
    if (connect(fd, (struct sockaddr *)&peer, sizeof(peer))) goto failed;
    // Set fresh address objects: negotiated config objects may share addresses.
    // Only the local transport endpoints change, never keys or codec options.
    ((void (*)(id, SEL, id))objc_msgSend)(config, NSSelectorFromString(@"setLocalAddress:"), mediaAddress(localPort));
    ((void (*)(id, SEL, id))objc_msgSend)(config, NSSelectorFromString(@"setRemoteAddress:"), mediaAddress(port));
    ((void (*)(id, SEL, uint16_t))objc_msgSend)(config, NSSelectorFromString(@"setRtcpRemotePort:"), port);
    @synchronized(report) {
        NSMutableDictionary *media = [report[@"nativeMedia"] mutableCopy] ?: [NSMutableDictionary new];
        media[@"transport"] = @"connectedLoopbackPair";
        media[@"connectedSockets"] = @([media[@"connectedSockets"] unsignedIntegerValue] + 1);
        report[@"nativeMedia"] = media;
        saveReport();
    }
    return fd;
failed: {
    int error = errno;
    close(fd);
    return mediaFailure(stage, localPort, error);
}
}

static int boundSocket(int kind, struct in_addr address, uint16_t port, uint16_t *actual) {
    int fd = socket(AF_INET, kind, 0);
    if (fd < 0) return -1;
    struct sockaddr_in local = {.sin_len=sizeof(local), .sin_family=AF_INET, .sin_port=htons(port), .sin_addr=address};
    if (bind(fd, (struct sockaddr *)&local, sizeof(local))) { close(fd); return -1; }
    socklen_t size = sizeof(local);
    if (getsockname(fd, (struct sockaddr *)&local, &size)) { close(fd); return -1; }
    *actual = ntohs(local.sin_port);
    return fd;
}

// This runs only under the explicit packaged self-test, with ephemeral local
// peers and synthetic bytes. It does not authenticate, capture or decode media.
static BOOL transportProbe(void) {
    int owned[16], count = 0;
    id session = nil;
    BOOL success = NO;
    int route = socket(AF_INET, SOCK_DGRAM, 0);
    if (route < 0) return NO;
    struct sockaddr_in destination = {.sin_len=sizeof(destination), .sin_family=AF_INET, .sin_port=htons(9)};
    inet_pton(AF_INET, "192.0.2.1", &destination.sin_addr);
    struct sockaddr_in local = {0};
    socklen_t size = sizeof(local);
    if (connect(route, (struct sockaddr *)&destination, sizeof(destination)) || getsockname(route, (struct sockaddr *)&local, &size)) {
        close(route); return NO;
    }
    close(route); // Route selection only; no traffic was sent to this peer.
    int peers[3] = {-1,-1,-1};
    for (int attempt = 0; attempt < 40; ++attempt) {
        probeRemoteBase = 20000 + arc4random_uniform(30000);
        BOOL ok = YES;
        for (int offset = 0; offset < 3; ++offset) {
            uint16_t actual;
            peers[offset] = boundSocket(SOCK_DGRAM, local.sin_addr, probeRemoteBase + offset, &actual);
            if (peers[offset] < 0) { ok = NO; break; }
        }
        if (ok) break;
        for (int offset = 0; offset < 3; ++offset) { if (peers[offset] >= 0) close(peers[offset]); peers[offset] = -1; }
    }
    if (peers[2] < 0) return NO;
    for (int offset = 0; offset < 3; ++offset) owned[count++] = peers[offset];
    for (int attempt = 0; attempt < 40; ++attempt) {
        mediaBase = 20000 + arc4random_uniform(30000);
        if (abs((int)mediaBase - (int)probeRemoteBase) < 3) continue;
        int reservations[6], n = 0;
        for (int offset = 0; offset < 3; ++offset) for (int side = 0; side < 2; ++side) {
            uint16_t actual;
            struct in_addr address = side ? (struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)} : local.sin_addr;
            int fd = boundSocket(SOCK_DGRAM, address, mediaBase + offset, &actual);
            if (fd >= 0) reservations[n++] = fd;
        }
        for (int i = 0; i < n; ++i) close(reservations[i]);
        if (n == 6) break;
        mediaBase = 0;
    }
    nativeMediaBase = 0;
    for (int attempt = 0; attempt < 40; ++attempt) {
        uint16_t candidate = 20000 + arc4random_uniform(30000);
        if (abs((int)candidate - (int)mediaBase) < 3 || abs((int)candidate - (int)probeRemoteBase) < 3) continue;
        int reservations[3], n = 0;
        for (int offset = 0; offset < 3; ++offset) {
            uint16_t actual;
            int fd = boundSocket(SOCK_DGRAM, (struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)}, candidate + offset, &actual);
            if (fd >= 0) reservations[n++] = fd;
        }
        for (int i = 0; i < n; ++i) close(reservations[i]);
        if (n == 3) { nativeMediaBase = candidate; break; }
    }
    uint16_t remotePort;
    int listener = boundSocket(SOCK_STREAM, local.sin_addr, 0, &remotePort);
    if (listener < 0) goto done;
    owned[count++] = listener;
    if (!mediaBase || !nativeMediaBase) goto done;
    if (listen(listener, 1)) goto done;
    int reservation = boundSocket(SOCK_STREAM, (struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)}, 0, &listenerPort);
    if (reservation < 0) goto done;
    close(reservation);
    @try {
        struct in6_addr remote = IN6ADDR_ANY_INIT;
        remote.s6_addr[10] = remote.s6_addr[11] = 255;
        memcpy(remote.s6_addr + 12, &local.sin_addr, 4);
        char localIP[INET_ADDRSTRLEN];
        if (!inet_ntop(AF_INET, &local.sin_addr, localIP, sizeof(localIP))) goto done;
        id entered = ((id (*)(id, SEL, id))objc_msgSend)(NSClassFromString(@"SSAddress"),
            NSSelectorFromString(@"addressFromString:"), [NSString stringWithFormat:@"vnc://%s:%u", localIP, remotePort]);
        id address = ((id (*)(id, SEL, struct in6_addr, uint16_t, id))objc_msgSend)(NSClassFromString(@"SSAddress"),
            NSSelectorFromString(@"ipv6AddressWithIn6Addr:port:resolvedFromAddress:"), remote, remotePort, entered);
        id redirected = loopbackAddress(address);
        // Apple carries the root input address through successive resolutions,
        // rather than retaining the immediately preceding resolved object.
        id origin = ((id (*)(id, SEL))objc_msgSend)(address, NSSelectorFromString(@"originalAddress"));
        BOOL identityPreserved = origin != nil &&
            ((id (*)(id, SEL))objc_msgSend)(redirected, NSSelectorFromString(@"originalAddress")) == origin;
        fprintf(stderr, "RUBIED_PROBE originalAddressPreserved=%d\n", identityPreserved);
        if (!identityPreserved) goto done;
        id options = ((id (*)(id, SEL))objc_msgSend)(NSClassFromString(@"SSConnectionOptions"), NSSelectorFromString(@"defaultOptions"));
        session = [NSClassFromString(@"SSSession") new];
        ((ConnectIMP)objc_msgSend)(session, NSSelectorFromString(@"connectToAddress:withOptions:timeout:"), address, options, 3);
        struct pollfd wait = {.fd=listener, .events=POLLIN};
        if (poll(&wait, 1, 3000) <= 0) goto done;
        int control = accept(listener, NULL, NULL);
        if (control < 0) goto done;
        owned[count++] = control;
        const char greeting[] = "RFB 003.008\n";
        if (send(control, greeting, 12, 0) != 12) goto done;
        wait.fd = control;
        if (poll(&wait, 1, 3000) <= 0) goto done;
        char reply[12];
        if (recv(control, reply, 12, MSG_WAITALL) != 12 || memcmp(reply, "RFB ", 4)) goto done;
        for (int offset = 0; offset < 3; ++offset) {
            id config = [NSClassFromString(@"AVCMediaStreamConfig") new];
            id remoteMedia = mediaAddress(mediaBase + offset);
            if (offset == 1) {
                ((void (*)(id, SEL, id))objc_msgSend)(remoteMedia, NSSelectorFromString(@"setIp:"), @"::ffff:127.0.0.1");
                ((void (*)(id, SEL, BOOL))objc_msgSend)(remoteMedia, NSSelectorFromString(@"setIsIPv6:"), YES);
            }
            ((void (*)(id, SEL, id))objc_msgSend)(config, NSSelectorFromString(@"setRemoteAddress:"), remoteMedia);
            xpc_object_t dictionary = ((id (*)(id, SEL, id, uint16_t))objc_msgSend)(NSClassFromString(@"SSSession"),
                NSSelectorFromString(@"newRTPSocketDictionaryWithConfig:port:"), config, mediaBase + offset);
            if (!dictionary) goto done;
            int native = xpc_dictionary_dup_fd(dictionary, "avcKeySharedSocket");
            if (native < 0) goto done;
            owned[count++] = native;
            struct sockaddr_in peer = {0}, bound = {0};
            size = sizeof(peer);
            if (getpeername(native, (struct sockaddr *)&peer, &size) ||
                peer.sin_addr.s_addr != htonl(INADDR_LOOPBACK) || peer.sin_port != htons(mediaBase + offset)) goto done;
            size = sizeof(bound);
            if (getsockname(native, (struct sockaddr *)&bound, &size) ||
                bound.sin_addr.s_addr != htonl(INADDR_LOOPBACK) || bound.sin_port != htons(nativeMediaBase + offset)) goto done;
            id configuredLocal = ((id (*)(id, SEL))objc_msgSend)(config, NSSelectorFromString(@"localAddress"));
            if (((uint16_t (*)(id, SEL))objc_msgSend)(configuredLocal, NSSelectorFromString(@"port")) != nativeMediaBase + offset) goto done;
            uint8_t packet[32]; arc4random_buf(packet, sizeof(packet));
            destination.sin_addr = local.sin_addr; destination.sin_port = htons(mediaBase + offset);
            if (sendto(peers[offset], packet, sizeof(packet), 0, (struct sockaddr *)&destination, sizeof(destination)) != sizeof(packet)) goto done;
            wait.fd = native;
            if (poll(&wait, 1, 1500) <= 0) goto done;
            uint8_t received[64];
            struct sockaddr_in sender = {0}; size = sizeof(sender);
            if (recvfrom(native, received, sizeof(received), 0, (struct sockaddr *)&sender, &size) != sizeof(packet) ||
                memcmp(packet, received, sizeof(packet)) || sender.sin_addr.s_addr != htonl(INADDR_LOOPBACK) ||
                sender.sin_port != peer.sin_port) goto done;
            // No supplied destination: this specifically requires a connected
            // descriptor, unlike r3's sendto-only wildcard-socket fixture.
            if (send(native, packet, sizeof(packet), 0) != sizeof(packet)) goto done;
            wait.fd = peers[offset];
            if (poll(&wait, 1, 1500) <= 0 || recv(peers[offset], received, sizeof(received), 0) != sizeof(packet) || memcmp(packet, received, sizeof(packet))) goto done;
        }
        id conflictConfig = [NSClassFromString(@"AVCMediaStreamConfig") new];
        ((void (*)(id, SEL, id))objc_msgSend)(conflictConfig, NSSelectorFromString(@"setRemoteAddress:"), mediaAddress(mediaBase));
        int duplicate = ((int (*)(id, SEL, id, uint16_t))objc_msgSend)(NSClassFromString(@"SSSession"),
            NSSelectorFromString(@"udpSocketWithAVCMediaStreamConfig:port:"), conflictConfig, mediaBase);
        if (duplicate >= 0) { close(duplicate); goto done; }
        @synchronized(report) {
            if (![report[@"nativeMediaFailure"][@"stage"] isEqual:@"bind"] ||
                ![report[@"nativeMediaFailure"][@"errno"] isEqual:@(EADDRINUSE)]) goto done;
            [report removeObjectForKey:@"nativeMediaFailure"]; // Expected negative fixture only.
        }
        fprintf(stderr, "RUBIED_PROBE nativeSocketConflictRefused=1\n");
        fprintf(stderr, "RUBIED_PROBE connectedMediaSocketDictionaries=3\n");
        success = YES;
    } @catch (__unused NSException *exception) { success = NO; }
done:
    if (session) ((void (*)(id, SEL))objc_msgSend)(session, NSSelectorFromString(@"disconnect"));
    for (int i = 0; i < count; ++i) close(owned[i]);
    stopRelay();
    dispatch_sync(eventQueue, ^{});
    fprintf(stderr, "RUBIED_PROBE tcpAndThreeNativeUDPChannels=%d udpHookCalls=%u\n", success, udpCalls);
    return success;
}

__attribute__((constructor)) static void installRubied(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.andotsy.screensharing-rubyfied"]) return;
        probeMode = getenv("SSP_RUBIED_SELF_TEST") != NULL;
        Class cls = NSClassFromString(@"SSSession");
        Method connect = class_getInstanceMethod(cls, NSSelectorFromString(@"connectToAddress:withOptions:timeout:"));
        Method udp = class_getClassMethod(cls, NSSelectorFromString(@"udpSocketWithAVCMediaStreamConfig:port:"));
        Method addressFactory = class_getClassMethod(NSClassFromString(@"SSAddress"),
            NSSelectorFromString(@"ipv6AddressWithIn6Addr:port:resolvedFromAddress:"));
        Method streamStart = class_getInstanceMethod(cls, NSSelectorFromString(@"stream:didStart:error:"));
        Method firstFrame = class_getInstanceMethod(cls, NSSelectorFromString(@"remoteVideoClientDidReceiveFirstFrame:"));
        Method rtcp = class_getInstanceMethod(cls, NSSelectorFromString(@"stream:didReceiveRTCPPackets:"));
        Method rtpTimeout = class_getInstanceMethod(cls, NSSelectorFromString(@"streamDidRTPTimeOut:"));
        Method rtcpTimeout = class_getInstanceMethod(cls, NSSelectorFromString(@"streamDidRTCPTimeOut:"));
        BOOL mediaABI = YES;
        const char *classes[] = {"AVCNetworkAddress", "AVCNetworkAddress", "AVCNetworkAddress", "AVCMediaStreamConfig", "AVCMediaStreamConfig", "AVCMediaStreamConfig"};
        const char *selectors[] = {"setIp:", "setIsIPv6:", "setPort:", "setLocalAddress:", "setRemoteAddress:", "setRtcpRemotePort:"};
        const char *encodings[] = {"v24@0:8@16", "v20@0:8B16", "v20@0:8S16", "v24@0:8@16", "v24@0:8@16", "v20@0:8S16"};
        for (unsigned i = 0; i < sizeof(classes) / sizeof(classes[0]); ++i) {
            Method method = class_getInstanceMethod(objc_getClass(classes[i]), sel_registerName(selectors[i]));
            mediaABI &= method && !strcmp(method_getTypeEncoding(method), encodings[i]);
        }
        if (!streamStart || !firstFrame || !rtcp || !rtpTimeout || !rtcpTimeout || !mediaABI ||
            strcmp(method_getTypeEncoding(streamStart), "v36@0:8@16B24@28") ||
            strcmp(method_getTypeEncoding(firstFrame), "v24@0:8@16") ||
            strcmp(method_getTypeEncoding(rtcp), "v32@0:8@16@24") ||
            strcmp(method_getTypeEncoding(rtpTimeout), "v24@0:8@16") ||
            strcmp(method_getTypeEncoding(rtcpTimeout), "v24@0:8@16") ||
            !connect || !udp || !addressFactory || strcmp(method_getTypeEncoding(connect), "v40@0:8@16@24d32") ||
            strcmp(method_getTypeEncoding(udp), "i28@0:8@16S24")) {
            fprintf(stderr, "Rubied: unsupported native transport ABI\n");
            _exit(78);
        }
        pendingEvents = [NSMutableData data];
        report = [@{@"schemaVersion":@3, @"transportRevision":@4, @"experiment":@"rubied-native-copy", @"highPerformanceSession":@"unverified"} mutableCopy];
        eventQueue = dispatch_queue_create("com.andotsy.rubied.events", DISPATCH_QUEUE_SERIAL);
        originalConnect = (ConnectIMP)method_setImplementation(connect, (IMP)connectThroughRuby);
        method_setImplementation(udp, (IMP)connectMediaThroughRuby);
        originalStreamStart = (void *)method_setImplementation(streamStart, (IMP)observeStreamStart);
        originalFirstFrame = (void *)method_setImplementation(firstFrame, (IMP)observeFirstFrame);
        originalRTCP = (void *)method_setImplementation(rtcp, (IMP)observeRTCP);
        originalRTPTimeout = (void *)method_setImplementation(rtpTimeout, (IMP)observeRTPTimeout);
        originalRTCPTimeout = (void *)method_setImplementation(rtcpTimeout, (IMP)observeRTCPTimeout);
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
            object:nil queue:nil usingBlock:^(__unused NSNotification *note) { stopRelay(); }];
        atexit(stopRelay);
        if (probeMode) {
            fprintf(stderr, "RUBIED_PROBE injected=1 connectHook=1 udpHook=1 uid=%u\n", getuid());
            [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
                object:nil queue:nil usingBlock:^(__unused NSNotification *note) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                        fprintf(stderr, "RUBIED_PROBE nativeUILaunched=1 windows=%lu nativeMenu=%d\n",
                            (unsigned long)NSApp.windows.count, NSApp.mainMenu != nil);
                        NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
                        BOOL named = [name hasSuffix:@" Rubyfied"] &&
                            [[NSFileManager.defaultManager displayNameAtPath:NSBundle.mainBundle.bundlePath] containsString:@"Rubyfied"];
                        fprintf(stderr, "RUBIED_PROBE localizedIdentity=%d\n", named);
                        if (!named) _exit(1);
                        BOOL passed = transportProbe();
                        if (!passed) _exit(1);
                        [NSApp terminate:nil];
                    });
                }];
        }
    }
}
