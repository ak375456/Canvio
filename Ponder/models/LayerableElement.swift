//
//  LayerableElement.swift
//  Ponder
//

import SwiftUI
import SwiftData

protocol LayerableElement: AnyObject {
    var id: UUID { get }
    var zIndex: Int { get set }
    var canvasID: UUID { get }
    var updatedAt: Date { get set }

    var layerTitle: String { get }
    var layerIcon: String { get }
    var layerTint: Color { get }
}
