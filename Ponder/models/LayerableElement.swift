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
    var groupID: UUID? { get set }
    var x: Double { get set }
    var y: Double { get set }
    var updatedAt: Date { get set }

    var layerTitle: String { get }
    var layerIcon: String { get }
    var layerTint: Color { get }
}
