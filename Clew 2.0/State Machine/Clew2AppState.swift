//
//  AppState.swift
//  Clew 2.0
//
//  Created by Joyce Chung & Gabby Blake on 2/11/23.
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import Foundation
import ARKit //change

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
        case DomainSelected // top of name hierarchy (i.e. Food & Drinks)
        
        // FamilyScreen events
        case FamilySelected // next in name hierarchy (i.e. Restaurants - one option in Food & Drinks)
        
        // LocationScreen events
        case LocationSelected(mapName: String) // (i.e. Cheescake Factory - a restaurant)
        
        // POIScreen events
        case ReviewsSelected(mapName: String) // users want to see the reviews for the POIs in this map
        case POISelected(mapName: String) // last in name hierarchy (i.e. Restroom in Cheescake Factory)
        case PreviewDirectionSelected(mapName: String) //user wants to see map of all routes in that location (map of Cheesecake Factory)
        
        // NameMapScreen events
        case StartCreationRequested // pressing Continue button after enteirng map naming and categorizing info
        
        // ReviewsScreen events TBD
        
        // PreviewDirectionScreen events TBD
        
        // CreateARView events
        case DropGeospatialAnchorRequested // anchors outside the establishment
        case DropPOIAnchorRequested(cloudIdentifier: String, withTransform: simd_float4x4) // POI cloud anchors
        // TODO: cloud anchors are both breadcrumbs and can be named as POIs - need to figure out the time interval at which it should be dropped or if we should make users drop it frequently and name those that they want to
        case DropDoorAnchorRequested(cloudIdentifier: String, withTransform: simd_float4x4)
        case DropStairAnchorRequested(cloudIdentifier: String, withTransform: simd_float4x4)
        case ViewPOIsRequested
        case NamePOIRequested
        case SaveMapRequested(mapName: String)
        case LeaveCreateARViewRequested(mapName: String)
        
        // Frame handling events
        case NewARFrame(cameraFrame: ARFrame) // to update AR screen during map creation
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) // if we are still using April tags
        case PlanesUpdated(planes: [ARPlaneAnchor])
        
        // NavigateARView events
        case StartNavigationRequested(mapName: String) // pressing a POI button in the Location Screen
        case LeaveNavigateARViewRequested(mapName: String) // takes users to POIScreen state
        case ChangeRouteRequested(mapName: String, POIName: String) // we may need to save the mapName so that we can redirect users to a new POI destination
        case PlanPath
        // resolving anchors
        case ResolvedCloudAnchor
        case EndpointReached(mapName: String, finalEndpoint: Bool)
        case RateMapRequested(mapName: String)
        case HomeScreenRequested
        case POIScreenRequested(mapName: String)
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
        
        case LeaveMap(mapName: String)
        
        // CreateARView commands
        case DropGeospatialAnchor(location: LocationInfoGeoSpatial)
        case DropPOIAnchor(cloudIdentifier: String, withTransform: simd_float4x4)
        case DropDoorAnchor(cloudIdentifier: String, withTransform: simd_float4x4)
        case DropStairAnchor(cloudIdentifier: String, withTransform: simd_float4x4)
        case ViewPOIs(mapName: String)
        case NamePOI
        case SaveMapToFirebase(mapName: String)
        case LeaveCreateARView(mapName: String)
        //case LocateAndCategorizeMap // user uses GPS to automatically categorize the map - map still needs to be named
        //case LoadAndCategorizeMap(mapName: String) // user searches for a location that doesn't have a map yet and creates a map for that location - map already named

        
        // NavigateARView commands
        case ResolvedCloudAnchor
        case PlanPath
        case UpdateInstructionText
        case UpdatePoseVIO(cameraFrame: ARFrame)
        case UpdatePoseTag(tag: AprilTags, cameraTransform: simd_float4x4)
        case ModifyRoute(mapname: String, POIName: String) // call StartNavigation to a new POI endpoint
        case LoadEndPopUp(mapName: String)
        case LoadRatePopUp(mapName: String)
        case LeaveNavigateARView(mapName: String)
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
            return [.LeaveCreateARView(mapName: mapName)]
            
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
        case DropPOIAnchorRequested(cloudIdentifier: GARAnchor.cloudIdentifier, withTransform: GARAnchor.transform)
        case DropDoorAnchorRequested(cloudIdentifier: GARAnchor.cloudIdentifier, withTransform: GARAnchor.transform)
        case DropStairAnchorRequested(cloudIdentifier: GARAnchor.cloudIdentifier, withTransform: GARAnchor.transform)
        case ViewPOIsRequested(mapName:String)
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
        case .DropPOIAnchorRequested(let cloudIdentifier, let withTransform):
            self = .DropPOIAnchorRequested(cloudIdentifier: cloudIdentifier, withTransform: withTransform)
        case .DropDoorAnchorRequested(let cloudIdentifier, let withTransform):
            self = .DropDoorAnchorRequested(cloudIdentifier: cloudIdentifier, withTransform: withTransform)
        case .DropStairAnchorRequested(let cloudIdentifier, let withTransform):
            self = .DropStairAnchorRequested(cloudIdentifier: cloudIdentifier, withTransform: withTransform)
        case .ViewPOIsRequested(let mapName):
            self = .ViewPOIsRequested(let mapName)
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
            return [.LeaveNavigateARView(mapName: mapName)]
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
            return [.UpdatePoseVIO(cameraFrame: cameraFrame), .UpdateInstructionText]
            
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















