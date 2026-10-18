#!/usr/bin/env python3
"""Exercise the real adapter's relay generations with an owned unavailable TCP peer.

No real sharing host, credentials, network configuration or installed viewer.
The first peer is bound but not listening; the same peer then accepts a retry.
"""
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

FIXTURE = r'''
static void requireFixture(BOOL condition, const char *stage) {
    if (!condition) { fprintf(stderr, "Retry fixture failed: %s\n", stage); stopRelay(); _exit(1); }
}
static void drainFixture(void) {
    requireFixture(!relayReader || dispatch_group_wait(relayReader,
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC)) == 0, "reader cleanup");
}
static int connectFixture(uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    requireFixture(fd >= 0, "client socket");
    struct sockaddr_in target = {.sin_len=sizeof(target), .sin_family=AF_INET,
        .sin_addr.s_addr=htonl(INADDR_LOOPBACK), .sin_port=htons(port)};
    requireFixture(connect(fd, (struct sockaddr *)&target, sizeof(target)) == 0, "client connect");
    return fd;
}
int main(void) { @autoreleasepool {
    alarm(25);
    probeMode = YES;
    report = [@{@"schemaVersion":@5, @"transportRevision":@6} mutableCopy];
    pendingEvents = [NSMutableData data];
    eventQueue = dispatch_queue_create("rubyfied.retry-fixture", DISPATCH_QUEUE_SERIAL);
    int route = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in address = {.sin_len=sizeof(address), .sin_family=AF_INET, .sin_port=htons(9)};
    inet_pton(AF_INET, "192.0.2.1", &address.sin_addr);
    requireFixture(connect(route, (struct sockaddr *)&address, sizeof(address)) == 0, "route selection");
    socklen_t size = sizeof(address);
    requireFixture(getsockname(route, (struct sockaddr *)&address, &size) == 0, "source selection");
    close(route);
    char ip[INET_ADDRSTRLEN]; inet_ntop(AF_INET, &address.sin_addr, ip, sizeof(ip));
    NSString *host = [NSString stringWithUTF8String:ip];
    uint16_t remotePort;
    int server = boundSocket(SOCK_STREAM, address.sin_addr, 0, &remotePort);
    requireFixture(server >= 0, "reserve remote port"); // Bound, deliberately not listening yet.
    int local = boundSocket(SOCK_STREAM, (struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)}, 0, &listenerPort);
    requireFixture(local >= 0, "reserve relay port"); close(local);
    BOOL reserved = NO;
    for (unsigned attempt=0; attempt<40 && !reserved; ++attempt) {
        mediaBase = 20000 + arc4random_uniform(29000);
        probeRemoteBase = mediaBase + 3;
        nativeMediaBase = mediaBase + 6;
        int sockets[18], count=0;
        for (unsigned side=0; side<2; ++side) for (unsigned offset=0; offset<9; ++offset) {
            uint16_t actual;
            int fd = boundSocket(SOCK_DGRAM, side ? (struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)} : address.sin_addr,
                                 mediaBase+offset, &actual);
            if(fd>=0) sockets[count++]=fd;
        }
        reserved = count == 18;
        for(int i=0;i<count;++i) close(sockets[i]);
    }
    requireFixture(reserved, "fixture UDP range");
    recordConnectionRequest(host, remotePort, NO, nil, 4);
    requireFixture(startRelay(host, remotePort), "first ready");
    int client = connectFixture(listenerPort);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12];
    while(relay.running && deadline.timeIntervalSinceNow>0) usleep(10000);
    requireFixture(!relay.running, "refused relay exit"); drainFixture(); close(client);
    NSString *firstFailure = report[@"failed"][@"code"];
    requireFixture(([@[@"connectFailed", @"connectionTimedOut"] containsObject:firstFailure]) &&
        [report[@"failureContext"][@"operation"] isEqual:@"hostConnect"], "first failure evidence");
    requireFixture(listen(server, 1) == 0, "enable same peer");
    recordConnectionRequest(host, remotePort, NO, nil, 4);
    requireFixture(startRelay(host, remotePort), "restart stopped task");
    requireFixture(relayGeneration == 2 && !report[@"failed"] && !report[@"adapterFailure"], "fresh generation");
    requireFixture([report[@"previousAttempts"] count] == 1 &&
        [report[@"previousAttempts"][0][@"failed"][@"code"] isEqual:firstFailure], "preserved prior failure");
    requireFixture(startRelay(host, remotePort) && relayGeneration == 2, "reuse active same target");
    requireFixture(!startRelay(host, remotePort == 65535 ? 65534 : remotePort+1) &&
        [report[@"adapterFailure"][@"code"] isEqual:@"differentPortSelected"], "active target remains pinned");
    @synchronized(report) { [report removeObjectForKey:@"adapterFailure"]; } // Expected negative fixture.
    client = connectFixture(listenerPort);
    struct pollfd wait = {.fd=server, .events=POLLIN};
    requireFixture(poll(&wait, 1, 2000)>0, "retry reached same peer");
    int accepted = accept(server, NULL, NULL); requireFixture(accepted>=0, "accept retry");
    const char payload[] = "retry fixture";
    requireFixture(send(accepted,payload,sizeof(payload),0)==sizeof(payload), "send fixture");
    wait.fd=client; requireFixture(poll(&wait,1,2000)>0, "receive deadline");
    char received[sizeof(payload)];
    requireFixture(recv(client,received,sizeof(received),MSG_WAITALL)==sizeof(received) &&
        !memcmp(payload,received,sizeof(payload)), "retry byte forwarding");
    close(client); close(accepted);
    stopRelay(); drainFixture();
    requireFixture([report[@"controlConnections"][@"connected"] isEqual:@1], "retry counters");
    for(int i=0;i<2;++i) { requireFixture(startRelay(host,remotePort), "bounded restart"); stopRelay(); drainFixture(); }
    requireFixture(!startRelay(host,remotePort) &&
        [report[@"adapterFailure"][@"code"] isEqual:@"relayRetryLimit"], "restart rate bound");
    requireFixture([report[@"previousAttempts"] count] == 3 && [report[@"connectionRequests"] count] == 2,
                   "bounded history");
    close(server);
    for(unsigned side=0;side<2;++side) for(unsigned offset=0;offset<3;++offset) {
        uint16_t actual;
        int fd = boundSocket(SOCK_DGRAM,side ? (struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)} : address.sin_addr,
                             mediaBase+offset,&actual);
        requireFixture(fd>=0,"released UDP reservations");close(fd);
    }
    puts("Connection failure, same-peer recovery, clean generations, preserved evidence and bounded restart passed.");
    return 0;
} }
'''


