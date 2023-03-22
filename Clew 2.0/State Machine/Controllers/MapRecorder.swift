//
//  MapRecorder.swift
//  Clew 2.0
//
//  Created by occamlab on 3/4/23.
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import Foundation
import ARKit
import Firebase
import FirebaseDatabase
import FirebaseStorage

class MapRecorder: MapRecorderController, ObservableObject {
    @Published var map: Map?
   
    // for tag detection visualization for creator
    var aprilTagDetectionDictionary = Dictionary<Int, AprilTagTracker>()
    var currentFrameTransform: simd_float4x4 = simd_float4x4.init()
    /// Tracks last recorded frame to set map image to
    var lastRecordedFrame: ARFrame?
    /// Time interval at which pose, tag, location, and node data is recorded
    let recordInterval = 0.5
    /// Allows you to asynchronously run a job on a background thread
    let aprilTagQueue = DispatchQueue(label: "edu.occamlab.apriltagfinder", qos: DispatchQoS.userInitiated)
    var poseId: Int = 0
    var poseData: [[String: Any]] = []
    var tagData: [[[String: Any]]] = []
    var locationData: [[String: Any]] = []
    var planeData: [UUID: [String: Any]] = [:]
    
    /// Tracks whether record data function is processing a frame to prevent queue from being overfilled
    var processingFrame: Bool = false
    /// Tracks any new locations
    var pendingLocation: (String, simd_float4x4)?
    /// Tracks any new location nodes
    var pendingNode: (SCNNode, UIImage, SCNNode)?
    /// Tracks current planes seen
    var planesSeen = Set<UUID>()
    
    /// Tracks whether the first tag has been found
    @Published var firstTagFound = false
    /// Tracks whether the user has asked for a tag to be recorded
    @Published var tagRecordingState = false
    @Published var seesTag = false
    @Published var tagWasRecorded = false
    @Published var previousTagRecordedState = false
    
    /// Correct the orientation estimate such that the normal vector of the tag is perpendicular to gravity
    let snapTagsToVertical = true
    
    let f = imageToData()
    
    var firebaseRef: DatabaseReference!
    var firebaseStorage: Storage!
    var firebaseStorageRef: StorageReference!
    
    func initFirebase() {
        firebaseRef = Database.database(url: "https://invisible-map-sandbox.firebaseio.com/").reference()
        firebaseStorage = Storage.storage()
        firebaseStorageRef = firebaseStorage.reference()
    }
    
    init() {
        initFirebase()
    }
    
    /// Record pose, tag, location, and node data after a specified period of time
    func recordData(cameraFrame: ARFrame) {
        processingFrame = true
        lastRecordedFrame = cameraFrame
        
        recordPoseData(cameraFrame: cameraFrame, timestamp: InvisibleMapCreatorController.shared.arViewer!.lastRecordedTimestamp, poseId: poseId)
        tagRecordingStates(cameraFrame: cameraFrame, timestamp: InvisibleMapCreatorController.shared.arViewer!.lastRecordedTimestamp, poseId: poseId)
        recordPlaneData(cameraFrame: cameraFrame, poseId: poseId)
        poseId += 1
        
        if let pendingLocation = pendingLocation {
            locationData.append(getLocationCoordinates(cameraFrame: cameraFrame, timestamp: InvisibleMapCreatorController.shared.arViewer!.lastRecordedTimestamp, poseId: poseId, location: pendingLocation))
            InvisibleMapCreatorController.shared.updateLocationListRequested(node: pendingNode!.0, picture: pendingNode!.1, textNode: pendingNode!.2, poseId: poseId)
            self.pendingLocation = nil
            self.pendingNode = nil
        }
        print("Running \(poseId)")
    }
    
    /// Add new planes and update existing planes
    func updatePlanes(planes: [ARPlaneAnchor]) {
        for plane in planes {
            planesSeen.insert(plane.identifier)
            planeData[plane.identifier] = getPlaneData(plane: plane)
        }
    }
    
    /// Cache the location and node data so that it is recorded the next time recordData is called and matches up with the corresponding poseId
    func cacheLocation(node: SCNNode, picture: UIImage, textNode: SCNNode) {
        pendingLocation = (node.name!, node.simdTransform)
        pendingNode = (node, picture, textNode)
    }

