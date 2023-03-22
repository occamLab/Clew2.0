//
//  MapNavigator.swift
//  Clew 2.0
//
//  Created by Allison Li and Ben Morris on 9/24/21.
//  Copyright © 2021 Occam Lab. All rights reserved.
//  Revised by Joyce Chung and Gabby Blake on 03/10/23

import Foundation
import ARKit
import SwiftGraph

class MapNavigator: ObservableObject {
    @Published var map: Map?
    
    /// endpoint sphere; if users enter this sphere announce that they're arrived at their destination
    let endpointSphere: Float = 0.3
    
    // endpoints are either tag locations or waypoint locations
    var locationType: String = "tag"
    
    // updates every time .StartPath command is called, depending on type of endpoint user selects (i.e. if tag is clicked endpointTagKey updates, if POI is clicked endpointLocation Id updates)
    var endpointTagKey: Int = -1
    var endpointWaypointKey: Int = -1
    
    let tagFinder = imageToData()
    
    /// Tracks whether the user has asked for tags to be detected
    @Published var detectTags = false
    /// Tracks whether the tag was found after the user asked a tag to be detected
    @Published var seesTag = false
    
    var processingFrame = false
    let aprilTagQueue = DispatchQueue(label: "edu.occamlab.invisiblemap", qos: DispatchQoS.userInitiated)
    var pathPlanningTimer = Timer()
    
