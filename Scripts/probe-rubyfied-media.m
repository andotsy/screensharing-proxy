// Appended to the real adapter by test-rubyfied-media.py. Owned loopback peers,
// synthetic negotiation and non-media packets; never a real sharing session.
#include <dlfcn.h>
static BOOL fixtureStarted;
static BOOL fixtureStartFailed;
static id fixtureGet(id object, const char *name) {
    return ((id (*)(id,SEL))objc_msgSend)(object,sel_registerName(name));
}
static void fixtureRequire(BOOL condition, const char *stage) {
    if (!condition) { fprintf(stderr,"Native media fixture failed: %s\n",stage); exit(1); }
}
@interface MediaFixtureDelegate : NSObject
@end
@implementation MediaFixtureDelegate
- (void)stream:(id)stream didStart:(BOOL)started error:(NSError *)error {
    (void)stream; fixtureStarted = started && !error; fixtureStartFailed = !fixtureStarted;
}
@end
@interface NSObject (MediaFixtureInitializer)
- (instancetype)initWithStreamToken:(long long)token delegate:(id)delegate;
@end

int main(void) { @autoreleasepool {
    alarm(20);
    fixtureRequire(dlopen("/System/Library/PrivateFrameworks/ScreenSharing.framework/Versions/A/ScreenSharing",RTLD_LAZY|RTLD_LOCAL)!=NULL,"load framework");
    fixtureRequire(localMediaABIIsSupported(),"checked media ABI");
    report = [@{@"highPerformanceSession":@"unverified"} mutableCopy];
    installLocalMedia();
    NSError *error = nil;
    id offerer = ((id (*)(id,SEL,NSInteger,id,NSError **))objc_msgSend)([NSClassFromString(@"AVCMediaStreamNegotiator") alloc],
        sel_registerName("initWithMode:options:error:"),7,@{@"avcMediaStreamOptionCallID":NSUUID.UUID.UUIDString},&error);
    fixtureRequire(offerer && ((BOOL (*)(id,SEL))objc_msgSend)(offerer,sel_registerName("createOffer")),"offer");
    id answerer = ((id (*)(id,SEL,id,id,NSError **))objc_msgSend)([NSClassFromString(@"AVCMediaStreamNegotiator") alloc],
        sel_registerName("initWithOffer:options:error:"),fixtureGet(offerer,"offer"),@{@"avcMediaStreamOptionCallID":NSUUID.UUID.UUIDString},&error);
    fixtureRequire(answerer && ((BOOL (*)(id,SEL))objc_msgSend)(answerer,sel_registerName("createAnswer")),"answer");
    fixtureRequire(((BOOL (*)(id,SEL,id,NSError **))objc_msgSend)(offerer,sel_registerName("setAnswer:withError:"),fixtureGet(answerer,"answer"),&error),"accept answer");
    id config = ((id (*)(id,SEL,NSError **))objc_msgSend)(offerer,sel_registerName("generateMediaStreamConfigurationWithError:"),&error);
    id options = ((id (*)(id,SEL,NSError **))objc_msgSend)(offerer,sel_registerName("generateMediaStreamInitOptionsWithError:"),&error);
    fixtureRequire(config && options,"configuration");
    int sockets[2]; uint16_t ports[2];
    for (int i=0;i<2;++i) {
        sockets[i] = boundSocket(SOCK_DGRAM,(struct in_addr){.s_addr=htonl(INADDR_LOOPBACK)},0,&ports[i]);
        fixtureRequire(sockets[i]>=0,"owned UDP socket");
        ((void (*)(id,SEL,id))objc_msgSend)(config,sel_registerName(i ? "setRemoteAddress:" : "setLocalAddress:"),mediaAddress(ports[i]));
    }
    struct sockaddr_in peer = {.sin_len=sizeof(peer),.sin_family=AF_INET,.sin_addr.s_addr=htonl(INADDR_LOOPBACK),.sin_port=htons(ports[1])};
    fixtureRequire(connect(sockets[0],(struct sockaddr *)&peer,sizeof(peer))==0,"connected native socket");
    ((void (*)(id,SEL,uint16_t))objc_msgSend)(config,sel_registerName("setRtcpRemotePort:"),ports[1]);
    ((void (*)(id,SEL,BOOL))objc_msgSend)(config,sel_registerName("setRtcpEnabled:"),YES);
    ((void (*)(id,SEL,double))objc_msgSend)(config,sel_registerName("setRtcpSendInterval:"),0.5);
    xpc_object_t dictionary = xpc_dictionary_create(NULL,NULL,0);
    xpc_dictionary_set_fd(dictionary,"avcKeySharedSocket",sockets[0]);
    id stream = ((id (*)(id,SEL,id,id,NSError **))objc_msgSend)([NSClassFromString(@"AVCVideoStream") alloc],sel_registerName("initWithNetworkSockets:options:error:"),dictionary,options,&error);
    fixtureRequire(stream!=nil,"create native stream");
    MediaFixtureDelegate *delegate = [MediaFixtureDelegate new];
    ((void (*)(id,SEL,id))objc_msgSend)(stream,sel_registerName("setDelegate:"),delegate);
    fixtureRequire(((BOOL (*)(id,SEL,id,NSError **))objc_msgSend)(stream,sel_registerName("configure:error:"),config,&error),"configure native stream");
    long long token = ((long long (*)(id,SEL))objc_msgSend)(stream,sel_registerName("streamToken"));
    __weak RubiedVideoClient *weakClient;
    @autoreleasepool {
        RubiedVideoClient *client = [[NSClassFromString(@"AVCRemoteVideoClient") alloc] initWithStreamToken:token delegate:nil];
        weakClient = client;
        fixtureRequire([client isKindOfClass:RubiedVideoClient.class],"native client initializer redirected");
        fixtureRequire([client slotForMode:0].unsignedIntValue!=0,"native image queue slot");
        ((void (*)(id,SEL))objc_msgSend)(stream,sel_registerName("start"));
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:6];
        unsigned feedback=0; uint16_t sequence=0;
        while (deadline.timeIntervalSinceNow>0 && (!fixtureStarted || !feedback)) {
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            uint8_t packet[16]={0x80,0};
            packet[1]=((NSUInteger (*)(id,SEL))objc_msgSend)(config,sel_registerName("rxPayloadType"));
            uint16_t seq=htons(++sequence); memcpy(packet+2,&seq,2);
            uint32_t ssrc=htonl(((unsigned (*)(id,SEL))objc_msgSend)(config,sel_registerName("remoteSSRC")));memcpy(packet+8,&ssrc,4);
            peer.sin_port=htons(ports[0]);
            fixtureRequire(sendto(sockets[1],packet,sizeof(packet),0,(struct sockaddr *)&peer,sizeof(peer))==sizeof(packet),"synthetic datagram");
            struct pollfd wait={.fd=sockets[1],.events=POLLIN};
            if(poll(&wait,1,0)>0) { uint8_t data[65536]; if(recv(sockets[1],data,sizeof(data),0)>0)++feedback; }
        }
        fixtureRequire(fixtureStarted && !fixtureStartFailed && feedback>0,"native start and feedback");
        fixtureRequire(!client.hasReceivedFirstFrame && [report[@"highPerformanceSession"] isEqual:@"unverified"],"invalid packets do not claim decoding");
        fixtureRequire(client.timer!=nil,"native client observer active");
        [client terminateConnection]; [client terminateConnection];
        fixtureRequire(client.timer==nil && client.terminated,"idempotent observer cleanup");
    }
    fixtureRequire(weakClient==nil,"video client released");
    ((void (*)(id,SEL))objc_msgSend)(stream,sel_registerName("stop"));
    close(sockets[0]); close(sockets[1]);
    puts("Native in-process startup, feedback, image-queue slot and client cleanup passed.");
    return 0;
} }
