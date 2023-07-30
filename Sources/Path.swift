//
//  Paths.swift
//  Euclid
//
//  Created by Nick Lockwood on 03/07/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/Euclid
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

/// A path made up of a sequence of straight line segments between points.
///
/// A ``Path`` can be either open (a *polyline*) or closed (a *polygon*), but should not be
/// self-intersecting or otherwise degenerate.
///
/// A path may be formed from multiple subpaths, which can be accessed via the ``Path/subpaths`` property.
/// A closed ``Path`` can be converted to one or more ``Polygon``s, but it can also be used for other
/// purposes, such as defining a cross-section or profile of a 3D shape.
///
/// Paths are typically 2-dimensional, but because ``PathPoint`` positions have a Z coordinate, they are
/// not *required* to be. Even a flat ``Path`` (where all points lie on the same plane) can be translated or
/// rotated so that its points do not necessarily lie on the *XY* plane.
public struct Path: Hashable, Sendable {
    let subpathIndices: [Int]
    /// The array of points that makes up this path.
    public let points: [PathPoint]
    /// Indicates whether the path is a closed path.
    public let isClosed: Bool
    /// The plane upon which all path points lie. Will be nil for non-planar paths.
    public private(set) var plane: Plane?
}

extension Path: Codable {
    private enum CodingKeys: CodingKey {
        case points, subpaths
    }

    /// Creates a new path by decoding from the given decoder.
    /// - Parameter decoder: The decoder to read data from.
    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let points = try container.decodeIfPresent([PathPoint].self, forKey: .points)
            if var subpaths = try container.decodeIfPresent([Path].self, forKey: .subpaths) {
                if let points = points {
                    subpaths.insert(Path(points), at: 0)
                }
                self.init(subpaths: subpaths)
            } else {
                self.init(points ?? [])
            }
        } else {
            let points = try [PathPoint](from: decoder)
            self.init(points)
        }
    }

    /// Encodes this path into the given encoder.
    /// - Parameter encoder: The encoder to write data to.
    public func encode(to encoder: Encoder) throws {
        let subpaths = self.subpaths
        if subpaths.count < 2 {
            try (subpaths.first?.points ?? []).encode(to: encoder)
        } else {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(subpaths, forKey: .subpaths)
        }
    }
}

public extension Path {
    /// An empty path.
    static let empty: Path = .init([])

    /// Indicates whether all the path's points lie on a single plane.
    var isPlanar: Bool {
        plane != nil
    }

    /// The bounds of all the path's points.
    var bounds: Bounds {
        Bounds(points: points.map { $0.position })
    }

    /// The total length of the path.
    var length: Double {
        var prev = points.first?.position ?? .zero
        return points.dropFirst().reduce(0.0) {
            let position = $1.position
            defer { prev = position }
            return $0 + (position - prev).length
        }
    }

    /// The face normal for the path.
    ///
    /// > Note: If path is non-planar then this returns an average/approximate normal.
    var faceNormal: Vector {
        plane?.normal ?? faceNormalForPolygonPoints(
            points.map { $0.position },
            convex: nil,
            closed: isClosed
        )
    }

    /// Replace/remove path point colors.
    /// - Parameter color: The color to apply to each point in the path.
    func with(color: Color?) -> Path {
        Path(unchecked: points.map {
            $0.with(color: color)
        }, plane: plane, subpathIndices: subpathIndices)
    }

    /// Closes the path by joining last point to first.
    /// - Returns: A new path, or `self` if the path is already closed, or cannot be closed.
    func closed() -> Path {
        if isClosed || self.points.isEmpty {
            return self
        }
        var points = self.points
        points.append(points[0])
        return Path(unchecked: points, plane: plane, subpathIndices: nil)
    }

    /// Creates a path from an array of  path points.
    /// - Parameter points: An array of ``PathPoint`` making up the path.
    init(_ points: [PathPoint]) {
        self.init(
            unchecked: sanitizePoints(points),
            plane: nil,
            subpathIndices: nil
        )
    }