    /// Upload pose data, last image frame to Firebase under "maps" and "unprocessed_maps" nodes
    func sendToFirebase(mapName: String) {
        let mapImage = convertToUIImage(cameraFrame: lastRecordedFrame!)
        let mapId =  mapName //+ " " + String(InvisibleMapCreatorController.shared.arViewer!.lastRecordedTimestamp).replacingOccurrences(of: ".", with: "")
        var planeDataList: [[String: Any]] = planeData.keys.map({planeData[$0]}) as! [[String: Any]]
        planeDataList.sort{
            ($0["id"] as! Int) < ($1["id"] as! Int)
        }
        
        let mapJsonFile: [String: Any] = ["map_id": mapId, "pose_data": poseData, "tag_data": tagData, "location_data": locationData, "plane_data": planeDataList]
        
        let folderPath = "rawMapData/" + String(describing: Auth.auth().currentUser!.uid)
        let imagePath = folderPath + "/" + mapId + ".jpg"
        let filePath = folderPath + "/" + mapId + ".json"
        
        // TODO: handle errors when failing to upload image and json file
        // TODO: let the user pick their image
        // Upload the last image capture to Firebase
        firebaseStorageRef.child(imagePath).putData(mapImage.jpegData(compressionQuality: 0)!, metadata: StorageMetadata(dictionary: ["contentType": "image/jpeg"]))
        
        var log = ""
        if JSONSerialization.isValidJSONObject(mapJsonFile) {
            if !JSONSerialization.isValidJSONObject(["map_id": mapId]) {
                log += "map_id \(mapId) is invalid\n"
            }
            if !JSONSerialization.isValidJSONObject(["pose_data": poseData]) {
                log += "pose_data is invalid:\n\(poseData)\n"
            }
            if !JSONSerialization.isValidJSONObject(["tag_data": tagData]) {
                log += "tag_data is invalid:\n\(tagData)\n"
            }
            if !JSONSerialization.isValidJSONObject(["location_data": locationData]) {
                log += "location_data is invalid:\n\(locationData)\n"
            }
            if !JSONSerialization.isValidJSONObject(["plane_data": planeDataList]) {
                log += "plane_data is invalid:\n\(planeDataList)\n"
            }
        }
        else {
            log += "mapJsonFile is valid"
        }
        print(log)
        try? firebaseStorageRef.child(folderPath + "/\(mapId) serialization error.json").putData(JSONSerialization.data(withJSONObject: ["log": log]))

        // Upload raw file json
        if let jsonData = try? JSONSerialization.data(withJSONObject: mapJsonFile, options: []) {
            firebaseStorageRef.child(filePath).putData(jsonData, metadata: StorageMetadata(dictionary: ["contentType": "application/json"])){ (metadata, error) in
                // Write to maps node in database
                self.firebaseRef.child("maps").child(String(describing: Auth.auth().currentUser!.uid)).child(mapId).setValue(["name": mapName, "image": imagePath, "raw_file": filePath])
                
                // Write to unprocessed maps node in database
                self.firebaseRef.child("unprocessed_maps").child(String(describing: Auth.auth().currentUser!.uid)).child(mapId).setValue(filePath)
            }
        }
    }
    
    /// Clear timestamp, pose, tag, and location data
    func clearData() {
        InvisibleMapCreatorController.shared.arViewer!.lastRecordedTimestamp = -1
        lastRecordedFrame = nil
        firstTagFound = false
        seesTag = false
        tagRecordingState = false
        poseId = 0
        poseData = []
        locationData = []
        tagData = []
        print("Clear data")
    }
}

// Helper functions that are not explicitly commands
extension MapRecorder {
    /// Append new pose data to list
    func recordPoseData(cameraFrame: ARFrame, timestamp: Double, poseId: Int) {
        poseData.append(getCameraCoordinates(cameraFrame: cameraFrame, timestamp: timestamp, poseId: poseId))
    }
    
    /// Append new april tag data to list - tags are continuously recorded when NewARFrame event is processed but tags are NOT actually "recorded" into the tag data unless certain conditions are met
    @objc func tagRecordingStates(cameraFrame: ARFrame, timestamp: Double, poseId: Int) {
        let uiimage = cameraFrame.convertToUIImage()
        aprilTagQueue.async {
            let arTags = self.getArTags(cameraFrame: cameraFrame, image: uiimage, timeStamp: timestamp, poseId: poseId)
            DispatchQueue.main.async {
                self.seesTag = !arTags.isEmpty
                if !self.firstTagFound && self.seesTag {
                    self.firstTagFound = true
                }
                if self.tagRecordingState && self.seesTag {
                    self.tagData.append(arTags)
                }

                if !self.tagRecordingState && self.previousTagRecordedState {
                    self.tagWasRecorded = true
                }

                if !self.seesTag {
                    self.previousTagRecordedState = self.tagRecordingState
                    self.tagRecordingState = false
                    self.tagWasRecorded = false
                }
                
                self.processingFrame = false
            }
        }
    }
    
