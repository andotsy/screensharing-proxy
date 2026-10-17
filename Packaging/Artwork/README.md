# Proxy icon artwork

The app icon source is the Icon Composer document `Packaging/AppIcon.icon`: two
cream right-pointing arrows separated by a mint divider on a graphite tile. The
arrows and divider are separate vector layers with their own dark and tinted
colors; the mint divider marks the allowed connection and stays the brightest
layer in tinted and clear appearances. Edit it in Icon Composer.

`Packaging/build-app.sh` compiles the document with `actool` into the bundle's
`Assets.car`, and `Packaging/app-icon.swift` renders that compiled icon at each
macOS icon size so `iconutil` can create the `AppIcon.icns` fallback.

The layers were drawn on 2026-10-17 from the user-supplied
`proxy-svgrepo-com.svg`, preserved here as `ProxyReference.svg`. The supplied SVG
identifies SVG Repo (https://www.svgrepo.com/) in its metadata. Its arrow/divider
arrangement is the reference for the artwork; no claim is made that the
reference symbol was authored by this project.
