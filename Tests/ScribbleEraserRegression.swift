// Run on macOS: Tests/run-scribble-regressions.sh
import Foundation
import PencilKit
import AppKit

@main
struct ScribbleEraserRegression {
    static func main() {
        let scratch = (0...6).map { CGPoint(x: $0.isMultiple(of: 2) ? 20 : 140, y: 20 + $0 * 10) }
        let ink = stroke([CGPoint(x: 0, y: 50), CGPoint(x: 160, y: 50)])
        let otherInk = stroke([CGPoint(x: 250, y: 250), CGPoint(x: 350, y: 250)])
        let before = PKDrawing(strokes: [ink, otherInk])
        let scribble = stroke(scratch)
        let drawing = PKDrawing(strokes: before.strokes + [scribble])
        let result = ScribbleEraser.eraseLatestStroke(in: drawing, since: DrawingStrokeBaseline(drawing: before))
        expect(result != nil, "Repeated passes over ink are recognized")
        expect(result?.after.strokes.count == 1, "Only touched ink is erased")
        expect(result?.before.strokes.count == 2, "Undo snapshot excludes the scratch")
        expect(result?.after.strokes.first?.path.creationDate == otherInk.path.creationDate,
               "Unrelated strokes retain their identity")

        let empty = PKDrawing()
        expect(ScribbleEraser.eraseLatestStroke(in: PKDrawing(strokes: [scribble]),
               since: DrawingStrokeBaseline(drawing: empty)) == nil, "Scratching blank space keeps the ink")
        expect(ScribbleEraser.eraseLatestStroke(in: before, since: DrawingStrokeBaseline(drawing: before)) == nil,
               "An unchanged drawing isn't interpreted as a new gesture")

        let line = (0...30).map { CGPoint(x: $0 * 5, y: 20) }
        expect(ScribbleEraseGesture(points: line) == nil, "Straight lines stay ink")
        let circle = (0...100).map { index in
            let angle = CGFloat(index) * .pi * 2 / 100
            return CGPoint(x: 70 + 50 * cos(angle), y: 70 + 50 * sin(angle))
        }
        expect(ScribbleEraseGesture(points: circle) == nil, "Circles stay ink")
        expect(ScribbleEraseGesture(points: Array(scratch.prefix(4))) == nil, "Short zigzags stay ink")
        let arrow = [CGPoint(x: 0, y: 50), CGPoint(x: 120, y: 50), CGPoint(x: 100, y: 30),
                     CGPoint(x: 120, y: 50), CGPoint(x: 100, y: 70), CGPoint(x: 120, y: 50)]
        expect(ScribbleEraseGesture(points: arrow) == nil, "Arrows stay ink")
        let jitter = (0...100).map { CGPoint(x: $0, y: $0.isMultiple(of: 2) ? 0 : 2) }
        expect(ScribbleEraseGesture(points: jitter) == nil, "Small hand jitter stays ink")
        let retracedLine = (0...6).map { CGPoint(x: $0.isMultiple(of: 2) ? 20 : 140, y: 50) }
        expect(ScribbleEraseGesture(points: retracedLine)?.erasingStrokes(in: before).strokes.count == 1,
               "Repeated horizontal scratching can erase without vertical drift")

        let gesture = ScribbleEraseGesture(points: scratch)!
        let firstPassOnly = stroke([CGPoint(x: 35, y: 15), CGPoint(x: 45, y: 15)], width: 1)
        expect(gesture.erasingStrokes(in: PKDrawing(strokes: [firstPassOnly])).strokes.count == 1,
               "One incidental contact is insufficient")
        let transform = CGAffineTransform(rotationAngle: .pi / 3).translatedBy(x: 210, y: 70)
        let rotatedGesture = ScribbleEraseGesture(points: scratch.map { $0.applying(transform) })!
        let rotatedInk = before.transformed(using: transform)
        expect(rotatedGesture.erasingStrokes(in: rotatedInk).strokes.count == 1,
               "Rotated and translated ink uses the same target geometry")
        for scale: CGFloat in [0.25, 0.55, 2, 5] {
            let zoomTransform = CGAffineTransform(scaleX: scale, y: scale)
            let zoomGesture = ScribbleEraseGesture(points: scratch.map { $0.applying(zoomTransform) }, viewScale: 1 / scale)!
            expect(zoomGesture.erasingStrokes(in: before.transformed(using: zoomTransform)).strokes.count == 1,
                   "Recognition and targeting are consistent at scale \(scale)")
        }

        let hiddenMask = NSBezierPath(rect: CGRect(x: 500, y: 500, width: 10, height: 10))
        let masked = PKStroke(ink: ink.ink, path: ink.path, transform: ink.transform, mask: hiddenMask)
        expect(gesture.erasingStrokes(in: PKDrawing(strokes: [masked])).strokes.count == 1,
               "Already erased portions aren't targets")
        let invisiblePreview = stroke(scratch, alpha: 0.001)
        expect(ScribbleEraser.eraseLatestStroke(in: PKDrawing(strokes: [ink, invisiblePreview]),
               since: DrawingStrokeBaseline(drawing: PKDrawing(strokes: [ink]))) != nil,
               "Patterned and gradient preview source strokes are recognized")

        let targetID = UUID()
        let crossDrawing = ScribbleEraser.eraseLatestStroke(
            in: PKDrawing(strokes: [scribble]), since: DrawingStrokeBaseline(drawing: empty),
            additionalTargets: { [ScribbleEraseTarget(id: targetID, drawing: before)] }
        )
        expect(crossDrawing?.after.strokes.isEmpty == true, "An erase over saved drawings doesn't create a new object")
        expect(crossDrawing?.externalTargets.first?.id == targetID, "External targets retain their object IDs")
        expect(crossDrawing?.externalTargets.first?.drawing.strokes.count == 1, "Saved drawings lose only touched ink")

        let firstPoint = PKStroke(ink: scribble.ink,
                                 path: PKStrokePath(controlPoints: [scribble.path[0]], creationDate: scribble.path.creationDate))
        let provisionalBaseline = DrawingStrokeBaseline(drawing: PKDrawing(strokes: before.strokes + [firstPoint]))
        expect(ScribbleEraser.eraseLatestStroke(in: drawing, since: provisionalBaseline) != nil,
               "A provisional point delivered before tool-begin doesn't hide the gesture")
        var requestedExternalTargets = false
        _ = ScribbleEraser.eraseLatestStroke(
            in: PKDrawing(strokes: [ink, stroke(line)]), since: DrawingStrokeBaseline(drawing: PKDrawing(strokes: [ink])),
            additionalTargets: { requestedExternalTargets = true; return [] }
        )
        expect(!requestedExternalTargets, "Ordinary writing doesn't scan saved drawings")
        let laterInk = stroke([CGPoint(x: 80, y: 35), CGPoint(x: 80, y: 70)])
        let rapidBatch = PKDrawing(strokes: [ink, scribble, laterInk])
        let rapidResult = ScribbleEraser.erasePendingStrokes(
            in: rapidBatch,
            since: [DrawingStrokeBaseline(drawing: PKDrawing(strokes: [ink])),
                    DrawingStrokeBaseline(drawing: PKDrawing(strokes: [ink, scribble]))]
        )
        expect(rapidResult?.after.strokes.count == 1, "Continuing immediately doesn't cancel scribble recognition")
        expect(rapidResult?.after.strokes.first?.path.creationDate == laterInk.path.creationDate,
               "Ink drawn after the scratch survives even inside its bounds")
        expect(rapidResult?.before.strokes.count == 2, "A batched Undo restores ink without restoring the scratch")
        let shiftedScratch = stroke(scratch.map { CGPoint(x: $0.x + 250, y: $0.y + 200) })
        let secondBatch = PKDrawing(strokes: [ink, otherInk, scribble, shiftedScratch])
        let multiResult = ScribbleEraser.erasePendingStrokes(
            in: secondBatch,
            since: [DrawingStrokeBaseline(drawing: before),
                    DrawingStrokeBaseline(drawing: PKDrawing(strokes: before.strokes + [scribble]))]
        )
        expect(multiResult?.after.strokes.isEmpty == true, "Multiple scratches in one batch erase their own targets")
        expect(multiResult?.before.strokes.count == 2, "Batch snapshots exclude all successful erase gestures")
        expect(ScribbleEraser.eraseLatestStroke(
            in: PKDrawing(strokes: [ink, stroke(scratch, duration: 4)]),
            since: DrawingStrokeBaseline(drawing: PKDrawing(strokes: [ink]))) == nil,
            "Slow deliberate sketches stay ink")
        print("Passed \(checks) scribble-to-erase regression checks.")
    }

    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }

    private static func stroke(_ vertices: [CGPoint], width: CGFloat = 3,
                               alpha: CGFloat = 1, duration: TimeInterval = 0.8) -> PKStroke {
        var locations: [CGPoint] = []
        for (start, end) in zip(vertices, vertices.dropFirst()) {
            for index in 0..<20 {
                let t = CGFloat(index) / 20
                locations.append(CGPoint(x: start.x + (end.x - start.x) * t,
                                         y: start.y + (end.y - start.y) * t))
            }
        }
        locations.append(vertices.last!)
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: duration * Double(index) / Double(locations.count - 1),
                          size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: NSColor.black.withAlphaComponent(alpha)),
                        path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }
}
