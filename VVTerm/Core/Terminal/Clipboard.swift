//
//  Clipboard.swift
//  VVTerm
//
//  Shared pasteboard helper for text and image clipboard payloads
//

import UIKit
import UniformTypeIdentifiers

struct ClipboardImagePayload: Sendable {
    let data: Data
    let mimeType: String
    let utType: String
    let suggestedExtension: String

    nonisolated var sizeBytes: Int { data.count }
}

struct ClipboardSnapshot: Sendable {
    let text: String?
    let image: ClipboardImagePayload?

    nonisolated var hasText: Bool {
        guard let text else { return false }
        return !text.isEmpty
    }

    nonisolated var hasImage: Bool {
        image != nil
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    static func readString() -> String? {
        UIPasteboard.general.string
    }

    static func copy(lines: [String], separator: String = "\n") {
        copy(lines.joined(separator: separator))
    }

    @MainActor
    static func snapshot() -> ClipboardSnapshot {
        let pasteboard = UIPasteboard.general
        return ClipboardSnapshot(
            text: normalizedText(pasteboard.string),
            image: pasteboard.image.flatMap { encodedImagePayload(from: $0) }
        )
    }

    private static func normalizedText(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func encodedImagePayload(from image: UIImage) -> ClipboardImagePayload? {
        guard let data = image.pngData(), !data.isEmpty else { return nil }

        return ClipboardImagePayload(
            data: data,
            mimeType: UTType.png.preferredMIMEType ?? "image/png",
            utType: UTType.png.identifier,
            suggestedExtension: "png"
        )
    }
}
