#!/usr/bin/env swift
// Renders the neutral placeholder icon: a system-font 가 on a plain gray keycap.
// Usage: swift Scripts/generate_icon.swift [output.png]
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let output = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(gray: 0.90, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: size, height: size))
// iOS masks the corners; the key face is an inset rounded square.
let face = CGRect(x: 152, y: 172, width: 720, height: 720)
context.setFillColor(gray: 1, alpha: 1)
context.addPath(CGPath(roundedRect: face, cornerWidth: 120, cornerHeight: 120, transform: nil)); context.fillPath()
let font = CTFontCreateUIFontForLanguage(.system, 440, "ko" as CFString)!
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "가", attributes: [kCTFontAttributeName as NSAttributedString.Key: font, kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0.18, alpha: 1)]))
let glyphs = CTLineGetImageBounds(line, context)
context.textPosition = CGPoint(x: face.midX - glyphs.midX, y: face.midY - glyphs.midY)
CTLineDraw(line, context)
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("Wrote", output.path)
