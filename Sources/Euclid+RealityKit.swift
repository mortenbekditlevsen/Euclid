//
//  Euclid+RealityKit.swift
//  Euclid
//
//  Created by Nick Lockwood on 05/10/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
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

#if canImport(RealityKit) && swift(>=5.4)

import CoreGraphics
import RealityKit

@available(macOS 10.15, iOS 13.0, *)
public extension RealityKit.Transform {
    init(_ transform: Euclid.Transform) {
        self.init(
            scale: .init(transform.scale),
            rotation: .init(transform.rotation),
            translation: .init(transform.offset)
        )
    }
}

@available(macOS 12.0, iOS 15.0, *)
private func defaultMaterialLookup(_ material: Polygon.Material?) -> RealityKit.Material? {
    switch material {
    case let material as RealityKit.Material:
        return material
    case let color as Color:
        return defaultMaterialLookup(OSColor(color))
    case let color as OSColor:
        var material = SimpleMaterial()
        material.color = .init(tint: color)
        return material
    case let color as CGColor where CFGetTypeID(color) == CGColor.typeID:
        return defaultMaterialLookup(OSColor(cgColor: color))
    case let image as OSImage:
        return defaultMaterialLookup(image.cgImage)
    case let image as CGImage where CFGetTypeID(image) == CGImage.typeID:
        guard let texture = try? TextureResource.generate(
            from: image,
            options: .init(semantic: .color)
        ) else {
            return nil
        }
        var material = SimpleMaterial()
        material.color = .init(texture: .init(texture))
        return material
    default:
        return nil
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension MeshDescriptor {
    private typealias SIMDVertexData = (
        positions: [simd_float3],
        normals: [simd_float3],
        texcoords: [simd_float2],
        indices: [UInt32],
        materialIndices: [UInt32]
    )

    /// Creates a mesh descriptor from a ``Mesh`` using triangles.
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit mesh descriptor.
    init(triangles mesh: Mesh) {
        self.init()
        var counts: [UInt8]?
        let data: SIMDVertexData = mesh.getVertexData(maxSides: 3, counts: &counts)
        self.positions = MeshBuffers.Positions(data.positions)
        self.normals = MeshBuffers.Normals(data.normals)
        self.textureCoordinates = MeshBuffers.TextureCoordinates(data.texcoords)
        self.primitives = .triangles(data.indices)
        if !data.materialIndices.isEmpty {
            self.materials = MeshDescriptor.Materials.perFace(data.materialIndices)
        }
    }

    /// Creates a mesh descriptor from a ``Mesh`` using convex polygons.
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit mesh descriptor.
    init(polygons mesh: Mesh) {
        self.init()
        var counts: [UInt8]? = []
        let data: SIMDVertexData = mesh.getVertexData(maxSides: 255, counts: &counts)
        self.positions = MeshBuffers.Positions(data.positions)
        self.normals = MeshBuffers.Normals(data.normals)
        self.textureCoordinates = MeshBuffers.TextureCoordinates(data.texcoords)
        self.primitives = .polygons(counts!, data.indices)
        if !data.materialIndices.isEmpty {
            self.materials = MeshDescriptor.Materials.perFace(data.materialIndices)
        }
    }

    /// Creates a mesh descriptor from a ``Mesh`` using quads where possible (and triangles as required).
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit mesh descriptor.
    init(quads mesh: Mesh) {
        self.init()
        var counts: [UInt8]? = []
        let data: SIMDVertexData = mesh.getVertexData(maxSides: 4, counts: &counts)
        self.positions = MeshBuffers.Positions(data.positions)
        self.normals = MeshBuffers.Normals(data.normals)
        self.textureCoordinates = MeshBuffers.TextureCoordinates(data.texcoords)
        var i = 0
        var quads = [UInt32]()
        var triangles = [UInt32]()
        let perFaceMaterials = !data.materialIndices.isEmpty
        for count in counts! {
            switch count {
            case 3:
                triangles += data.indices[i ..< i + 3]
            case 4:
                quads += data.indices[i ..< i + 4]
            default:
                assertionFailure()
                self.primitives = .polygons(counts!, data.indices)
                if perFaceMaterials {
                    self.materials = MeshDescriptor.Materials.perFace(data.materialIndices)
                }
                return
            }
            i += Int(count)
        }
        self.primitives = .trianglesAndQuads(triangles: triangles, quads: quads)
        if perFaceMaterials {
            var triangles = [UInt32]()
            var quads = [UInt32]()
            for (count, material) in zip(counts!, data.materialIndices) {
                switch count {
                case 3:
                    triangles.append(material)
                default:
                    quads.append(material)
                }
            }
            self.materials = MeshDescriptor.Materials.perFace(triangles + quads)
        }
    }
}

@available(macOS 12.0, iOS 15.0, *)
public extension ModelEntity {
    /// A closure that maps a Euclid material to a RealityKit material.
    /// - Parameter m: A Euclid material to convert, or `nil` for the default material.
    /// - Returns: A `Material` used by RealityKit.
    typealias MaterialProvider = (_ m: Polygon.Material?) -> RealityKit.Material?

    /// Creates a model entity from a ``Mesh`` using the default tessellation method.
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit model entity.
    ///   - materialLookup: A closure to map the polygon material to a RealityKit material.
    convenience init(_ mesh: Mesh, materialLookup: MaterialProvider? = nil) throws {
        try self.init(triangles: mesh, materialLookup: materialLookup)
    }

    /// Creates a model entity from a ``Mesh`` using triangles.
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit model entity.
    ///   - materialLookup: A closure to map the polygon material to a RealityKit material.
    convenience init(triangles mesh: Mesh, materialLookup: MaterialProvider? = nil) throws {
        let descriptor = MeshDescriptor(triangles: mesh)
        let resource = try MeshResource.generate(from: [descriptor])
        self.init(mesh: resource, materials: mesh.materials(for: materialLookup))
    }

    /// Creates a model entity from a ``Mesh`` using convex polygons.
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit model entity.
    ///   - materialLookup: A closure to map the polygon material to a RealityKit material.
    convenience init(polygons mesh: Mesh, materialLookup: MaterialProvider? = nil) throws {
        let descriptor = MeshDescriptor(polygons: mesh)
        let resource = try MeshResource.generate(from: [descriptor])
        self.init(mesh: resource, materials: mesh.materials(for: materialLookup))
    }

    /// Creates a model entity from a ``Mesh`` using quads where possible (and triangles as required).
    /// - Parameters:
    ///   - mesh: The mesh to convert into a RealityKit model entity.
    ///   - materialLookup: A closure to map the polygon material to a RealityKit material.
    convenience init(quads mesh: Mesh, materialLookup: MaterialProvider? = nil) throws {
        let descriptor = MeshDescriptor(quads: mesh)
        let resource = try MeshResource.generate(from: [descriptor])
        self.init(mesh: resource, materials: mesh.materials(for: materialLookup))
    }
}

private extension Mesh {
    @available(macOS 12.0, iOS 15.0, *)
    func materials(for materialLookup: ModelEntity.MaterialProvider?) -> [RealityKit.Material] {
        let materialLookup = materialLookup ?? defaultMaterialLookup
        return materials.map { materialLookup($0) ?? SimpleMaterial() }
    }
}

#endif
