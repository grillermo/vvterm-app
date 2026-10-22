//
//  TerminalAccessoryGutterGeometry+iOS.swift
//  VVTermUITests
//
//  Screen-space accessory gutter geometry parsing for UI tests.
//

import UIKit
import XCTest

/// Parses the harness's screen-space accessory diagnostics and states the
/// spec's geometry as checkable rules. All frames are in screen points.
struct TerminalAccessoryGutterGeometry {
    let accessory: CGRect
    let controls: CGRect
    let terminal: CGRect
    let screen: CGRect
    let safeAreaBottom: Double
    let backgroundHex: String

    init?(diagnostics: String) {
        func token(_ key: String) -> String? {
            diagnostics.split(separator: " ")
                .first { $0.hasPrefix("\(key)=") }
                .map { String($0.dropFirst(key.count + 1)) }
        }
        func rect(_ key: String) -> CGRect? {
            guard let raw = token(key), raw != "none" else { return nil }
            let values = raw.split(separator: ",").compactMap { Double($0) }
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        guard let accessory = rect("accessoryScreenFrame"),
              let controls = rect("accessoryControlsScreenFrame"),
              let terminal = rect("terminalScreenFrame"),
              let screen = rect("screenBounds"),
              let safeAreaBottom = token("windowSafeAreaBottom").flatMap(Double.init),
              let backgroundHex = token("accessoryBackgroundHex") else {
            return nil
        }
        self.accessory = accessory
        self.controls = controls
        self.terminal = terminal
        self.screen = screen
        self.safeAreaBottom = safeAreaBottom
        self.backgroundHex = backgroundHex
    }

    /// Empty when the layout matches the spec. `bottomBoundaryY` is the
    /// screen's max Y for case (a) or the software keyboard's min Y for (b).
    func violations(barHeight: Double, gutterHeight: Double, bottomBoundaryY: Double) -> [String] {
        let tolerance = 1.0
        var result: [String] = []
        if abs(controls.minY - accessory.minY) > tolerance {
            result.append("space between accessory top and controls: controls.minY=\(controls.minY) accessory.minY=\(accessory.minY)")
        }
        if abs(controls.height - barHeight) > tolerance {
            result.append("control row height \(controls.height) != \(barHeight)")
        }
        let gutter = accessory.maxY - controls.maxY
        if abs(gutter - gutterHeight) > tolerance {
            result.append("gutter below controls \(gutter) != \(gutterHeight)")
        }
        if terminal.maxY < accessory.minY - tolerance {
            result.append("gap between terminal and bar: terminal.maxY=\(terminal.maxY) accessory.minY=\(accessory.minY)")
        }
        if terminal.maxY > accessory.minY + tolerance {
            result.append("bar overlays terminal: terminal.maxY=\(terminal.maxY) accessory.minY=\(accessory.minY)")
        }
        if accessory.maxY > bottomBoundaryY + tolerance {
            result.append("accessory extends past bottom boundary: accessory.maxY=\(accessory.maxY) boundary=\(bottomBoundaryY)")
        }
        if accessory.maxY > screen.maxY + tolerance {
            result.append("accessory extends off screen: accessory.maxY=\(accessory.maxY) screen.maxY=\(screen.maxY)")
        }
        return result
    }

    /// Reads one screenshot pixel at a point given in screen points.
    static func pixelHex(in image: UIImage, at point: CGPoint) -> String? {
        guard let cgImage = image.cgImage, image.size.width > 0 else { return nil }
        let scale = CGFloat(cgImage.width) / image.size.width
        let pixelX = Int(point.x * scale)
        let pixelY = Int(point.y * scale)
        guard pixelX >= 0, pixelY >= 0, pixelX < cgImage.width, pixelY < cgImage.height,
              let cropped = cgImage.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)) else {
            return nil
        }
        var rgba = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return String(format: "%02X%02X%02X", rgba[0], rgba[1], rgba[2])
    }

    /// First y, scanning down in 1pt steps, whose screenshot pixel no longer
    /// matches `backgroundHex`: the visible bottom edge of the gutter. Used
    /// instead of `XCUIElement.frame` for the software keyboard, whose
    /// reported minY sits below the keyboard's visible top.
    static func visibleBottomBoundaryY(
        in image: UIImage,
        x: CGFloat,
        from startY: CGFloat,
        to endY: CGFloat,
        backgroundHex: String
    ) -> CGFloat {
        var y = startY
        while y < endY {
            guard let pixel = pixelHex(in: image, at: CGPoint(x: x, y: y)),
                  hex(pixel, matches: backgroundHex) else { return y }
            y += 1
        }
        return endY
    }

    /// Per-channel tolerance absorbs sRGB/P3 conversion in screenshots.
    static func hex(_ lhs: String, matches rhs: String, tolerance: Int = 8) -> Bool {
        func channels(_ hex: String) -> [Int]? {
            guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
            return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF]
        }
        guard let left = channels(lhs), let right = channels(rhs) else { return false }
        return zip(left, right).allSatisfy { abs($0 - $1) <= tolerance }
    }
}