    /// Creates a composite path from an array of subpaths.
    /// - Parameter subpaths: An array of paths.
    init(subpaths: [Path]) {
        guard subpaths.count > 1 else {
            self = subpaths.first ?? .empty
            return
        }
        let points = subpaths.flatMap { $0.points }
        // Remove duplicate points
        // TODO: share logic with santizePoints function
        var result = [PathPoint]()
        for point in points {
            if let last = result.last, point.position == last.position {
                if !point.isCurved, last.isCurved {
                    result[result.count - 1].isCurved = false
                }
            } else {
                result.append(point)
            }
        }
        // TODO: precompute planes/subpathIndices from existing paths
        self.init(unchecked: result, plane: nil, subpathIndices: nil)
    }

    /// Creates a closed path from a polygon.
    /// - Parameter polygon: A ``Polygon`` to convert to a path.
    init(_ polygon: Polygon) {
        let hasTexcoords = polygon.hasTexcoords
        let hasVertexColors = polygon.hasVertexColors
        let points = polygon.vertices.map {
            PathPoint.point(
                $0.position,
                texcoord: hasTexcoords ? $0.texcoord : nil,
                color: hasVertexColors ? $0.color : nil
            )
        }
        self.init(
            unchecked: points + [points[0]],
            plane: polygon.plane,
            subpathIndices: nil
        )
    }

    @available(*, deprecated, message: "Use `init(_:)` instead")
    init(polygon: Polygon) {
        let hasTexcoords = polygon.hasTexcoords
        self.init(
            unchecked: polygon.vertices.map {
                .point($0.position, texcoord: hasTexcoords ? $0.texcoord : nil)
            },
            plane: polygon.plane,
            subpathIndices: nil
        )
    }

    /// An array of the subpaths that make up the path.
    ///
    /// For paths without nested subpaths, this will return an array containing only `self`.
    var subpaths: [Path] {
        var startIndex = 0
        var paths = [Path]()
        for i in subpathIndices {
            let points = self.points[startIndex ... i]
            startIndex = i
            guard points.count > 1 else {
                continue
            }
            // TODO: support internal one-element line segments
            guard points.count > 2 || points.startIndex == 0 || i == self.points.count - 1 else {
                continue
            }
            do {
                // TODO: do this as part of regular sanitization step
                var points = Array(points)
                if points.last?.position == points.first?.position {
                    points[0] = points.last!
                }
                paths.append(Path(unchecked: points, plane: plane, subpathIndices: []))
            }
        }
        return paths.isEmpty && !points.isEmpty ? [self] : paths
    }

    /// Returns one or more polygons needed to fill the path.
    /// - Parameter material: An optional ``Polygon/Material-swift.typealias`` to apply to the polygons.
    /// - Returns: An array of polygons needed to fill the path, or an empty array if path is not closed.
    ///
    /// > Note: Polygon normals are calculated automatically based on the curvature of the path points.
    /// If the path points do not include textcoords, they will be calculated automatically based on the
    /// path point positions relative to the bounding rectangle of the path.
    func facePolygons(material: Mesh.Material? = nil) -> [Polygon] {
        guard subpaths.count <= 1 else {
            return Polygon.xor(subpaths.flatMap { $0.facePolygons(material: material) })
        }
        guard let vertices = faceVertices else {
            return []
        }
        if plane != nil, let polygon = Polygon(vertices, material: material) {
            return [polygon]
        }
        return triangulateVertices(
            vertices,
            plane: nil,
            isConvex: nil,
            sanitizeNormals: false,
            material: material,
            id: 0
        ).detessellate(ensureConvex: false)
    }

