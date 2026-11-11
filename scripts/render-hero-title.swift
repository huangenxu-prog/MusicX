import AppKit
import Foundation

let source = URL(fileURLWithPath: "scripts/hero-title.svg")
let destination = URL(fileURLWithPath: "MusicX/Assets.xcassets/hero_title.imageset/hero_title.png")
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

guard let image = NSImage(contentsOf: source),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
    fatalError("Unable to rasterize scripts/hero-title.svg")
}
try data.write(to: destination)
print("Rendered transparent hero calligraphy asset: \(destination.path)")
