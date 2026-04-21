#!/usr/bin/env swift

// Generate Kite's macOS app icon into an AppIcon.appiconset.
//
// Usage:
//   swift scripts/generate_icon.swift [outdir]
//
// Default outdir: Resources/Assets.xcassets/AppIcon.appiconset (relative to cwd).
//
// Design: a deep-blue gradient rounded square ("squircle-ish" via
// RoundedRect cornerRadius = 22% of side) with a white kite-diamond
// glyph and a short tail. No external dependencies — CoreGraphics only,
// so the script runs reliably from a plain `swift` invocation without
// requiring a SwiftUI environment (ImageRenderer needs a run-loop which
// the command-line interpreter doesn't reliably provide).
//
// Re-running produces identical output and overwrites the
// AppIcon.appiconset contents. Commit the generated PNGs so CI / a fresh
// checkout build the bundle with an icon without first running the
// script.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Icon rendering

func renderKitePNG(size pixels: Int) -> Data? {
    let side = CGFloat(pixels)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    // swiftlint:disable:next force_unwrapping
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Flip Y so drawing math reads top-down like SwiftUI / UIKit.
    ctx.translateBy(x: 0, y: side)
    ctx.scaleBy(x: 1, y: -1)

    // Background: linear gradient blue top-left → deeper blue bottom-right.
    let bgRect = CGRect(x: 0, y: 0, width: side, height: side)
    let cornerRadius = side * 0.22
    let bgPath = CGPath(
        roundedRect: bgRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let gradientColors = [
        CGColor(srgbRed: 0.17, green: 0.40, blue: 0.86, alpha: 1.0),
        CGColor(srgbRed: 0.08, green: 0.22, blue: 0.55, alpha: 1.0)
    ] as CFArray
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: gradientColors,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: side, y: side),
        options: []
    )
    ctx.restoreGState()

    // Kite diamond glyph, centred and offset slightly up to leave room
    // for the tail.
    let glyphWidth = side * 0.48
    let glyphHeight = side * 0.64
    let centerX = side / 2
    let centerY = side / 2 - side * 0.04

    let diamond = CGMutablePath()
    diamond.move(to: CGPoint(x: centerX, y: centerY - glyphHeight / 2))
    diamond.addLine(to: CGPoint(x: centerX + glyphWidth / 2, y: centerY))
    diamond.addLine(to: CGPoint(x: centerX, y: centerY + glyphHeight / 2))
    diamond.addLine(to: CGPoint(x: centerX - glyphWidth / 2, y: centerY))
    diamond.closeSubpath()

    ctx.setFillColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.95))
    ctx.addPath(diamond)
    ctx.fillPath()

    // Cross-spars: the two thin lines splitting the diamond into quadrants.
    let sparColor = CGColor(srgbRed: 0.10, green: 0.24, blue: 0.58, alpha: 0.65)
    ctx.setStrokeColor(sparColor)
    ctx.setLineWidth(max(1, side * 0.010))
    ctx.move(to: CGPoint(x: centerX, y: centerY - glyphHeight / 2))
    ctx.addLine(to: CGPoint(x: centerX, y: centerY + glyphHeight / 2))
    ctx.move(to: CGPoint(x: centerX - glyphWidth / 2, y: centerY))
    ctx.addLine(to: CGPoint(x: centerX + glyphWidth / 2, y: centerY))
    ctx.strokePath()

    // Tail: a short wavy line from the diamond's bottom point.
    let tailStartY = centerY + glyphHeight / 2
    let tailEndY = tailStartY + side * 0.18
    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.80))
    ctx.setLineCap(.round)
    ctx.setLineWidth(max(1, side * 0.022))
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: centerX, y: tailStartY))
    tail.addCurve(
        to: CGPoint(x: centerX, y: tailEndY),
        control1: CGPoint(x: centerX + side * 0.04, y: tailStartY + side * 0.06),
        control2: CGPoint(x: centerX - side * 0.04, y: tailStartY + side * 0.12)
    )
    ctx.addPath(tail)
    ctx.strokePath()

    // Two small tail dashes — visual echo of a real kite's ribbons.
    let dashColor = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.75)
    ctx.setFillColor(dashColor)
    for i in 0 ..< 2 {
        let dashCenterY = tailEndY + side * 0.025 + CGFloat(i) * side * 0.045
        let dashRect = CGRect(
            x: centerX - side * 0.035,
            y: dashCenterY - side * 0.010,
            width: side * 0.07,
            height: side * 0.020
        )
        let dashPath = CGPath(
            roundedRect: dashRect,
            cornerWidth: side * 0.010,
            cornerHeight: side * 0.010,
            transform: nil
        )
        ctx.addPath(dashPath)
        ctx.fillPath()
    }

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - Asset catalog output

struct Slot {
    let filename: String
    let pixels: Int
    let logicalSize: Int
    let scale: Int

    var scaleString: String { "\(scale)x" }
    var sizeString: String { "\(logicalSize)x\(logicalSize)" }
}

let slots: [Slot] = [
    Slot(filename: "icon_16x16.png",     pixels: 16,   logicalSize: 16,  scale: 1),
    Slot(filename: "icon_16x16@2x.png",  pixels: 32,   logicalSize: 16,  scale: 2),
    Slot(filename: "icon_32x32.png",     pixels: 32,   logicalSize: 32,  scale: 1),
    Slot(filename: "icon_32x32@2x.png",  pixels: 64,   logicalSize: 32,  scale: 2),
    Slot(filename: "icon_128x128.png",   pixels: 128,  logicalSize: 128, scale: 1),
    Slot(filename: "icon_128x128@2x.png", pixels: 256, logicalSize: 128, scale: 2),
    Slot(filename: "icon_256x256.png",   pixels: 256,  logicalSize: 256, scale: 1),
    Slot(filename: "icon_256x256@2x.png", pixels: 512, logicalSize: 256, scale: 2),
    Slot(filename: "icon_512x512.png",   pixels: 512,  logicalSize: 512, scale: 1),
    Slot(filename: "icon_512x512@2x.png", pixels: 1024, logicalSize: 512, scale: 2)
]

let defaultOutdir = "Resources/Assets.xcassets/AppIcon.appiconset"
let outdir = CommandLine.arguments.dropFirst().first ?? defaultOutdir

let fm = FileManager.default
try? fm.createDirectory(atPath: outdir, withIntermediateDirectories: true)

for slot in slots {
    guard let data = renderKitePNG(size: slot.pixels) else {
        FileHandle.standardError.write(Data("Failed to render \(slot.filename)\n".utf8))
        exit(1)
    }
    let outURL = URL(fileURLWithPath: "\(outdir)/\(slot.filename)")
    do {
        try data.write(to: outURL)
        print("Wrote \(slot.filename) (\(slot.pixels)x\(slot.pixels))")
    } catch {
        FileHandle.standardError.write(Data("Write failed for \(slot.filename): \(error)\n".utf8))
        exit(1)
    }
}

// Regenerate Contents.json to match exactly.
let imagesJSON = slots.map { slot -> String in
    """
        {
          "filename" : "\(slot.filename)",
          "idiom" : "mac",
          "scale" : "\(slot.scaleString)",
          "size" : "\(slot.sizeString)"
        }
    """.trimmingCharacters(in: .whitespacesAndNewlines)
}.joined(separator: ",\n    ")

let contents = """
{
  "images" : [
    \(imagesJSON)
  ],
  "info" : {
    "author" : "kite",
    "version" : 1
  }
}

"""

try contents.write(
    toFile: "\(outdir)/Contents.json",
    atomically: true,
    encoding: .utf8
)
print("Wrote Contents.json")