    /// An array of vertices suitable for constructing a polygon from the path.
    ///
    /// > Note: Vertices include normals and uv coordinates normalized to the bounding
    /// rectangle of the path. Returns `nil` if path is not closed, or has subpaths.
    var faceVertices: [Vertex]? {
        let count = points.count
        guard isClosed, subpaths.count <= 1, count > 1 else {
            return nil
        }
        var hasTexcoords = true
        var vertices = [Vertex]()
        var p0 = points[count - 2]
        for i in 0 ..< count - 1 {
            let p1 = points[i]
            let texcoord = p1.texcoord
            hasTexcoords = hasTexcoords && texcoord != nil
            let normal = plane?.normal ?? faceNormalForPolygonPoints(
                [p0.position, p1.position, points[i + 1].position],
                convex: true,
                closed: isClosed
            )
            vertices.append(Vertex(
                unchecked: p1.position,
                normal,
                texcoord,
                p1.color
            ))
            p0 = p1
        }
        guard !verticesAreDegenerate(vertices) else {
            return nil
        }
        if hasTexcoords {
            return vertices
        }
        var min = Vector(.infinity, .infinity)
        var max = Vector(-.infinity, -.infinity)
        let flatteningPlane = self.flatteningPlane
        vertices = vertices.map {
            let uv = flatteningPlane.flattenPoint($0.position)
            min.x = Swift.min(min.x, uv.x)
            min.y = Swift.min(min.y, uv.y)
            max.x = Swift.max(max.x, uv.x)
            max.y = Swift.max(max.y, uv.y)
            return Vertex(unchecked: $0.position, $0.normal, uv, $0.color)
        }
        let uvScale = Vector(max.x - min.x, max.y - min.y)
        return vertices.map {
            let uv = Vector(
                ($0.texcoord.x - min.x) / uvScale.x,
                1 - ($0.texcoord.y - min.y) / uvScale.y,
                0
            )
            return Vertex(unchecked: $0.position, $0.normal, uv, $0.color)
        }
    }

    /// An array of vertices suitable for constructing a set of edge polygons for the path.
    ///
    /// > Note: Returns an empty array if the path has subpaths.
    var edgeVertices: [Vertex] {
        edgeVertices(for: .default)
    }

    /// An array of vertices suitable for constructing a set of edge polygons for the path.
    /// - Parameter wrapMode: The wrap mode to use for generating texture coordinates.
    /// - Returns: The edge vertices, or an empty array if path has subpaths.
    func edgeVertices(for wrapMode: Mesh.WrapMode) -> [Vertex] {
        guard subpaths.count <= 1, points.count >= 2 else {
            // TODO: does this actually match the documented behavior?
            return points.first.map { [Vertex($0)] } ?? []
        }

        // get path length
        var totalLength: Double = 0
        switch wrapMode {
        case .shrink, .default:
            var prev = points[0].position
            for point in points {
                let length = (point.position - prev).length
                totalLength += length
                prev = point.position
            }
        case .tube:
            var min = Double.infinity
            var max = -Double.infinity
            for point in points {
                min = Swift.min(min, point.position.y)
                max = Swift.max(max, point.position.y)
            }
            totalLength = max - min
        }

        let count = isClosed ? points.count - 1 : points.count
        var p1 = isClosed ? points[count - 1] : (
            count > 2 ?
                extrapolate(points[2], points[1], points[0]) :
                extrapolate(points[1], points[0])
        )
        var p2 = points[0]
        var p1p2 = p2.position - p1.position
        var n1: Vector!
        var vertices = [Vertex]()
        var v = 0.0
        let endIndex = count
        let faceNormal = self.faceNormal
        for i in 0 ..< endIndex {
            p1 = p2
            p2 = i < points.count - 1 ? points[i + 1] :
                (isClosed ? points[1] : (
                    count > 2 ?
                        extrapolate(points[i - 2], points[i - 1], points[i]) :
                        extrapolate(points[i - 1], points[i])
                ))
            let p0p1 = p1p2
            p1p2 = p2.position - p1.position
            let n0 = n1 ?? p0p1.cross(faceNormal).normalized()
            n1 = p1p2.cross(faceNormal).normalized()
            let uv = Vector(0, v, 0)
            switch wrapMode {
            case .shrink, .default:
                v += p1p2.length / totalLength
            case .tube:
                v += abs(p1p2.y) / totalLength
            }
            if p1.isCurved {
                let v = Vertex(
                    unchecked: p1.position,
                    (n0 + n1).normalized(),
                    uv,
                    p1.color
                )
                vertices.append(v)
                vertices.append(v)
            } else {
                vertices.append(Vertex(unchecked: p1.position, n0, uv, p1.color))
                vertices.append(Vertex(unchecked: p1.position, n1, uv, p1.color))
            }
        }
        var first = vertices.removeFirst()
        if isClosed {
            first.texcoord = Vector(0, v, 0)
            vertices.append(first)
        } else {
            vertices.removeLast()
        }
        return vertices
    }