    /// Finds and visualizes path repeatedly in intervals to the endpoint based on a timer
    func scheduledPathPlanningTimer() {
        pathPlanningTimer.invalidate()
        //pathPlanningTimer = Timer()
        //replans the path every "timeInterval" seconds
        pathPlanningTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(self.sendPathPlanEvent), userInfo: nil, repeats: true)
    }
    
    func stopPathPlanning() {
        self.pathPlanningTimer.invalidate()
    }
    
    @objc func sendPathPlanEvent() {
        InvisibleMapController.shared.process(event: .PlanPath)
    }
    
    @objc func waitBeforeLeavingMap(mapFileName: String) {
        InvisibleMapController.shared.process(event: .ReadyToLeaveMap(mapFileName: mapFileName))
    }
    
    /// Plans a path from the current location to the end and visualizes it in red
    /// retunrs an arry of Vertices between Edges of path
    func planPath(from currentLocation: simd_float3) -> [RawMap.OdomVertex]? {
        let start = Date()
        guard let map = map else{
            return nil
        }
        
        if !map.firstTagFound {
            return nil
        }
        
        let endpoint: Int
        // end point for navigating to waypoints/POIs
        if locationType == "waypoint" {
            let waypointLocation = map.rawData.waypointsVertices.first(where: {$0.id == map.waypointDictionary[endpointWaypointKey]!.id})!.translation
            
            endpoint = map.getClosestGraphNode(to: simd_float3(waypointLocation.x, waypointLocation.y, waypointLocation.z))!
        } else {
            // end point for navigating to tag locations
            // searching for first instance of match between id and given endpointTagKey
            let tagLocation = map.rawData.tagVertices.first(where: {$0.id == self.endpointTagKey})!.translation
            
            // closest graph node from current location to endpoint
            endpoint = map.getClosestGraphNode(to: simd_float3(tagLocation.x, tagLocation.y, tagLocation.z))!
            
        }
        let startpoint = map.getClosestGraphNode(to: currentLocation, ignoring: endpoint)

        let (_, pathDict) = map.pathPlanningGraph!.dijkstra(root: String(startpoint!), startDistance: Float(0.0))
        
        //print("startpoint:", startpoint!)
        //print("endpoint:", endpoint)
        //print("current location:", currentLocation)
        //print("tag dictionary:", Array(self.map.tagDictionary.values))
        //print("waypoint dictionary:", Array(self.map.waypointDictionary.values))
        
        // find path from startpoint to endpoint
        let path: [WeightedEdge<Float>] = pathDictToPath(from: map.pathPlanningGraph!.indexOfVertex(String(startpoint!))!, to: map.pathPlanningGraph!.indexOfVertex(String(endpoint))!, pathDict: pathDict)
        //stops are the vertices of edges that make up path
        let stops = map.pathPlanningGraph!.edgesToVertices(edges: path)
     //   print("Time to path plan \(-start.timeIntervalSinceNow)")
        return stops.map({map.odometryDict![Int($0)!]!})
    }
    
    /// Check if tag is detected and update the tag and map transforms
    ///
    /// - Parameters:
    ///   - rotatedImage: the camera frame rotated by 90 degrees to enable accurate tag detection
    ///   - timestamp: the timestamp of the current frame
    func checkTagDetection(image: UIImage, cameraIntrinsics: simd_float3x3, cameraTransform: simd_float4x4)->Array<AprilTags> {
        let intrinsics = cameraIntrinsics.columns
        tagFinder.findTags(image, intrinsics.0.x, intrinsics.1.y, intrinsics.2.x, intrinsics.2.y)
        var tagArray: Array<AprilTags> = Array()
        let numTags = tagFinder.getNumberOfTags()
        if numTags > 0 {
            // remove all of the child nodes of the detection node using the map operation (map plays nicer with optionals than writing it as a for loop)
            let _ = InvisibleMapController.shared.arViewer?.detectionNode?.childNodes.map({ childNode in childNode.removeFromParentNode() })
 
            for i in 0...tagFinder.getNumberOfTags()-1 {
                let tag = tagFinder.getTagAt(i)
                
                // if the tag is within a certain range from the current camera position, detect the tag; only detect tags that are nearby for now -> temporary method to stop constant path shifts when multiple tags or tags that are far away are detected
                if tag.poseData.11 <= 2.5 {
                    tagArray.append(tag)
                    if let map = self.map {
                        if let _ = map.tagDictionary[Int(tag.number)] {
                            InvisibleMapController.shared.process(event: .TagFound(tag: tagArray[tagArray.count-1], cameraTransform: cameraTransform))
                            InvisibleMapController.shared.arViewer?.detectTag(tag: tag, cameraTransform: cameraTransform, snapTagsToVertical: map.snapTagsToVertical)
                        }
                    }
                }
            }
        }
        print(tagArray.map {$0.number})
        return tagArray;
    }
    
    /// Processes the pose, april tags, and nearby waypoints.
    func updateTags(from cameraFrame: ARFrame) {
        // only continue if user chooses to detect tags
      if !detectTags {
            // don't allow camera to see tags if user did not start tag detection
            self.seesTag = false
            return
        }
        print("Update Tags")
        // Convert ARFrame to a UIImage
        let pixelBuffer = cameraFrame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let uiImage = UIImage(cgImage: cgImage!)
        
        if processingFrame {
            return
        }
        // process the frame in NavigateMap view if it's not doing that yet
        processingFrame = true
        
        aprilTagQueue.async {
            let arTags = self.checkTagDetection(image: uiImage,cameraIntrinsics: cameraFrame.camera.intrinsics, cameraTransform: cameraFrame.camera.transform)
        //    print("arTags array of detected tags: \(arTags)")
            DispatchQueue.main.async {
                // checks if tags were detected and assigns seesTag depending on that
                self.seesTag = !arTags.isEmpty
                print("seesTag: \(self.seesTag)")
                if let map = self.map {
                    if !map.firstTagFound && self.seesTag {
                        print("Starting path planning")
                        map.firstTagFound = true
                        map.renderGraphPath()
                        print("firstTagFound: \(map.firstTagFound)")
                    }
                    self.processingFrame = false
                }
            }
        }
    }
    
    // clears data for map
    func resetMap() {
        self.stopPathPlanning()
        self.processingFrame = false
        self.map = nil  // this also resets firstTagFound var to false
        self.detectTags = false
        self.seesTag = false
    }
}
