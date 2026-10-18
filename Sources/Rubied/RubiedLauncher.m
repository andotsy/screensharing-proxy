#import <AppKit/AppKit.h>
#include <unistd.h>

// A separate executable keeps Finder launches reproducible without changing
// global DYLD settings or attaching to Apple's installed application.
int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL probe = argc == 2 && strcmp(argv[1], "--rubied-self-test") == 0;
        if (!probe) {
            NSArray<NSRunningApplication *> *originals =
                [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.ScreenSharing"];
            if (originals.count) {
                [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
                [NSApp activateIgnoringOtherApps:YES];
                NSAlert *alert = [NSAlert new];
                alert.messageText = @"Quit the original Screen Sharing viewer?";
                alert.informativeText = @"Its viewer connections will disconnect. This does not turn off this Mac’s Screen Sharing service. Rubyfied needs the media ports for its relay.";
                [alert addButtonWithTitle:@"Quit Viewer and Continue"];
                [alert addButtonWithTitle:@"Cancel"];
                if ([alert runModal] != NSAlertFirstButtonReturn) return 0;
                for (NSRunningApplication *app in originals) [app terminate];
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
                while ([deadline timeIntervalSinceNow] > 0) {
                    BOOL remaining = NO;
                    for (NSRunningApplication *app in originals) remaining |= !app.terminated;
                    if (!remaining) break;
                    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
                }
                for (NSRunningApplication *app in originals) if (!app.terminated) {
                    alert.messageText = @"The original viewer is still running";
                    alert.informativeText = @"Finish closing its connection windows, then open Rubyfied again.";
                    [alert runModal];
                    return 1;
                }
            }
        }
        NSString *contents = NSBundle.mainBundle.bundlePath;
        NSString *binary = [contents stringByAppendingPathComponent:@"Contents/MacOS/ScreenSharingNative"];
        NSString *library = [contents stringByAppendingPathComponent:@"Contents/Frameworks/RubiedTransport.dylib"];
        if (access(binary.fileSystemRepresentation, X_OK) || access(library.fileSystemRepresentation, R_OK)) return 2;
        // The bundled optool adds the load command to this copy at patch time.
        // No DYLD environment variable is needed for a Finder launch.
        unsetenv("DYLD_INSERT_LIBRARIES");
        if (probe) setenv("SSP_RUBIED_SELF_TEST", "1", 1);
        else unsetenv("SSP_RUBIED_SELF_TEST");
        argv[0] = (char *)binary.fileSystemRepresentation;
        if (probe) argv[1] = NULL;
        execv(binary.fileSystemRepresentation, argv);
        return 3;
    }
}