    /// Append/Modify new plane data to list
    func recordPlaneData(cameraFrame: ARFrame, poseId: Int) {
        var planeInfo: [[String: Any]] = []
        for plane in planesSeen {
            guard let currentPlane = planeData[plane], let planePoseList = currentPlane["pose"] as? [Float], let planeId = currentPlane["id"] as? Int else {
                continue
            }
            let planePose = simd_float4x4(columns: (simd_float4(planePoseList[0], planePoseList[1], planePoseList[2], planePoseList[3]), simd_float4(planePoseList[4], planePoseList[5], planePoseList[6], planePoseList[7]), simd_float4(planePoseList[8], planePoseList[9], planePoseList[10], planePoseList[11]), simd_float4(planePoseList[12], planePoseList[13], planePoseList[14], planePoseList[15])))
            let transform = matrix_multiply(planePose, currentFrameTransform.inverse)
            planeInfo.append(["transform": [transform.columns.0.x, transform.columns.1.x, transform.columns.2.x, transform.columns.3.x, transform.columns.0.y, transform.columns.1.y, transform.columns.2.y, transform.columns.3.y, transform.columns.0.z, transform.columns.1.z, transform.columns.2.z, transform.columns.3.z, transform.columns.0.w, transform.columns.1.w, transform.columns.2.w, transform.columns.3.w], "id": planeId])
        }
        poseData[poseId]["planes"] = planeInfo
        planesSeen.removeAll()
    }
    
    /// Finds all april tags in the frame
    func getArTags(cameraFrame: ARFrame, image: UIImage, timeStamp: Double, poseId: Int) -> [[String:Any]] {
        let intrinsics = cameraFrame.camera.intrinsics.columns
        f.findTags(image, intrinsics.0.x, intrinsics.1.y, intrinsics.2.x, intrinsics.2.y)
        var tagArray: Array<AprilTags> = Array()
        var allTags: [[String:Any]] = []
        let numTags = f.getNumberOfTags()
        if numTags > 0 {
            for i in 0...f.getNumberOfTags()-1 {
                tagArray.append(f.getTagAt(i))
            }

            for i in 0...tagArray.count-1 {
                var tagDict:[String:Any] = [:]
                
                
                if ((InvisibleMapCreatorController.shared.arViewer?.supportsLidar) != nil ? InvisibleMapCreatorController.shared.arViewer?.supportsLidar as! Bool : false) {
                    let raycastPose: simd_float4x4? = InvisibleMapCreatorController.shared.arViewer?.raycastTag(tag: tagArray[i], cameraTransform: cameraFrame.camera.transform, snapTagsToVertical: snapTagsToVertical)
                    
                    if raycastPose == nil {
                        continue
                    } else {
                        tagArray[i].poseData = raycastPose!.toRowMajorOrder()
                    }
                }
                
                InvisibleMapCreatorController.shared.process(event: .NewTagFound(tag: tagArray[i], cameraTransform: cameraFrame.camera.transform, snapTagsToVertical: snapTagsToVertical)) // Generates event to detect new tag
                
                var pose = tagArray[i].poseData
                
                if snapTagsToVertical {
                    var simdPose = simd_float4x4(pose)
                    // convert from April Tags conventions to Apple's (TODO: could this be done in one rotation?)
                    simdPose = simdPose.rotate(radians: Float.pi, 0, 1, 0)
                    simdPose = simdPose.rotate(radians: Float.pi, 0, 0, 1)
                    let worldPose = cameraFrame.camera.transform*simdPose
                    // TODO: the alignY() seems to break things, possibly because we aren't properly remapping the covariance matrices.  I made an attempt to try to do this using LASwift, but ran into issues with conflicts with VISP3
                    let worldPoseFlat = worldPose.makeZFlat()//.alignY()
                    // back calculate what the camera pose should be so that the pose in the global frame is flat
                    var correctedCameraPose = cameraFrame.camera.transform.inverse*worldPoseFlat
                    // go back to April Tag Conventions
                    correctedCameraPose = correctedCameraPose.rotate(radians: Float.pi, 0, 0, 1)
                    correctedCameraPose = correctedCameraPose.rotate(radians: Float.pi, 0, 1, 0)
                    pose = correctedCameraPose.toRowMajorOrder()
                }
                tagDict["tag_id"] = tagArray[i].number
                tagDict["tag_pose"] = [pose.0, pose.1, pose.2, pose.3, pose.4, pose.5, pose.6, pose.7, pose.8, pose.9, pose.10, pose.11, pose.12, pose.13, pose.14, pose.15]
                tagDict["camera_intrinsics"] = [intrinsics.0.x, intrinsics.1.y, intrinsics.2.x, intrinsics.2.y]
                tagDict["tag_corners_pixel_coordinates"] = [tagArray[i].imagePoints.0, tagArray[i].imagePoints.1, tagArray[i].imagePoints.2, tagArray[i].imagePoints.3, tagArray[i].imagePoints.4, tagArray[i].imagePoints.5, tagArray[i].imagePoints.6, tagArray[i].imagePoints.7]
                tagDict["tag_position_variance"] = [tagArray[i].transVecVar.0, tagArray[i].transVecVar.1, tagArray[i].transVecVar.2]
                tagDict["tag_orientation_variance"] = [tagArray[i].quatVar.0, tagArray[i].quatVar.1, tagArray[i].quatVar.2, tagArray[i].quatVar.3]
                tagDict["timestamp"] = timeStamp
                tagDict["pose_id"] = poseId
                var jointCovarList: [Double] = []
                let mirror = Mirror(reflecting: tagArray[i].jointCovar)
                for child in mirror.children {
                    jointCovarList.append(child.value as! Double)
                }
                tagDict["joint_covar"] = jointCovarList
                allTags.append(tagDict)
            }
        }
        return allTags
    }
    
