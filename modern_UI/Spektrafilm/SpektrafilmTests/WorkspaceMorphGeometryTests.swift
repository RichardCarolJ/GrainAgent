import XCTest
import CoreGraphics

final class WorkspaceMorphGeometryTests: XCTestCase {
    func testEaseDoesNotCreateNegativeGeometryAtRoundedEndpoints() {
        // Build 28 yields 1.000000000000002 here, then a negative corner radius.
        let samples = [0.0, 0.0000000762, 0.5, 0.9999999238, 1.0.nextDown, 1.0]
        for sample in samples {
            let q = WorkspaceMorphGeometry.ease(sample)
            XCTAssertTrue(q.isFinite)
            XCTAssertGreaterThanOrEqual(q, 0)
            XCTAssertLessThanOrEqual(q, 1)
            XCTAssertGreaterThanOrEqual(sin(q * .pi) * 18, 0)
            XCTAssertGreaterThanOrEqual(1200 * (1 - q), 0)
        }
        XCTAssertEqual(WorkspaceMorphGeometry.ease(0), 0)
        XCTAssertEqual(WorkspaceMorphGeometry.ease(1), 1)
        XCTAssertEqual(WorkspaceMorphGeometry.ease(0.5), 0.5)
    }

    func testInvalidProgressCannotReachCoreGraphics() {
        for value in [Double.nan, -.infinity, .infinity, -1, 2] {
            let q = WorkspaceMorphGeometry.ease(value)
            XCTAssertTrue(q.isFinite && q >= 0 && q <= 1)
        }
    }

    func testSmallAndInvalidRectanglesHaveValidMasks() {
        let rect = CGRect(x: 4, y: 9, width: 1, height: 0.25)
        XCTAssertEqual(WorkspaceMorphGeometry.cornerRadius(28, in: rect), 0.125)
        for radius: CGFloat in [-1, -.ulpOfOne, 0, 28, .nan, .infinity] {
            let path = WorkspaceMorphGeometry.roundedRect(rect, radius: radius)
            XCTAssertFalse(path.isEmpty)
            XCTAssertEqual(path.boundingBoxOfPath, rect)
        }
        for rect in [CGRect.zero, .null, .infinite,
                     CGRect(x: 0, y: 0, width: -1, height: 20),
                     CGRect(x: CGFloat.nan, y: 0, width: 10, height: 20)] {
            XCTAssertTrue(WorkspaceMorphGeometry.roundedRect(rect, radius: 28).isEmpty)
        }
    }

    func testBothDirectionsAndStaggeredPanelsKeepLegalMasks() {
        for i in 0...2000 {
            for progress in [Double(i) / 2000, 1 - Double(i) / 2000] {
                for delay in [0.0, 0.02, 0.025, 0.06] {
                    let q = WorkspaceMorphGeometry.ease((progress - delay) / (1 - delay))
                    let rect = CGRect(x: 0, y: 0, width: 1 + 300 * q, height: 1 + 200 * (1 - q))
                    let radius = WorkspaceMorphGeometry.cornerRadius(sin(q * .pi) * 18, in: rect)
                    XCTAssertTrue(radius.isFinite && radius >= 0 && radius <= min(rect.width, rect.height) / 2)
                    XCTAssertFalse(WorkspaceMorphGeometry.roundedRect(rect, radius: radius).isEmpty)
                }
            }
        }
    }
}
