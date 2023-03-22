//
//  CreatorAppState.swift
//  InvisibleMapCreator
//
//  Created by Marion Madanguit on 3/5/21.
//

import Foundation
import ARKit

enum CreatorAppState: StateType {
    // Higher level app states
    case MainScreen
    case RecordMap(RecordMapState)
    case EditMapScreen //(EditMapState)
    
    
    // Initial state upon opening the app
    static let initialState = CreatorAppState.MainScreen
    
    // All the effectual inputs from the app which the state can react to
    enum Event {
        // MainScreen events
        case StartRecordingRequested
        case MapSelected(mapFileName: String)
        // EditMapScreen events
        case MapDeleteRequested(mapID: String)
        // RecordMap events
        case NewARFrame(cameraFrame: ARFrame)
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool)
        case PlanesUpdated(planes: [ARPlaneAnchor])
        case SaveLocationRequested(locationName: String)
        case ViewLocationsRequested
        case DismissLocationsRequested
        case CancelRecordingRequested
        case SaveMapRequested(mapName: String)
    }
    
    // All the effectful outputs which the state desires to have performed on the app
    enum Command {
        // RecordMap commands
        case RecordData(cameraFrame: ARFrame)
        case DetectTag(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool)
        case UpdatePlanes(planes: [ARPlaneAnchor])
        // case PauseRecording
        case UpdateInstructionText
        case PinLocation(locationName: String)
        case CacheLocation(node: SCNNode, picture: UIImage, textNode: SCNNode)
        case UpdateLocationList(node: SCNNode, picture: UIImage, textNode: SCNNode, poseId: Int)
        case SendToFirebase(mapName: String)
        case ClearData
        // EditMapScreen commands
        case DeleteMap(mapID: String)
        case LoadMap(mapFileName: String)
    }
    
    // In response to an event, a state may transition to a new state, and it may emit a command
    mutating func handle(event: Event) -> [Command] {
        switch (self, event) {
        case (.MainScreen, .StartRecordingRequested):
            self = .RecordMap(.RecordMap)
            return []
        case (.RecordMap, .CancelRecordingRequested):
            self = .MainScreen
            return [.ClearData]
        case (.RecordMap, .SaveMapRequested(let mapName)):
            self = .MainScreen
            return [.SendToFirebase(mapName: mapName), .ClearData]
        case (.RecordMap(let state), _) where RecordMapState.Event(event) != nil:
            var newState = state
            let commands = newState.handle(event: RecordMapState.Event(event)!)
            self = .RecordMap(newState)
            return commands
        case (.EditMapScreen, .MapDeleteRequested(_)):
            self = .MainScreen
            return []
        case (.MainScreen, .MapSelected(let mapFileName)):
            self = .EditMapScreen
            return [.LoadMap(mapFileName: mapFileName)]
        case(.EditMapScreen, .DismissLocationsRequested):
            self = .MainScreen
            return []
      /*  case (.EditMapScreen(let state), _) where EditMapState.Event(event) != nil:
            var newState = state
            let commands = newState.handle(event: EditMapState.Event(event)!)
            self = .EditMapScreen(newState)
            return commands */
            
        default: break
        }
        return []
    }
}

enum RecordMapState: StateType {
    // Lower level app states nested within RecordMapState
    case RecordMap
    case RecordingPaused
    case ViewLocations
        
    // Initial state upon transitioning into the RecordMapState
    static let initialState = RecordMapState.RecordMap
    
    // All the effectual inputs from the app which RecordMapState can react to
    enum Event {
        case NewARFrame(cameraFrame: ARFrame)
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool)
        case PlanesUpdated(planes: [ARPlaneAnchor])
        // case PauseRecordingPressed
        case SaveLocationRequested(locationName: String)
        case ViewLocationsRequested
        case DismissLocationsRequested
        case CancelRecordingRequested
        case SaveMapRequested
    }
    
    // Refers to commands defined in CreatorAppState
    typealias Command = CreatorAppState.Command
    
    // In response to an event, RecordMapState may emit a command
    mutating func handle(event: Event) -> [Command] {
        switch (self, event) {
            case(.RecordMap, .NewARFrame(let cameraFrame)):
                return [.RecordData(cameraFrame: cameraFrame), .UpdateInstructionText]
            case(.RecordMap, .NewTagFound(let tag, let cameraTransform, let snapTagsToVertical)):
                return [.DetectTag(tag: tag, cameraTransform: cameraTransform, snapTagsToVertical: snapTagsToVertical)]
            case(.RecordMap, .PlanesUpdated(let planes)):
                return [.UpdatePlanes(planes: planes)]
            // Uncomment to implement pausing map recording feature
            // TODO: Implement pausing map feature
            // case(.RecordMap, .PauseRecordingPressed):
            //     self = .RecordingPaused
            //     return []
            // case(.RecordingPaused, .PauseRecordingPressed):
            //     self = .RecordMap
            //     return []
            case(.RecordMap, .SaveLocationRequested(let locationName)):
                return [.PinLocation(locationName: locationName)]
            case(.RecordMap, .ViewLocationsRequested):
                self = .ViewLocations
                return []
            case(.RecordMap, .DismissLocationsRequested):
                self = .RecordMap
                return []
                
            default: break
        }
        return []
    }
}

extension RecordMapState.Event {
    init?(_ event: CreatorAppState.Event) {
        // Translate between events in CreatorAppState and events in RecordMapState
        switch event {
        case .NewARFrame(let cameraFrame):
            self = .NewARFrame(cameraFrame: cameraFrame)
        case .NewTagFound(let tag, let cameraTransform, let snapTagsToVertical):
            self = .NewTagFound(tag: tag, cameraTransform: cameraTransform, snapTagsToVertical: snapTagsToVertical)
        case .PlanesUpdated(let planes):
            self = .PlanesUpdated(planes: planes)
        case .SaveLocationRequested(let locationName):
            self = .SaveLocationRequested(locationName: locationName)
        case .ViewLocationsRequested:
            self = .ViewLocationsRequested
        case .DismissLocationsRequested:
            self = .DismissLocationsRequested
            
        default: return nil
        }
    }
}



