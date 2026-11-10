import AppKit
import Foundation

let source = URL(fileURLWithPath: "MusicX/Assets.xcassets/AppIcon.appiconset/AppIcon.svg")
let destination = URL(fileURLWithPath: "MusicX/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let image = NSImage(contentsOf: source),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
    fatalError("Unable to rasterize AppIcon.svg")
}
try data.write(to: destination)
