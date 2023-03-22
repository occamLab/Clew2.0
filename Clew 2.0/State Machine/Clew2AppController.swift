//
//  Clew2AppController.swift
//  Clew 2.0
//
//  Created by Joyce Chung & Gabby Blake on 2/11/23.
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import Foundation
import ARKit

class Clew2AppController: AppController {
    public static var shared = Clew2AppController()
    private var state = Clew2AppState.initialState
    
    // Creator controllers for handling commands
    var mapRecorder = MapRecorder()
    var recordViewer: RecordViewController? // Initialized in RecordMapView.swift
    var mapDatabase = FirebaseManager.createMapDatabase()
    
    // Navigate controllers for handling commands
    public var mapNavigator = MapNavigator()
    var navigateViewer: NavigateViewController? // Initiliazed in NavigateMapView.swift
    
    // controllers for both navigate and create
    public var arViewer: ARViewController? // Initialized in ARView.swift
    
    func initialize() {
        Clew2AppController.shared.arViewer?.initialize()
        Clew2AppController.shared.arViewer?.setupPing()
    }
    
    func process(commands: [Clew2AppState.Command]) {
        for command in commands {
            switch commands {
                // MapRecorder commands
    
                
                // RecordViewer commands
                
                
                // MapDatabase commands
                
                
                // MapNavigator commands
                
                
                // NavigateViewer commands
                
                
                // ARViewer commands
            }
        }
    }
    
    func process(event: Clew2AppState.Event) {
        process(commands: state.handle(event: event))
    }
}


extension Clew2AppController {
    // functions that don't fall under any of the command object categories above
    func cacheLocationRequested(node: SCNNode, picture: UIImage, textNode: SCNNode) {
        process(commands: [CreatorAppState.Command.CacheLocation(node: node, picture: picture, textNode: textNode)])
    }
    
    func updateLocationListRequested(node: SCNNode, picture: UIImage, textNode: SCNNode, poseId: Int) {
        process(commands: [CreatorAppState.Command.UpdateLocationList(node: node, picture: picture, textNode: textNode, poseId: poseId)])
    }
    
    func deleteMap(mapName: String) {
        process(commands: [.DeleteMap(mapID: mapName)])
    }
}


protocol MapRecorderController {
    // Commands that impact the map data being recorded; Lays out command functions implemented on MapRecorder class in MapRecorder.swift
    func recordData(cameraFrame: ARFrame)
    func cacheLocation(node: SCNNode, picture: UIImage, textNode: SCNNode)
    func sendToFirebase(mapName: String)
    func clearData()
}

protocol RecordViewController {
    // Commands that impact the record map UI - mainly for instruction updates; Lays out functions implemented on RecordGlobalState class in RecordMapView.swift
    func updateRecordInstructionText()
    func updateLocationList(node: SCNNode, picture: UIImage, textNode: SCNNode, poseId: Int)
}

protocol NavigateViewController {
    // Commands that impact the navigate map UI - mainly for instruction updates; Lays out functions implemented on NavigateGlobalState class in NavigateMapView.swift
    func updateNavigateInstructionText()
}

protocol MapsController {
    // Commands that impact the map database; Lays out functions implemented on MapDatabase class extension in FirebaseManager.swift
    func deleteMap(mapID: String)
}
