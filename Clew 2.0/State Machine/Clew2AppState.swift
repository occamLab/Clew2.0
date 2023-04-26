//
//  AppState.swift
//  Clew 2.0
//
//  Created by Joyce Chung & Gabby Blake on 2/11/23.
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import Foundation
import ARKit

indirect enum Clew2AppState: StateType {
    // Higher level app states
    case HomeScreen
    case FamilyScreen
    case LocationScreen
    case POIScreen
    case NameMapScreen
    case ReviewsScreen
    case PreviewDirectionsScreen
    case CreateARView(CreateARViewState)
    case NavigateARView(NavigateARViewState)
    
    // Initial state upon opening the app
    static let initialState = Clew2AppState.HomeScreen
    
    // All the effectual inputs from the app which the state can react to
    enum Event {
        // HomeScreen events
        case CreateMapRequested(mapName: String)
        case LocateUserRequested
        case DomainSelected
        // FamilyScreen events
        case FamilySelected
        // LocationScreen events
        case LocationSelected(mapName: String)
        // POIScreen events
        case ReviewsSelected(mapName: String)
        case POISelected(mapName: String)
        case PreviewDirectionSelected(mapName: String)
        
        // NameMapScreen events
        case StartCreationRequested // after enterng map naming and categorizing info
        // ReviewsScreen events TBD
        // PreviewDirectionScreen events TBD
        
        // CreateARView events
        case DropGeospatialAnchorRequested
        case DropPOIAnchorRequested // POI cloud anchors
        // TODO: cloud anchors are both breadcrumbs and can be named as POIs - need to figure out the time interval at which it should be dropped or if we should make users drop it frequently and name those that they want to
        case DropDoorAnchorRequested
        case DropStairAnchorRequested
        case ViewPOIsRequested(mapName: String)
        case NamePOIRequested
        case SaveMapRequested(mapName: String)
        case LeaveCreateARViewRequested(mapName: String)
        
        // NavigateARView events
        case StartNavigationRequested(mapName: String)
        case ChangeRouteRequested(mapName: String, POIName: String) // we may need to save the mapName so that we can redirect users to a new POI destination
        case PlanPath
        // resolving anchors
        case ResolveCloudAnchor
        case EndpointReached(mapName: String, finalEndpoint: Bool)
        case RateMapRequested(mapName: String)
        case HomeScreenRequested
        case POIScreenRequested(mapName: String)
        case LeaveNavigateARViewRequested(mapName: String)
        
        // Frame handling events
        case NewARFrame(cameraFrame: ARFrame) // to update AR screen during map creation
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) // for April tags
        case PlanesUpdated(planes: [ARPlaneAnchor])
    }
    
    // All the effectful outputs which the state desires to have performed on the app
    enum Command {
        // HomeScreen commands
        case NameMap(mapName: String)
        case LoadFamilyScreen
        
        // FamilyScreen commands
        case LoadLocationScreen
        
        // Location Screen commands
        case LoadPOIScreen(mapName: String)
        
        // POIScreen commands
        case LoadReviews(mapName: String)
        case StartNavigation(mapName: String)
        case LoadPreviewDirections(mapName: String)
        
        // ReviewsScreen commands TBD
        // PreviewDirectionScreen commands TBD
        //NameMapScreen commands TBD
        
        // CreateARView commands
        case DropGeospatialAnchor
        case DropPOIAnchor
        case DropDoorAnchor
        case DropStairAnchor
        case ViewPOIs(mapName: String)
        case NamePOI
        case SaveMapToFirebase(mapName: String)
        case UpdateCreateInstructionText
        //case LocateAndCategorizeMap // user uses GPS to automatically categorize the map - map still needs to be named
        //case LoadAndCategorizeMap(mapName: String) // user searches for a location that doesn't have a map yet and creates a map for that location - map already named

        // NavigateARView commands
        case ResolveCloudAnchor
        case PlanPath
        case UpdateNavigateInstructionText
        case UpdatePoseVIO(cameraFrame: ARFrame)
        case UpdatePoseTag(tag: AprilTags, cameraTransform: simd_float4x4)
        case ModifyRoute(mapname: String, POIName: String) // call StartNavigation to a new POI endpoint
        case LoadEndPopUp(mapName: String)
        case LoadRatePopUp(mapName: String)
        
        // Leaving Create or Navigate ARView - unless they require different things to be changed, using the same command should be okay
        case LeaveARView(mapName: String)
    }
    
    // In response to an event, a state may transition to a new state, and it may emit a command
    mutating func handle(event: Event) -> [Command] {
        print("Last State: \(self), \(event)")
        switch (self, event) {
        case (.HomeScreen, .CreateMapRequested(let mapName)):
            self = .NameMapScreen
            return [.NameMap(mapName: mapName)] // should we send to Firebase after user presses 'Finished'?
        case (.NameMapScreen, .StartCreationRequested):
            self = .CreateARView(.CreateARView)
            return []
            
        case (.POIScreen, .StartNavigationRequested(let mapName)):
            self = .NavigateARView(.NavigateARView)
            return []
            
        // user finds a map's POIs without shortcut/searchbar - i.e. selects a domain -> ... -> POI
        case (.HomeScreen, .DomainSelected):
            self = .FamilyScreen
            return [.LoadFamilyScreen]
        case (.FamilyScreen, .FamilySelected):
            self = .LocationScreen
            return [.LoadLocationScreen]
        case (.LocationScreen, .LocationSelected(let mapName)):
            self = .POIScreen
            return [.LoadPOIScreen(mapName: mapName)]
        case (.POIScreen, .ReviewsSelected(let mapName)):
            self = .ReviewsScreen
            return [.LoadReviews(mapName: mapName)]
        case (.POIScreen, .POISelected(let mapName)):
            self = .NavigateARView(.NavigateARView)
            return [.StartNavigation(mapName: mapName)]
        case (.POIScreen, .PreviewDirectionSelected(let mapName)):
            self = .PreviewDirectionsScreen
            return [.LoadPreviewDirections(mapName: mapName)]
        // user finds a map's POIs through the search bar - takes shortcut
//        case (.HomeScreen, .LocationSelected(let mapName)):
//            self = .POIScreen
//            return [.LoadPOIs(mapName: mapName)]
        
        // handling lower level events for CreateMapState
        case (.CreateARView(let state), _) where CreateARViewState.Event(event) != nil:
            var newState = state
            let commands = newState.handle(event: CreateARViewState.Event(event)!)
            self = .CreateARView(newState)
            return commands
        case (.CreateARView, .SaveMapRequested(let mapName)):
            self = .POIScreen
            return [.SaveMapToFirebase(mapName: mapName)]
        case (.CreateARView, .LeaveCreateARViewRequested(let mapName)):
            self = .POIScreen
            return [.LeaveARView(mapName: mapName)]
            
        // handling lower level events for NavigateMapState
        case (.NavigateARView(let state), _) where NavigateARViewState.Event(event) != nil:
            var newState = state
            let commands = newState.handle(event: NavigateARViewState.Event(event)!)
            self = .NavigateARView(newState)
            return commands
        case (.NavigateARView, .HomeScreenRequested):
            self = .HomeScreen
            return []
        case (.NavigateARView, .POIScreenRequested(let mapName)):
            self = .POIScreen
            return [.LoadPOIScreen(mapName: mapName)]
        case (.NavigateARView, .LeaveNavigateARViewRequested(let mapName)):
            self = .POIScreen
            return [.LeaveARView(mapName: mapName)]
            
            default: break
        }
        return []
    }
}