    /// Applies a uniform inset to the edges of the path.
    /// - Parameter distance: The distance by which to inset the path edges.
    /// - Returns: A copy of the path, inset by the specified distance.
    ///
    /// > Note: Passing a negative `distance` will expand the path instead of shrinking it.
    func inset(by distance: Double) -> Path {
        guard subpaths.count <= 1, points.count >= 2 else {
            return Path(subpaths: subpaths.compactMap { $0.inset(by: distance) })
        }
        let count = points.count
        var p1 = isClosed ? points[count - 2] : (
            count > 2 ?
                extrapolate(points[2], points[1], points[0]) :
                extrapolate(points[1], points[0])
        )
        var p2 = points[0]
        var p1p2 = p2.position - p1.position
        var n1: Vector!
        return Path((0 ..< count).map { i in
            p1 = p2
            p2 = i < count - 1 ? points[i + 1] :
                (isClosed ? points[1] : (
                    count > 2 ?
                        extrapolate(points[i - 2], points[i - 1], points[i]) :
                        extrapolate(points[i - 1], points[i])
                ))
            let p0p1 = p1p2
            p1p2 = p2.position - p1.position
            let faceNormal = plane?.normal ?? p0p1.cross(p1p2).normalized()
            let n0 = n1 ?? p0p1.cross(faceNormal).normalized()
            n1 = p1p2.cross(faceNormal).normalized()
            // TODO: do we need to inset texcoord as well? If so, by how much?
            let normal = (n0 + n1).normalized()
            return p1.translated(by: normal * -(distance / n0.dot(normal)))
        })
    }
}

public extension Polygon {
    /// Creates a single polygon from a path.
    /// - Parameters
    ///   - shape: The ``Path`` to convert to a polygon.
    ///   - material: An optional ``Material-swift.typealias`` to apply to the polygon.
    ///
    /// Path may be convex or concave, but must be closed, planar and non-degenerate, and must not
    /// include subpaths. For a non-planar path, or one with subpaths, use ``Path/facePolygons(material:)``.
    init?(shape: Path, material: Material? = nil) {
        guard let vertices = shape.faceVertices, let plane = shape.plane else {
            return nil
        }
        self.init(
            unchecked: vertices,
            plane: plane,
            isConvex: nil,
            sanitizeNormals: false,
            material: material
        )
    }
}

internal extension Path {
    init(unchecked points: [PathPoint], plane: Plane?, subpathIndices: [Int]?) {
        self.points = points
        self.isClosed = pointsAreClosed(unchecked: points)
        let positions = isClosed ? points.dropLast().map { $0.position } : points.map { $0.position }
        let subpathIndices = subpathIndices ?? subpathIndicesFor(points)
        self.subpathIndices = subpathIndices
        if let plane = plane {
            self.plane = plane
            assert(positions.allSatisfy { plane.containsPoint($0) })
        } else if subpathIndices.isEmpty {
            self.plane = Plane(points: positions, convex: nil, closed: isClosed)
        } else {
            for path in subpaths {
                guard let plane = path.plane else {
                    self.plane = nil
                    break
                }
                if let existing = self.plane {
                    guard existing.isEqual(to: plane) else {
                        self.plane = nil
                        break
                    }
                }
                self.plane = plane
            }
        }
    }

    /// Does path contain vertex colors?
    var hasColors: Bool {
        points.contains(where: { $0.color != nil })
    }

    // Test if path is self-intersecting
    var isSimple: Bool {
        // TODO: what should we do about subpaths?
        !pointsAreSelfIntersecting(points.map { $0.position })
    }

    // Returns the most suitable FlatteningPlane for the path
    var flatteningPlane: FlatteningPlane {
        FlatteningPlane(normal: faceNormal)
    }

    // TODO: Make this more robust, then make public
    // TODO: Could this make use of Polygon.area?
    var hasZeroArea: Bool {
        points.count < (isClosed ? 4 : 3)
    }

