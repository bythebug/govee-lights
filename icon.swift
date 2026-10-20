// Draws the 1024px app icon: `swift icon.swift out.png` (build.sh turns it into AppIcon.icns).
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824px rounded square centred on a 1024px canvas
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 1.00, green: 0.66, blue: 0.22, alpha: 1),
                    NSColor(srgbRed: 0.93, green: 0.30, blue: 0.47, alpha: 1),
                    NSColor(srgbRed: 0.45, green: 0.27, blue: 0.93, alpha: 1)])!.draw(in: tile, angle: -65)

let glow = NSShadow()
glow.shadowColor = NSColor(white: 1, alpha: 0.9)
glow.shadowBlurRadius = 60
glow.set()
let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .medium).applying(.init(paletteColors: [.white]))
let bulb = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let b = bulb.size
bulb.draw(in: NSRect(x: (Double(size) - b.width) / 2, y: (Double(size) - b.height) / 2, width: b.width, height: b.height))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
