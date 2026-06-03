//
//  AppFont.swift
//  Ponder
//

import Combine
import CoreText
import Foundation
import SwiftUI

struct AppFont: Identifiable, Hashable {
    let name: String          // PostScript name used by SwiftUI
    let displayName: String   // Shown to user in chip
    var isCustom: Bool = false

    var id: String { name }

    static let system = AppFont(name: "system", displayName: "System")

    static let bundledFonts: [AppFont] = [
        .system,
        AppFont(name: "BitcountGridDoubleRoman-ExtraBold", displayName: "Bitcount"),
        AppFont(name: "Lato-Regular",                      displayName: "Lato"),
        AppFont(name: "Montez-Regular",                    displayName: "Montez"),
        AppFont(name: "Poppins-Regular",                   displayName: "Poppins"),
    ]

    static let allFonts: [AppFont] = bundledFonts
}

enum AppFontImportError: LocalizedError {
    case unsupportedFormat
    case unreadableFile
    case noUsableFont

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Please choose a .ttf font file."
        case .unreadableFile:
            return "Canvio could not read that font file."
        case .noUsableFont:
            return "That file does not contain a usable TrueType font."
        }
    }
}

enum AppFontRegistry {
    private static let customFontsFolderName = "Custom Fonts"

    static func registerBundledFonts() {
        guard let resourcePath = Bundle.main.resourcePath else { return }
        let resourceURL = URL(fileURLWithPath: resourcePath)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: resourcePath) else { return }

        for file in files where file.lowercased().hasSuffix(".ttf") {
            _ = registerFont(at: resourceURL.appendingPathComponent(file))
        }
    }

    static func registerStoredCustomFonts() {
        _ = storedCustomFonts()
    }

    static func storedCustomFonts() -> [AppFont] {
        guard let directoryURL = customFontsDirectoryURL(createIfNeeded: true),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }

        let fonts = files
            .filter { $0.pathExtension.lowercased() == "ttf" }
            .flatMap { registerFont(at: $0, isCustom: true) }

        return uniqueFonts(fonts).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    static func importFont(from sourceURL: URL) throws -> [AppFont] {
        guard sourceURL.pathExtension.lowercased() == "ttf" else {
            throw AppFontImportError.unsupportedFormat
        }

        let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let sourceFonts = fontDescriptors(at: sourceURL, isCustom: true)
        guard !sourceFonts.isEmpty else { throw AppFontImportError.noUsableFont }

        guard let directoryURL = customFontsDirectoryURL(createIfNeeded: true) else {
            throw AppFontImportError.unreadableFile
        }

        let destinationURL = uniqueDestinationURL(
            in: directoryURL,
            preferredFileName: sourceURL.lastPathComponent
        )

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw AppFontImportError.unreadableFile
        }

        let importedFonts = registerFont(at: destinationURL, isCustom: true)
        guard !importedFonts.isEmpty else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw AppFontImportError.noUsableFont
        }

        return importedFonts
    }

    @discardableResult
    private static func registerFont(at url: URL, isCustom: Bool = false) -> [AppFont] {
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        return fontDescriptors(at: url, isCustom: isCustom)
    }

    private static func fontDescriptors(at url: URL, isCustom: Bool) -> [AppFont] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }

        return descriptors.compactMap { descriptor in
            guard let postScriptName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontNameAttribute
            ) as? String else {
                return nil
            }

            let displayName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontDisplayNameAttribute
            ) as? String
            let familyName = CTFontDescriptorCopyAttribute(
                descriptor,
                kCTFontFamilyNameAttribute
            ) as? String

            return AppFont(
                name: postScriptName,
                displayName: cleanedDisplayName(displayName ?? familyName ?? postScriptName),
                isCustom: isCustom
            )
        }
    }

    private static func customFontsDirectoryURL(createIfNeeded: Bool) -> URL? {
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directoryURL = documentsURL.appendingPathComponent(customFontsFolderName, isDirectory: true)
        if createIfNeeded {
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private static func uniqueDestinationURL(in directoryURL: URL, preferredFileName: String) -> URL {
        let safeName = preferredFileName
            .components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>"))
            .joined(separator: "-")
        let baseName = URL(fileURLWithPath: safeName).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: safeName).pathExtension.isEmpty
            ? "ttf"
            : URL(fileURLWithPath: safeName).pathExtension

        var candidate = directoryURL.appendingPathComponent("\(baseName).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(baseName) \(index).\(ext)")
            index += 1
        }
        return candidate
    }

    private static func uniqueFonts(_ fonts: [AppFont]) -> [AppFont] {
        var seen = Set<String>()
        return fonts.filter { seen.insert($0.name).inserted }
    }

    private static func cleanedDisplayName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class CustomFontStore: ObservableObject {
    static let shared = CustomFontStore()

    @Published private(set) var customFonts: [AppFont] = []

    var allFonts: [AppFont] {
        AppFont.bundledFonts + customFonts
    }

    private init() {
        reload()
    }

    func reload() {
        customFonts = AppFontRegistry.storedCustomFonts()
    }

    func importFont(from url: URL) throws -> AppFont {
        let importedFonts = try AppFontRegistry.importFont(from: url)
        reload()
        return importedFonts.first ?? customFonts.first ?? .system
    }
}
