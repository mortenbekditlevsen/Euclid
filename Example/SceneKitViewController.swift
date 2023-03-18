//
//  SceneViewController.swift
//  Example
//
//  Created by Nick Lockwood on 11/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import UIKit

class SceneKitViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // create a new scene
        let scene = SCNScene()

        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)

        // place the camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2)

        // create some geometry using Euclid
        let start = CFAbsoluteTimeGetCurrent()
//        let cube = Mesh.cube(size: 0.8, material: UIColor.red)
//        let sphere = Mesh.sphere(slices: 120, material: UIColor.blue)
//        let mesh = cube.subtract(sphere).makeWatertight()

//        let cube = Mesh.cube().inverted()
//        let cube2 = Mesh.cube().inverted().translated(by: Vector(0.5, 0.5, 0.5))
//        let mesh = cube.union(cube2).inverted()

//        print("Time:", CFAbsoluteTimeGetCurrent() - start)
//        print("Polygons:", mesh.polygons.count)
//        print("Triangles:", mesh.triangulate().polygons.count)
//        print("Watertight:", mesh.isWatertight)

        let polygon1 = Path.square().facePolygons()[0]
        let polygon2 = Path.square().translated(by: Vector(0.5, 0.5, 0.1)).rotated(by: .yaw(.pi / 5)).facePolygons()[0]
        let result = polygon1.xor(polygon2)
        let mesh = Mesh(result)

        // create SCNNode
        let geometry = SCNGeometry(mesh)
        let node = SCNNode(geometry: geometry)
        scene.rootNode.addChildNode(node)

        // configure the SCNView
        let scnView = view as! SCNView
        scnView.scene = scene
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = true
        scnView.backgroundColor = .white
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var prefersStatusBarHidden: Bool {
        true
    }
}