    /// Get dictionary of plane data
    func getPlaneData(plane: ARPlaneAnchor) -> [String: Any] {
        let planeId: Int
        if let id = planeData[plane.identifier]?["id"] as? Int {
            planeId = id
        } else {
            planeId = planeData.count
        }
        let planeTransform = plane.transform
        let boundaryVertices: [[Float]] = plane.geometry.boundaryVertices.map({[$0.x, $0.y, $0.z]})
        let planeDict: [String: Any] = ["pose": [planeTransform.columns.0.x, planeTransform.columns.1.x, planeTransform.columns.2.x, planeTransform.columns.3.x, planeTransform.columns.0.y, planeTransform.columns.1.y, planeTransform.columns.2.y, planeTransform.columns.3.y, planeTransform.columns.0.z, planeTransform.columns.1.z, planeTransform.columns.2.z, planeTransform.columns.3.z, planeTransform.columns.0.w, planeTransform.columns.1.w, planeTransform.columns.2.w, planeTransform.columns.3.w], "boundaries": boundaryVertices, "id": planeId]
        return planeDict
    }
    
    /// Get pose data (transformation matrix, time)
    func getCameraCoordinates(cameraFrame: ARFrame, timestamp: Double, poseId: Int) -> [String: Any] {
        let camera = cameraFrame.camera
        let cameraTransform = camera.transform
        currentFrameTransform = cameraTransform
        let scene = SCNMatrix4(cameraTransform)
        
        let cameraInfo: [String: Any] = ["pose": [scene.m11, scene.m12, scene.m13, scene.m14, scene.m21, scene.m22, scene.m23, scene.m24, scene.m31, scene.m32, scene.m33, scene.m34, scene.m41, scene.m42, scene.m43, scene.m44], "timestamp": timestamp, "id": poseId]
        
        return cameraInfo
    }
    
    /// Get location data
    func getLocationCoordinates(cameraFrame: ARFrame, timestamp: Double, poseId: Int, location: (String, simd_float4x4)) -> [String: Any] {
        let (locationName, nodeTransform) = location
        let finalTransform = currentFrameTransform.inverse * nodeTransform
        let locationInfo: [String: Any] = ["transform": [finalTransform.columns.0.x, finalTransform.columns.1.x, finalTransform.columns.2.x, finalTransform.columns.3.x, finalTransform.columns.0.y, finalTransform.columns.1.y, finalTransform.columns.2.y, finalTransform.columns.3.y, finalTransform.columns.0.z, finalTransform.columns.1.z, finalTransform.columns.2.z, finalTransform.columns.3.z, finalTransform.columns.0.w, finalTransform.columns.1.w, finalTransform.columns.2.w, finalTransform.columns.3.w], "timestamp": timestamp, "pose_id": poseId, "name": locationName]
        
        return locationInfo
    }
    
    /// Convert ARFrame to a UIImage
    func convertToUIImage(cameraFrame: ARFrame) -> (UIImage) {
        let pixelBuffer = cameraFrame.capturedImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        let uiImage = UIImage(cgImage: cgImage!)
        return uiImage
    }
}
