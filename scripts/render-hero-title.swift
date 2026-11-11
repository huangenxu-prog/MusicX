import AppKit
import Foundation

let width = 1200
let height = 300
let output = URL(fileURLWithPath: "MusicX/Assets.xcassets/hero_title.imageset/hero_title.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let font = NSFont(name: "STKaiti", size: 176)
    ?? NSFont(name: "Kaiti SC", size: 176)
    ?? NSFont.systemFont(ofSize: 176, weight: .semibold)
let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.43, green: 0.28, blue: 1.0, alpha: 0.72)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = .zero

let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.93, blue: 1.0, alpha: 1),
    .shadow: shadow
]
let title = NSAttributedString(string: "发现音乐", attributes: attributes)
let textSize = title.size()
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high
NSColor.clear.set()
NSRect(x: 0, y: 0, width: width, height: height).fill()
let drawRect = NSRect(
    x: (CGFloat(width) - textSize.width) / 2,
    y: (CGFloat(height) - textSize.height) / 2,
    width: textSize.width,
    height: textSize.height
)
title.draw(in: drawRect)
graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode hero title PNG")
}
try data.write(to: output)
print("Rendered transparent calligraphy title using \(font.fontName): \(output.path)")