    // flattens z-axis
    // TODO: this is a hack and should be replaced by a better solution
    func flattened() -> Path {
        guard subpathIndices.isEmpty else {
            return Path(subpaths: subpaths.map { $0.flattened() })
        }
        if points.allSatisfy({ $0.position.z == 0 }) {
            return self
        }
        let flatteningPlane = self.flatteningPlane
        return Path(unchecked: sanitizePoints(points.map {
            PathPoint(
                flatteningPlane.flattenPoint($0.position),
                texcoord: $0.texcoord,
                color: $0.color,
                isCurved: $0.isCurved
            )
        }), plane: .xy, subpathIndices: [])
    }

    func clippedToYAxis() -> Path {
        guard subpathIndices.isEmpty else {
            return Path(subpaths: subpaths.map { $0.clippedToYAxis() })
        }
        var points = self.points
        guard !points.isEmpty else {
            return self
        }
        // flip path if it mostly lies right of the origin
        var leftOfOrigin = 0
        var rightOfOrigin = 0
        for p in points {
            if p.position.x > 0 {
                rightOfOrigin += 1
            } else if p.position.x < 0 {
                leftOfOrigin += 1
            }
        }
        if isClosed {
            if points[0].position.x > 0 {
                rightOfOrigin -= 1
            } else if points[0].position.x < 0 {
                leftOfOrigin -= 1
            }
        }
        if rightOfOrigin > leftOfOrigin {
            // Mirror the path about Y axis
            points = points.map {
                var point = $0
                point.position.x = -point.position.x
                return point
            }
        }
        // clip path to Y axis
        var i = points.count - 1
        while i > 0 {
            let p0 = points[i]
            let p1 = points[i - 1]
            if p0.position.x > 0 {
                if p0 == p1 {
                    points.remove(at: i)
                } else if abs(p1.position.x) < epsilon {
                    points.remove(at: i)
                } else if p1.position.x > 0 {
                    points.remove(at: i)
                    points.remove(at: i - 1)
                    i -= 1
                } else {
                    let p0p1 = p0.position - p1.position
                    let dy = p0p1.y / p0p1.x * -p1.position.x
                    points[i].position = Vector(0, p1.position.y + dy)
                    continue
                }
            } else if p1.position.x > 0 {
                if p1 == p0 {
                    points.remove(at: i - 1)
                } else if p0.position.x >= 0 {
                    if i == 1 ||
                        (p1.position.y == p0.position.y && p1.position.z == p0.position.z)
                    {
                        points.remove(at: i - 1)
                    }
                } else {
                    let p0p1 = p1.position - p0.position
                    let dy = p0p1.y / p0p1.x * -p0.position.x
                    points[i - 1].position = Vector(0, p0.position.y + dy)
                    continue
                }
            }
            i -= 1
        }
        return Path(
            unchecked: points,
            plane: nil, // Might have changed if path is self-intersecting
            subpathIndices: nil
        )
    }

    /// Approximate equality
    func isEqual(to other: Path, withPrecision p: Double = epsilon) -> Bool {
        points.count == other.points.count && zip(points, other.points).allSatisfy {
            $0.isEqual(to: $1, withPrecision: p)
        }
    }

    // Returns the path with its first point recentered on the origin
    func withNormalizedPosition() -> (path: Path, offset: Vector) {
        guard let offset = points.first?.position, offset != .zero else {
            return (self, .zero)
        }
        return (translated(by: -offset), offset)
    }
}

public extension Path {
    /// Efficiently forms a union from multiple paths.
    /// - Parameters
    ///   - paths: A collection of paths to be unioned.
    /// - Returns: An array of paths representing the union of the input paths.
    static func union<T: Collection>(_ paths: T) -> [Path] where T.Element == Path {
//        let paths = paths.flatMap { Path.xor($0.subpaths) }
        guard let first = paths.first, paths.count > 1 else { return Array(paths) }
        var polygons = first.facePolygons()
        for path in paths.dropFirst() {
            for polygon in path.facePolygons() {
                var inside = [Polygon](), outside = [Polygon](), id = 0
                polygon.clip(to: polygons, &inside, &outside, &id)
                polygons += outside
            }
        }
        return [Path(
            subpaths: polygons
                .makeWatertight(with: polygons.holeEdges)
                .edgePaths(withOriginalPaths: paths)
        )]
    }

