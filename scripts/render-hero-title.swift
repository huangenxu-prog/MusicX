import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 1200
let height = 300
let output = URL(fileURLWithPath: "MusicX/Assets.xcassets/hero_title.imageset/hero_title.png")

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)

let font = CTFontCreateWithName("STKaiti" as CFString, 176, nil)
let attributed = CFAttributedStringCreate(nil, "发现音乐" as CFString, [kCTFontAttributeName: font] as CFDictionary)!
let line = CTLineCreateWithAttributedString(attributed)
let runs = CTLineGetGlyphRuns(line) as! [CTRun]
let path = CGMutablePath()

for run in runs {
    let count = CTRunGetGlyphCount(run)
    guard count > 0 else { continue }
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
    let attributes = CTRunGetAttributes(run) as NSDictionary
    let runFont = attributes[kCTFontAttributeName] as! CTFont
    for index in 0..<count {
        if let glyphPath = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
            var transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
            path.addPath(glyphPath, transform: transform)
        }
    }
}

let bounds = path.boundingBoxOfPath
let x = (CGFloat(width) - bounds.width) / 2 - bounds.minX
let y = (CGFloat(height) - bounds.height) / 2 - bounds.minY
var placement = CGAffineTransform(translationX: x, y: y)
let placedPath = path.copy(using: &placement)!

let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                       bytesPerRow: width * 4, space: colorSpace,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.clear(CGRect(x: 0, y: 0, width: width, height: height))
bitmap.setAllowsAntialiasing(true)
bitmap.setShouldAntialias(true)

let violet = CGColor(red: 0.42, green: 0.28, blue: 1.0, alpha: 0.62)
bitmap.saveGState()
bitmap.addPath(placedPath)
bitmap.setFillColor(violet)
bitmap.setShadow(offset: .zero, blur: 24, color: violet)
bitmap.fillPath()
bitmap.restoreGState()

bitmap.saveGState()
bitmap.addPath(placedPath)
bitmap.clip()
let gradient = CGGradient(colorsSpace: colorSpace,
    colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
             CGColor(red: 0.88, green: 0.84, blue: 1, alpha: 1)] as CFArray,
    locations: [0, 1])!
bitmap.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height),
                          end: CGPoint(x: 0, y: 0), options: [])
bitmap.restoreGState()

guard let image = bitmap.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to create hero title PNG")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write hero title PNG") }
print("Rendered hero title asset: \(output.path), font: \(CTFontCopyPostScriptName(font))")
