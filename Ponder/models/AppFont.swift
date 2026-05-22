//
//  AppFont.swift
//  Ponder
//

import SwiftUI

struct AppFont: Identifiable, Hashable {
    let id = UUID()
    let name: String          // PostScript name used by SwiftUI
    let displayName: String   // Shown to user in chip

    static let system = AppFont(name: "system", displayName: "System")

    static let allFonts: [AppFont] = [
        .system,
        AppFont(name: "BitcountGridDoubleRoman-ExtraBold", displayName: "Bitcount"),
        AppFont(name: "Lato-Regular",                      displayName: "Lato"),
        AppFont(name: "Montez-Regular",                    displayName: "Montez"),
        AppFont(name: "Poppins-Regular",                   displayName: "Poppins"),
    ]
}
