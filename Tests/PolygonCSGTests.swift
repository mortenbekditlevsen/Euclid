//
//  PolygonCSGTests.swift
//  Euclid
//
//  Created by Nick Lockwood on 15/01/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

@testable import Euclid
import XCTest

class PolygonCSGTests: XCTestCase {
    // MARK: XOR

    func testXorCoincidingSquares() {
        let a = Path.square().facePolygons()[0]
        let b = Path.square().facePolygons()[0]
        let c = a.xor(b)
        XCTAssert(c.isEmpty)
    }

    func testXorAdjacentSquares() {
        let a = Path.square().facePolygons()[0]
        let b = a.translated(by: .unitX)
        let c = a.xor(b)
        XCTAssertEqual(Bounds(polygons: c), a.bounds.union(b.bounds))
    }

    func testXorOverlappingSquares() {
        let a = Path.square().facePolygons()[0]
        let b = a.translated(by: Vector(0.5, 0, 0))
        let c = a.xor(b)
        XCTAssertEqual(Bounds(polygons: c), Bounds(
            min: Vector(-0.5, -0.5, 0),
            max: Vector(1.0, 0.5, 0)
        ))
    }

    // MARK: Plane clipping

    func testSquareClippedToPlane() {
        let a = Path.square().facePolygons()[0]
        let plane = Plane(unchecked: .unitX, pointOnPlane: .zero)
        let b = a.clip(to: plane)
        XCTAssertEqual(Bounds(polygons: b), .init(Vector(0, -0.5), Vector(0.5, 0.5)))
    }

    func testPentagonClippedToPlane() {
        let a = Path.circle(segments: 5).facePolygons()[0]
        let plane = Plane(unchecked: .unitX, pointOnPlane: .zero)
        let b = a.clip(to: plane)
        XCTAssertEqual(Bounds(polygons: b), .init(
            Vector(0, -0.404508497187),
            Vector(0.475528258148, 0.5)
        ))
    }

    func testDiamondClippedToPlane() {
        let a = Path.circle(segments: 4).facePolygons()[0]
        let plane = Plane(unchecked: .unitX, pointOnPlane: .zero)
        let b = a.clip(to: plane)
        XCTAssertEqual(Bounds(polygons: b), .init(Vector(0, -0.5), Vector(0.5, 0.5)))
    }

    // MARK: Plane splitting

    func testSquareSplitAlongPlane() {
        let a = Path.square().facePolygons()[0]
        let plane = Plane(unchecked: .unitX, pointOnPlane: .zero)
        let b = a.split(along: plane)
        XCTAssertEqual(
            Bounds(polygons: b.0),
            .init(Vector(0, -0.5), Vector(0.5, 0.5))
        )
        XCTAssertEqual(
            Bounds(polygons: b.1),
            .init(Vector(-0.5, -0.5), Vector(0, 0.5))
        )
        XCTAssertEqual(b.front, b.0)
        XCTAssertEqual(b.back, b.1)
    }

    func testSquareSplitAlongItsOwnPlane() {
        let a = Path.square().facePolygons()[0]
        let plane = Plane(unchecked: .unitZ, pointOnPlane: .zero)
        let b = a.split(along: plane)
        XCTAssertEqual(b.front, [a])
        XCTAssert(b.back.isEmpty)
    }

    func testSquareSplitAlongReversePlane() {
        let a = Path.square().facePolygons()[0]
        let plane = Plane(unchecked: -.unitZ, pointOnPlane: .zero)
        let b = a.split(along: plane)
        XCTAssertEqual(b.back, [a])
        XCTAssert(b.front.isEmpty)
    }
}