    /// Efficiently gets the difference between multiple paths.
    /// - Parameters
    ///   - paths: An ordered collection of paths. All but the first will be subtracted from the first.
    /// - Returns: An array of paths representing the difference between the input paths.
    static func difference<T: Collection>(_ paths: T) -> [Path] where T.Element == Path {
        let paths = paths.flatMap { $0.subpaths }
        guard let first = paths.first, paths.count > 1 else { return paths }
        var polygons = first.facePolygons()
        for path in paths.dropFirst() {
            var inside = [Polygon](), outside = [Polygon](), id = 0
            let rhs = path.facePolygons()
            for polygon in polygons {
                polygon.clip(to: rhs, &inside, &outside, &id)
            }
            polygons = outside
        }
        return polygons
            .makeWatertight(with: polygons.holeEdges)
            .edgePaths(withOriginalPaths: paths)
    }

    /// Efficiently XORs multiple paths.
    /// - Parameters
    ///   - paths: A collection of paths to be XORed.
    /// - Returns: An array of paths representing the XOR of the input paths.
    static func xor<T: Collection>(_ paths: T) -> [Path] where T.Element == Path {
        let paths = Array(paths)
        guard paths.count == 2, paths.allSatisfy({ $0.subpaths.count == 1 }) else {
            guard paths.count == 1, paths[0].subpaths.count == 2 else {
                preconditionFailure()
            }
            return xor(paths[0].subpaths)
        }
        var result = [Path]()
        let lhs = paths.first!.facePolygons()
        let rhs = paths.last!.facePolygons()
        var inside = [Polygon](), outside = [Polygon](), id = 0
        for polygon in lhs {
            polygon.clip(to: rhs, &inside, &outside, &id)
        }
        result += outside
            .makeWatertight(with: outside.holeEdges)
            .edgePaths(withOriginalPaths: paths)
        outside.removeAll()
        for polygon in rhs {
            polygon.clip(to: lhs, &inside, &outside, &id)
        }
        result += outside
            .makeWatertight(with: outside.holeEdges)
            .edgePaths(withOriginalPaths: paths)
        return [Path(subpaths: result)]
    }
}

private extension Array where Element == Polygon {
    func edgePaths<T: Collection>(withOriginalPaths paths: T) -> [Path] where T.Element == Path {
        var pointMap = Dictionary(paths.flatMap { path -> [(Vector, PathPoint)] in
            path.points.map { ($0.position, $0) }
        }, uniquingKeysWith: {
            $0.lerp($1, 0.5)
        })
        var polylines = [[Vector]]()
        var edges = holeEdges.sorted()
        while let edge = edges.popLast() {
            var polyline = [edge.start, edge.end]
            while let i = edges.firstIndex(where: {
                polyline.first!.isEqual(to: $0.start) ||
                    polyline.last!.isEqual(to: $0.start) ||
                    polyline.first!.isEqual(to: $0.end) ||
                    polyline.last!.isEqual(to: $0.end)
            }) {
                let edge = edges.remove(at: i)
                if polyline.first!.isEqual(to: edge.start) {
                    polyline.insert(edge.end, at: 0)
                } else if polyline.last!.isEqual(to: edge.start) {
                    polyline.append(edge.end)
                } else if polyline.first!.isEqual(to: edge.end) {
                    polyline.insert(edge.start, at: 0)
                } else if polyline.last!.isEqual(to: edge.end) {
                    polyline.append(edge.start)
                }
            }
            polylines.append(polyline)
        }
        // TODO: this is just to recover texcoords/colors - find more efficient solution
        for polygon in self {
            for vertex in polygon.vertices {
                if pointMap[vertex.position] == nil {
                    pointMap[vertex.position] = PathPoint(vertex)
                }
            }
        }
        return polylines.map { Path($0.map { pointMap[$0] ?? .point($0) }) }
    }
}