enum CreateARViewState: StateType {
    // Lower level app states nested within CreateMapState
    case CreateARView
    case DropDoorAnchorState
    case DropStairAnchorState
    
    // Initial state upon transitioning into the CreateMapState
    static let initialState = CreateARViewState.CreateARView
    
    // All the effectual inputs from the app which CreateMapState can react to
    enum Event {
        case DropGeospatialAnchorRequested
        case DropPOIAnchorRequested
        case DropDoorAnchorRequested
        case DropStairAnchorRequested
        case ViewPOIsRequested(mapName: String)
        case NamePOIRequested
        // events handled in higher level (to switch to higher level states)
        case SaveMapRequested(mapName: String)
        case LeaveCreateARViewRequested(mapName: String)
        
        // frame handling events
        case NewARFrame(cameraFrame: ARFrame) // to update AR screen during map creation
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) // if we are still using April tags
        case PlanesUpdated(planes: [ARPlaneAnchor])
    }
    
    // Refers to commands defined in Clew2AppState - adds onto created commands for CreateMapState
    typealias Command = Clew2AppState.Command
    
    // In response to an event, CreateMapState may emit a command
    mutating func handle(event:Event) -> [Command] {
        switch (self, event) {
        case (.CreateARView, .DropGeospatialAnchorRequested):
            self = .CreateARView
            return [.DropGeospatialAnchor]
        case (.CreateARView, .DropPOIAnchorRequested):
            self = .CreateARView
            return [.DropPOIAnchor]
        case (.CreateARView, .DropDoorAnchorRequested):
            self = .DropDoorAnchorState
            return [.DropDoorAnchor]
        case (.CreateARView, .DropStairAnchorRequested):
            self = .DropStairAnchorState
            return [.DropStairAnchor]
        case (.CreateARView, .ViewPOIsRequested(let mapName)):
            self = .CreateARView
            return [.ViewPOIs(mapName: mapName)]
        case (.CreateARView, .NewARFrame(let cameraFrame)):
            self = .CreateARView
            return [.UpdateCreateInstructionText]
        default: break
        }
        return []
    }
}


