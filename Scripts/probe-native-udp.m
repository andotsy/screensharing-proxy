// Exercise only the inspected native socket-creation method, not a Screen
// Sharing session. Owned ephemeral sockets, no configuration changes, no data
// sent to the documentation-only peer. Payload delivery is entirely local.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

@interface SSPFixtureRemoteAddress : NSObject
- (BOOL)isIPv6;
- (NSString *)ip;
@end
@implementation SSPFixtureRemoteAddress
- (BOOL)isIPv6 { return NO; }
- (NSString *)ip { return @"192.0.2.1"; }
@end

@interface SSPFixtureMediaConfig : NSObject
@property(nonatomic, strong) SSPFixtureRemoteAddress *remoteAddress;
@end
@implementation SSPFixtureMediaConfig
@end

static void requireCall(int value, NSString *stage) {
    if (value < 0) {
        @throw [NSException exceptionWithName:@"FixtureCallFailed" reason:stage
                                    userInfo:@{@"errno": @(errno)}];
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        alarm(10);
        NSMutableDictionary *result = [@{@"scope": @"native UDP helper; no session"} mutableCopy];
        int route = -1, relay = -1, native = -1, injector = -1;
        int reservedPort = 0;
        if (argc != 1) {
            if (argc != 3 || strcmp(argv[1], "--reserved-port") != 0) return 2;
            char *end = NULL;
            long value = strtol(argv[2], &end, 10);
            if (!end || *end || value < 1024 || value > 65535) return 2;
            reservedPort = (int)value;
        }
        void *framework = NULL;
        @try {
            framework = dlopen("/System/Library/PrivateFrameworks/ScreenSharing.framework/Versions/A/ScreenSharing", RTLD_LAZY | RTLD_LOCAL);
            Class cls = NSClassFromString(@"SSSession");
            SEL selector = NSSelectorFromString(@"udpSocketWithAVCMediaStreamConfig:port:");
            Method method = cls ? class_getClassMethod(cls, selector) : NULL;
            if (!framework || !method || strcmp(method_getTypeEncoding(method), "i28@0:8@16S24") != 0) {
                @throw [NSException exceptionWithName:@"UnsupportedNativeMethod" reason:nil userInfo:nil];
            }

            // UDP connect performs route/source selection without sending a
            // datagram. Never send any bytes through route or relay below.
            struct sockaddr_in peer = {.sin_len = sizeof(peer), .sin_family = AF_INET, .sin_port = htons(9)};
            inet_pton(AF_INET, "192.0.2.1", &peer.sin_addr);
            route = socket(AF_INET, SOCK_DGRAM, 0);
            requireCall(route, @"route.socket");
            requireCall(connect(route, (struct sockaddr *)&peer, sizeof(peer)), @"route.connect");
            struct sockaddr_in local = {0};
            socklen_t length = sizeof(local);
            requireCall(getsockname(route, (struct sockaddr *)&local, &length), @"route.getsockname");
            close(route); route = -1;
            local.sin_port = 0;

            if (reservedPort) {
                // The test driver already started the real Ruby child. Use its
                // reserved tuple without taking another socket at that port.
                local.sin_port = htons((uint16_t)reservedPort);
            } else {
            relay = socket(AF_INET, SOCK_DGRAM, 0);
            requireCall(relay, @"relay.socket");
            int enabled = 1;
            requireCall(setsockopt(relay, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled)), @"relay.reuseaddr");
            requireCall(setsockopt(relay, SOL_SOCKET, SO_REUSEPORT, &enabled, sizeof(enabled)), @"relay.reuseport");
            requireCall(bind(relay, (struct sockaddr *)&local, sizeof(local)), @"relay.bind");
            length = sizeof(local);
            requireCall(getsockname(relay, (struct sockaddr *)&local, &length), @"relay.getsockname");
            peer.sin_port = local.sin_port;
            requireCall(connect(relay, (struct sockaddr *)&peer, sizeof(peer)), @"relay.connect");
            }

            SSPFixtureMediaConfig *config = [SSPFixtureMediaConfig new];
            config.remoteAddress = [SSPFixtureRemoteAddress new];
            typedef int (*CreateSocket)(id, SEL, id, uint16_t);
            CreateSocket createSocket = (CreateSocket)method_getImplementation(method);
            native = createSocket(cls, selector, config, ntohs(local.sin_port));
            result[@"nativeReturnedDescriptor"] = @(native >= 0);
            requireCall(native, @"native.createSocket");
            struct sockaddr_in observed = {0};
            length = sizeof(observed);
            int connected = getpeername(native, (struct sockaddr *)&observed, &length);
            result[@"nativeConnected"] = @(connected == 0);
            if (connected < 0) result[@"nativePeerError"] = @(errno);
            length = sizeof(observed);
            requireCall(getsockname(native, (struct sockaddr *)&observed, &length), @"native.getsockname");
            result[@"nativeWildcard"] = @(observed.sin_addr.s_addr == INADDR_ANY);
            result[@"nativeMediaPortMatches"] = @(observed.sin_port == local.sin_port);

            injector = socket(AF_INET, SOCK_DGRAM, 0);
            requireCall(injector, @"injector.socket");
            struct sockaddr_in loopback = {.sin_len = sizeof(loopback), .sin_family = AF_INET};
            loopback.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            requireCall(bind(injector, (struct sockaddr *)&loopback, sizeof(loopback)), @"injector.bind");
            length = sizeof(loopback);
            requireCall(getsockname(injector, (struct sockaddr *)&loopback, &length), @"injector.getsockname");
            uint8_t payload[32], received[64];
            arc4random_buf(payload, sizeof(payload));
            ssize_t sent = sendto(injector, payload, sizeof(payload), 0, (struct sockaddr *)&local, sizeof(local));
            requireCall((int)sent, @"injector.sendtoLocalAddress");
            struct pollfd descriptors[] = {{native, POLLIN, 0}, {relay, POLLIN, 0}};
            requireCall(poll(descriptors, 2, 500), @"delivery.poll");
            result[@"relayReceivedLocalPacket"] = @((descriptors[1].revents & POLLIN) != 0);
            if (descriptors[0].revents & POLLIN) {
                length = sizeof(observed);
                ssize_t count = recvfrom(native, received, sizeof(received), MSG_DONTWAIT, (struct sockaddr *)&observed, &length);
                result[@"localInjectionToNative"] = @(count == (ssize_t)sizeof(payload) && memcmp(received, payload, sizeof(payload)) == 0
                    && observed.sin_addr.s_addr == loopback.sin_addr.s_addr && observed.sin_port == loopback.sin_port);
            } else {
                result[@"localInjectionToNative"] = @NO;
            }
        } @catch (NSException *exception) {
            result[@"errorType"] = exception.name;
            if ([exception.name isEqualToString:@"FixtureCallFailed"]) {
                result[@"failureStage"] = exception.reason;
                result[@"errno"] = exception.userInfo[@"errno"];
            }
        } @finally {
            int descriptors[] = {route, relay, native, injector};
            for (size_t index = 0; index < sizeof(descriptors) / sizeof(descriptors[0]); ++index) {
                if (descriptors[index] >= 0) close(descriptors[index]);
            }
            if (framework) dlclose(framework);
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:NULL];
        puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
        alarm(0);
        return 0;
    }
}
