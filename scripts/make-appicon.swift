import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage: swift make-appicon.swift <inputPNG> <iconsetDir> <masterOutPNG>
// Trims transparent margins from the input, squares it (centered on a
// transparent canvas), then renders the macOS .iconset PNG sizes plus a
// 1024px master PNG.

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: make-appicon.swift <input> <iconsetDir> <masterOut>\n".utf8))
    exit(2)
}

let inputPath = CommandLine.arguments[1]
let iconsetDir = CommandLine.arguments[2]
let masterOutPath = CommandLine.arguments[3]

func loadImage(_ path: String) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("failed to create destination at \(path)\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    if !CGImageDestinationFinalize(destination) {
        FileHandle.standardError.write(Data("failed to write \(path)\n".utf8))
        exit(1)
    }
}

func makeContext(width: Int, height: Int) -> CGContext? {
    CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

guard let image = loadImage(inputPath) else {
    FileHandle.standardError.write(Data("could not load \(inputPath)\n".utf8))
    exit(1)
}

let width = image.width
let height = image.height

// Render top-left oriented so the alpha scan matches CGImage crop coordinates.
guard let scanContext = makeContext(width: width, height: height) else { exit(1) }
scanContext.translateBy(x: 0, y: CGFloat(height))
scanContext.scaleBy(x: 1, y: -1)
scanContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

guard let raw = scanContext.data else { exit(1) }
let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)

let alphaThreshold: UInt8 = 12
var minX = width, minY = height, maxX = 0, maxY = 0
for y in 0..<height {
    for x in 0..<width {
        let alpha = pixels[(y * width + x) * 4 + 3]
        if alpha > alphaThreshold {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}

guard maxX >= minX, maxY >= minY else {
    FileHandle.standardError.write(Data("image appears fully transparent\n".utf8))
    exit(1)
}

let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = image.cropping(to: cropRect) else {
    FileHandle.standardError.write(Data("crop failed\n".utf8))
    exit(1)
}

let side = max(cropped.width, cropped.height)

func renderSquare(_ source: CGImage, side: Int, output: Int) -> CGImage? {
    guard let context = makeContext(width: output, height: output) else { return nil }
    context.interpolationQuality = .high
    let scale = CGFloat(output) / CGFloat(side)
    let drawW = CGFloat(source.width) * scale
    let drawH = CGFloat(source.height) * scale
    let originX = (CGFloat(output) - drawW) / 2
    let originY = (CGFloat(output) - drawH) / 2
    context.draw(source, in: CGRect(x: originX, y: originY, width: drawW, height: drawH))
    return context.makeImage()
}

guard let master = renderSquare(cropped, side: side, output: 1024) else { exit(1) }
writePNG(master, to: masterOutPath)

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let entries: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for entry in entries {
    guard let rendered = renderSquare(cropped, side: side, output: entry.size) else {
        FileHandle.standardError.write(Data("failed to render \(entry.name)\n".utf8))
        exit(1)
    }
    writePNG(rendered, to: "\(iconsetDir)/\(entry.name)")
}

print("Wrote master \(masterOutPath) and iconset \(iconsetDir)")
