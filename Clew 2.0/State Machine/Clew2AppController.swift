//
//  Clew2AppController.swift
//  Clew 2.0
//
//  Created by tad on 9/22/21.
//  Copyright © 2021 Occam Lab. All rights reserved.
//
//  Revised by Joyce Chung & Gabby Blake on 2/11/23.
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
    // Controllers for both navigate and create
    public var arViewer: ARViewController? // Initialized in ARView.swift
    var cloudAnchorType: String // door, stair, POI
    // State of whether the current app is in the process of leaving the app
    public var exitingMap = false
    // Counter incremented each time a graph is rendered in a new AR frame
    public var countFrame: Int = 0
    
    init() {
        Clew2AppController.shared.arViewer?.initialize()
        Clew2AppController.shared.arViewer?.setupPing()
    }
    
    func process(commands: [Clew2AppState.Command]) {
        for command in commands {
            switch command {
                // HomeScreen commands
            case .NameMap(let mapName):
                break
            case .LoadFamilyScreen:
                break
                // FamilyScreen commands
            case .LoadLocationScreen:
                break
                // Location Screen commands
            case .LoadPOIScreen(let mapName):
                break
                // POIScreen commands
            case .LoadReviews(let mapName):
                break
            case .StartNavigation(let mapName):
                NavigateGlobalStateSingleton.shared = NavigateGlobalState()
            case .LoadPreviewDirections:
                break
                // ReviewsScreen commands TBD
                // PreviewDirectionScreen commands TBD
                //NameMapScreen commands TBD
                //  case .LocateAndCategorizeMap: // user uses GPS to automatically categorize the map - map still needs to be named
                //  case .LoadAndCategorizeMap(mapName: String): // user searches for a location that doesn't have a map yet and creates a map for that location - map already named
            
                
                // CreateARView commands
            case .DropGeospatialAnchor:
                self.arViewer?.dropGeoSpatialAnchor() //TODO: need location argument
                Clew2AppController.shared.mapRecorder.geospatialAnchorWasRecorded = true
            case .DropPOIAnchor:
                self.arViewer?.hostCloudAnchor() //TODO: need transform argument
                Clew2AppController.shared.mapRecorder.cloudAnchorWasRecorded = true
                Clew2AppController.shared.cloudAnchorType = "POI"
            case .DropDoorAnchor:
                self.arViewer?.hostCloudAnchor() //TODO: need transform argument
                Clew2AppController.shared.mapRecorder.cloudAnchorWasRecorded = true
                Clew2AppController.shared.cloudAnchorType = "door"
            case .DropStairAnchor:
                self.arViewer?.hostCloudAnchor() //TODO: need transform argument
                Clew2AppController.shared.mapRecorder.cloudAnchorWasRecorded = true
                Clew2AppController.shared.cloudAnchorType = "stair"
            case .ViewPOIs(let mapName):
                // viewing POIs dropped during creation of map
                process(commands: [.LoadPOIScreen(mapName: mapName)])
            case .NamePOI: //TODO: after dropping POI during creation, name the POI, store it in some dictionary? put into Firebase?
                // ask: how to save this in Firebase
                break
            case .SaveMapToFirebase(let mapName):
                Clew2AppController.shared.mapRecorder.sendToFirebase(mapName: mapName)
            case .UpdateCreateInstructionText:
                recordViewer?.updateRecordInstructionText()
                print("updated creation instruction text")
            
            // NavigateARView commands
            case .ResolveCloudAnchor:
                // ask: arview session that resolves cloud anchors - how do we call this?
                // the session will mark the anchorType var in the session
                break
            case .UpdateNavigateInstructionText:
                navigateViewer?.updateNavigateInstructionText()
                print("updated navigation instruction text")
            // TODO: need a case that continuously resolves cloud anchors (breadcrumbs for the path)
            // route anchors are nameless cloud anchors that're dropped every x seconds or every x feet (just like breadcrumbs in Clew)
     
            // For both NavigateARView and CreateARView
            case .LeaveARView(let mapName):
                self.arViewer?.resetNavigatingSession()
                self.mapNavigator.resetMap() // destroys the map
                self.exitingMap = false
                print("leave map")
                process(commands: [.LoadPOIScreen(mapName: mapName)])
                
            // From IM code
            case .PlanPath:
                if let cameraNode = arViewer?.cameraNode {
                        let cameraPos = arViewer!.convertNodeOrigintoMapFrame(node: cameraNode)
                        let stops = self.mapNavigator.planPath(from: simd_float3(cameraPos!.x, cameraPos!.y, cameraPos!.z))
                            if let stops = stops {
                                self.arViewer!.renderGraph(fromStops: stops)
                                countFrame += 1
                            }
                        }
            case .UpdatePoseVIO(cameraFrame: ARFrame):
                break
            case .UpdatePoseTag(tag: AprilTags, cameraTransform: simd_float4x4):
                break
            case .ModifyRoute(mapname: String, POIName: String):
                // call StartNavigation to a new POI endpoint
                break
            case .LoadEndPopUp(mapName: String):
                break
            case .LoadRatePopUp(mapName: String):
                break
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
        process(commands: [Clew2AppState.Command.CacheLocation(node: node, picture: picture, textNode: textNode)])
    }
    
    func updateLocationListRequested(node: SCNNode, picture: UIImage, textNode: SCNNode, poseId: Int) {
        process(commands: [Clew2AppState.Command.UpdateLocationList(node: node, picture: picture, textNode: textNode, poseId: poseId)])
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
