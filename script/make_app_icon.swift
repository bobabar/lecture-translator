#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "resources/AppIcon.icns")
let fileManager = FileManager.default
let temporaryDirectory = fileManager.temporaryDirectory
    .appendingPathComponent("lecture-translator-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: outputURL)

let iconSpecs: [(name: String, pixels: Int)] = [
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

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

func drawArrow(
    in context: CGContext,
    from start: CGPoint,
    to end: CGPoint,
    head: CGFloat
) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let left = CGPoint(
        x: end.x - cos(angle - .pi / 6) * head,
        y: end.y - sin(angle - .pi / 6) * head
    )
    let right = CGPoint(
        x: end.x - cos(angle + .pi / 6) * head,
        y: end.y - sin(angle + .pi / 6) * head
    )

    context.move(to: start)
    context.addLine(to: end)
    context.move(to: end)
    context.addLine(to: left)
    context.move(to: end)
    context.addLine(to: right)
}

func renderPNG(pixels: Int, to url: URL) throws {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate icon bitmap."])
    }

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.clear(bounds)

    let backgroundRect = bounds.insetBy(dx: size * 0.06, dy: size * 0.06)
    let backgroundPath = CGPath(
        roundedRect: backgroundRect,
        cornerWidth: size * 0.22,
        cornerHeight: size * 0.22,
        transform: nil
    )
    context.addPath(backgroundPath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            color(0.03, 0.54, 0.56),
            color(0.08, 0.66, 0.50),
            color(0.22, 0.76, 0.60)
        ] as CFArray,
        locations: [0, 0.58, 1]
    )
    if let gradient {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: backgroundRect.minX, y: backgroundRect.maxY),
            end: CGPoint(x: backgroundRect.maxX, y: backgroundRect.minY),
            options: []
        )
    }
    context.resetClip()

    let bubbleRect = CGRect(x: size * 0.21, y: size * 0.25, width: size * 0.58, height: size * 0.48)
    let bubblePath = CGPath(
        roundedRect: bubbleRect,
        cornerWidth: size * 0.10,
        cornerHeight: size * 0.10,
        transform: nil
    )
    context.setFillColor(color(1, 1, 1, 0.94))
    context.addPath(bubblePath)
    context.fillPath()

    context.beginPath()
    context.move(to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.28, y: bubbleRect.minY + size * 0.03))
    context.addLine(to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.43, y: bubbleRect.minY + size * 0.03))
    context.addLine(to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.31, y: bubbleRect.minY - size * 0.10))
    context.closePath()
    context.fillPath()

    context.setStrokeColor(color(0.03, 0.40, 0.43))
    context.setLineWidth(max(2, size * 0.052))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.beginPath()
    drawArrow(
        in: context,
        from: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.23, y: bubbleRect.midY + size * 0.065),
        to: CGPoint(x: bubbleRect.maxX - bubbleRect.width * 0.24, y: bubbleRect.midY + size * 0.065),
        head: size * 0.085
    )
    drawArrow(
        in: context,
        from: CGPoint(x: bubbleRect.maxX - bubbleRect.width * 0.23, y: bubbleRect.midY - size * 0.065),
        to: CGPoint(x: bubbleRect.minX + bubbleRect.width * 0.24, y: bubbleRect.midY - size * 0.065),
        head: size * 0.085
    )
    context.strokePath()

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "Icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create icon PNG."])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "Icon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not write icon PNG."])
    }
}

for spec in iconSpecs {
    try renderPNG(pixels: spec.pixels, to: iconsetURL.appendingPathComponent(spec.name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

try? fileManager.removeItem(at: temporaryDirectory)
if process.terminationStatus != 0 {
    throw NSError(domain: "Icon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}