// Translate between events in Clew2AppState and events in CreateMapState
extension CreateARViewState.Event {
    init?(_ event: Clew2AppState.Event) {
        // Translate between events in CreatorAppState and events in RecordMapState
        switch event {
        case .DropGeospatialAnchorRequested:
            self = .DropGeospatialAnchorRequested
        case .DropPOIAnchorRequested:
            self = .DropPOIAnchorRequested
        case .DropDoorAnchorRequested:
            self = .DropDoorAnchorRequested
        case .DropStairAnchorRequested:
            self = .DropStairAnchorRequested
        case .ViewPOIsRequested(let mapName):
            self = .ViewPOIsRequested(mapName: mapName)
        case .NamePOIRequested:
            self = .NamePOIRequested
        case .NewARFrame(let cameraFrame):
            self = .NewARFrame(cameraFrame: cameraFrame)
        case .NewTagFound(let tag, let cameraTransform, let snapTagsToVertical):
            self = .NewTagFound(tag: tag, cameraTransform: cameraTransform, snapTagsToVertical: snapTagsToVertical)
        case .PlanesUpdated(let planes):
            self = .PlanesUpdated(planes: planes)
        default: return nil
        }
    }
}

enum NavigateARViewState: StateType {
    // Lower level app states nested within NavigateMapState
    case NavigateARView
    
    // Initial state upon transitioning into the NavigateMapState
    static let initialState = NavigateARViewState.NavigateARView
    
    // All the effectual inputs from the app which NavigateMapState can react to
    enum Event {
        case LeaveNavigateARViewRequested(mapName: String) // takes users to POIScreen state
        case ChangeRouteRequested(mapName: String, POIName: String) // we may need to save the mapName so that we can redirect users to a new POI destination
        case PlanPath
        case EndpointReached(mapName: String, finalEndpoint: Bool) // POI cloud anchor resolved
        case RateMapRequested(mapName: String)
        // events handled in higher level (to change to higher level state)
        case HomeScreenRequested
        case POIScreenRequested(mapName: String)
        
        // Frame handling events
        case NewARFrame(cameraFrame: ARFrame) // to update AR screen during map creation
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) // if we are still using April tags
        case PlanesUpdated(planes: [ARPlaneAnchor])
    }
    
    // Refers to commands defined in Clew2AppState - adds onto created commands for NavigateMapState
    typealias Command = Clew2AppState.Command
    
    // In response to an event, CreateMapState may emit a command
    mutating func handle(event:Event) -> [Command] {
        switch (self, event) {
        case (.NavigateARView, .LeaveNavigateARViewRequested(let mapName)):
            self = .NavigateARView
            return [.LeaveARView(mapName: mapName)]
        case (.NavigateARView, .ChangeRouteRequested(let mapName, let POIName)):
            self = .NavigateARView
            return [.ModifyRoute(mapname: mapName, POIName: POIName)]
        case (.NavigateARView, .PlanPath):
            return [.PlanPath]
        case (.NavigateARView, .EndpointReached(let mapName, let finalEndpoint)):
            self = .NavigateARView
            return [.LoadEndPopUp(mapName: mapName)]
        case (.NavigateARView, .RateMapRequested(let mapName)):
            self = .NavigateARView
            return [.LoadRatePopUp(mapName: mapName)]
        case (.NavigateARView, .NewARFrame(let cameraFrame)):
            return [.UpdatePoseVIO(cameraFrame: cameraFrame), .UpdateNavigateInstructionText]
            
        default: break
        }
        return []
    }
}

// Translate between events in Clew2AppState and events in NavigateMapState
extension NavigateARViewState.Event {
    init?(_ event: Clew2AppState.Event) {
        switch event {
        case .LeaveNavigateARViewRequested(let mapName): // lower level event
            self = .LeaveNavigateARViewRequested(mapName: mapName) // switch to higher level event
        case .ChangeRouteRequested(let mapName, let POIName):
            self = .ChangeRouteRequested(mapName: mapName, POIName: POIName)
        case .PlanPath:
            self = .PlanPath
        case .EndpointReached(let mapName, let finalEndpoint):
            self = .EndpointReached(mapName: mapName, finalEndpoint: finalEndpoint)
        case .RateMapRequested(let mapName):
            self = .RateMapRequested(mapName: mapName)
        case .NewARFrame(let cameraFrame):
            self = .NewARFrame(cameraFrame: cameraFrame)
        case .NewTagFound(let tag, let cameraTransform, let snapTagsToVertical):
            self = .NewTagFound(tag: tag, cameraTransform: cameraTransform, snapTagsToVertical: snapTagsToVertical)
        case .PlanesUpdated(let planes):
            self = .PlanesUpdated(planes: planes)
        default: return nil
        }
    }
}















