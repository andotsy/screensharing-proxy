# Screen Sharing Rubyfier

Rubyfier gets High Performance Screen Sharing working on a Mac whose firewall
blocks the Screen Sharing app.

## Why this exists

In High Performance mode, the video and audio come back to your Mac as incoming
network traffic. Normally that just works, and you don't need this project.

If the firewall blocks incoming connections for Screen Sharing, though, that
media stream can't reach the app. System Ruby (`/usr/bin/ruby`) can still be
allowed through. So Rubyfier makes a copy of Screen Sharing that sends its TCP
and UDP traffic through a small Ruby relay instead of its own sockets.

## How it works

Rubyfier copies the Screen Sharing app that's already on your Mac, adds a small
library and the Ruby relay, and signs the copy locally. Your original Screen
Sharing app isn't touched, and no firewall or network settings are changed.

The copy, **Screen Sharing Rubyfied**, looks and behaves like Screen Sharing.
Apple's code still handles sign-in, video, audio and input; only the network
sockets move to Ruby. The download contains none of Apple's files.

## Install

1. Download the DMG from [Releases](https://github.com/andotsy/screensharing-proxy/releases)
   and drag **Screen Sharing Rubyfier** to Applications.
2. Open it, click **Create Rubyfied App…** and pick a folder. `~/Applications`
   works without an admin password.
3. Open **Screen Sharing Rubyfied**. If Screen Sharing is already running, it
   asks to quit it first. Allow Local Network access when macOS asks.
4. Connect with the other Mac's IPv4 address and choose High Performance.

The app is ad hoc signed, not notarized. If macOS won't open it, see
[the install guide](docs/INSTALL.md#if-macos-blocks-the-app).

## Compatibility

- Apple silicon only.
- Tested with Screen Sharing from macOS 26.7.1 (25G241). High Performance video,
  audio and keyboard/mouse control work there.
- On other macOS versions the patcher still runs and tells you the build is
  untested. If Apple changed the parts the copy hooks into, the copy quits when
  you open it.
- Not yet tested on a Mac where the firewall actually blocks Screen Sharing.
- After a macOS update, create a new copy.

## Known issues

- Turning on **Dynamic Resolution** during a High Performance session corrupts
  the stream right away and the connection closes. Leave it off for now.

## Building from source

You need an Apple silicon Mac with Xcode 26.

```sh
bash Packaging/build-app.sh                         # app in .build/native-bundle/
SSP_VERSION=1.1.0 bash Packaging/build-app-dmg.sh   # DMG in dist/
```

Tests:

```sh
swift test -Xswiftc -warnings-as-errors
python3 Scripts/test-loopback-relay.py
python3 Scripts/test-rubyfied-retry.py
python3 Scripts/test-rubyfied-media.py
```

Building doesn't publish anything. GitHub Actions builds and publishes a release
when a version tag is pushed.

[docs/RUBIED_PATCHER.md](docs/RUBIED_PATCHER.md) covers how the copy is patched,
what the relay does and what it logs.
