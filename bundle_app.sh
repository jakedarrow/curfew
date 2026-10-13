#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "🔨 Building Curfew (Release)..."
swift build -c release

APP_NAME="Curfew.app"
BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "📦 Assembling $APP_NAME bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
touch "$BUILD_DIR/.metadata_never_index"

# 1. Copy Release Binary
cp "$DIR/.build/release/Curfew" "$MACOS_DIR/Curfew"
chmod +x "$MACOS_DIR/Curfew"

# 2. Generate Info.plist
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Curfew</string>
    <key>CFBundleIdentifier</key>
    <string>com.jakedarrow.Curfew</string>
    <key>CFBundleName</key>
    <string>Curfew</string>
    <key>CFBundleDisplayName</key>
    <string>Curfew</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

# 3. Generate AppIcon.icns
echo "🎨 Generating Curfew App Icon..."
ICONSET_DIR="/tmp/Curfew.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift -e '
import Cocoa

func generateIcon(size: Int, filename: String) {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * (110.0 / 512.0)
    let inset = s * (25.0 / 512.0)
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: cornerRadius, yRadius: cornerRadius)

    // Vibrant Royal Twilight Indigo-Violet Gradient
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.30, green: 0.25, blue: 0.75, alpha: 1.0),
        NSColor(calibratedRed: 0.12, green: 0.10, blue: 0.38, alpha: 1.0)
    ])!
    gradient.draw(in: path, angle: -45)

    // Crisp Border glow
    NSColor.white.withAlphaComponent(0.25).setStroke()
    path.lineWidth = max(1.0, s * (3.0 / 512.0))
    path.stroke()

    // Glowing Golden Moon & Bright White Stars
    if let symbol = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: nil) {
        let symSize = s * (270.0 / 512.0)
        let gold = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.38, alpha: 1.0)
        let starWhite = NSColor(calibratedWhite: 1.0, alpha: 0.95)
        let config = NSImage.SymbolConfiguration(pointSize: symSize, weight: .semibold).applying(
            NSImage.SymbolConfiguration(paletteColors: [gold, starWhite])
        )
        if let configured = symbol.withSymbolConfiguration(config) {
            let symRect = NSRect(x: (s - symSize) / 2, y: (s - symSize) / 2, width: symSize, height: symSize)
            configured.draw(in: symRect)
        }
    }

    image.unlockFocus()

    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: filename))
    }
}

let iconSizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (sz, name) in iconSizes {
    generateIcon(size: sz, filename: "/tmp/Curfew.iconset/\(name)")
}
'

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# 4. Ad-hoc codesign
echo "🔏 Signing application bundle..."
codesign --force --deep --sign - "$APP_DIR"

if [ -d "/Applications" ]; then
    echo "📲 Installing to /Applications/Curfew.app..."
    rm -rf "/Applications/Curfew.app"
    cp -R "$APP_DIR" "/Applications/Curfew.app"
    touch "/Applications/Curfew.app"
    # Unregister staging copy from LaunchServices and remove build directory so Raycast/Spotlight never shows duplicate apps
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP_DIR" 2>/dev/null || true
    rm -rf "$BUILD_DIR"
    echo "✅ Successfully deployed to /Applications/Curfew.app"
fi

echo "✅ App ready at /Applications/Curfew.app"