def main():
    with tempfile.TemporaryDirectory(prefix='rubyfied-retry-') as temporary:
        root = Path(temporary)
        app = root / 'Relay Retry Fixture.app'
        contents = app / 'Contents'
        resources = contents / 'Resources/Rubied'
        resources.mkdir(parents=True)
        binary = contents / 'MacOS/RelayRetryFixture'
        binary.parent.mkdir()
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.andotsy.rubyfied-retry-fixture',
            'CFBundleExecutable': binary.name, 'CFBundlePackageType': 'APPL'}))
        for name in ('relay.rb', 'loopback-relay.rb'):
            shutil.copyfile(ROOT / 'Sources/ProxyCore/Resources' / name, resources / name)
        source = (ROOT / 'Sources/Rubied/RubiedTransport.m').read_text()
        directory = '[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/Screen Sharing Rubyfied"]'
        assert source.count(directory) == 1
        source = source.replace(directory, '@' + json.dumps(str(root / 'reports')))
        fixture = root / 'fixture.m'
        fixture.write_text(source + '\n' + FIXTURE)
        subprocess.run(['clang', '-arch', 'arm64', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                        '-framework', 'Foundation', '-framework', 'AppKit', str(fixture), '-o', str(binary)],
                       check=True, timeout=60)
        subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(app)],
                       check=True, capture_output=True, timeout=15)
        subprocess.run([str(binary)], check=True, timeout=30)
        text = (root / 'reports/latest-session.json').read_text()
        assert str(root) not in text and 'retry fixture' not in text
        assert len(text) < 32768
        report = json.loads(text)
        assert report['relayGeneration'] == 4 and len(report['previousAttempts']) == 3
        assert report['previousAttempts'][0]['failed']['code'] in ('connectFailed', 'connectionTimedOut')
        assert len(report['connectionRequests']) == 2
        print('Retry report bounds and retained failure passed.')


if __name__ == '__main__':
    main()
