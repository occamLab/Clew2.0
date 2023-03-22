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
        case CreateMapRequested
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
        case StartCreationRequested(mapName: String) // pressing Continue button after enteirng map naming and categorizing info
        
        // ReviewsScreen events TBD
        // PreviewDirectionScreen events TBD
        
        // CreateARView events
        case DropGeospatialAnchorRequested
        case DropCloudAnchorRequested
        case DropDoorAnchorRequested
        case DropStairAnchorRequested
        case ViewPOIsRequested
        case NamePOIRequested
        case SaveMapRequested(mapName: String)
        case CancelMapRequested
        
        // NavigateARView events
        case LeaveMapRequested(mapName: String) // takes users to POIScreen state
        case ChangeRouteRequested(mapName: String) // we may need to save the mapName so that we can redirect users to a new POI destination
        case EndpointReached
        case RateMapRequested(mapName: String)
        case HomeScreenRequested
        
        // events common to both CreateARView and NavigateARView
        case NewARFrame(cameraFrame: ARFrame) // to update AR screen during map creation
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) // if we are still using April tags
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
        case LoadPreviewDirections
        
        // ReviewsScreen commands TBD
        // PreviewDirectionScreen commands TBD
        
        //NameMapScreen commands TBD
        case StartCreation(mapName: String)
        
        // CreateARView commands
        //case LocateAndCategorizeMap // user uses GPS to automatically categorize the map - map still needs to be named

        //case LoadAndCategorizeMap(mapName: String) // user searches for a location that doesn't have a map yet and creates a map for that location - map already named
        case DropGeospatialAnchor
        case DropCloudAnchor
        case DropDoorAnchor
        case DropStairAnchor
        case ViewPOIs
        case NamePOI
        case SaveMap(mapName: String)
        case CancelMap(mapName: String)
        
        // NavigateARView commands
        case LeaveMap(mapName: String)
        case ModifyRoute(mapname: String, POIName: String) // call StartNavigation to a new POI endpoint
        case LoadEndPopUp(mapName: String)
        case LoadRatePopUp(mapName: String)
    }
    
    // In response to an event, a state may transition to a new state, and it may emit a command
    mutating func handle(event: Event) -> [Command] {
        print("Last State: \(self), \(event)")
        switch (self, event) {
        case (.HomeScreen, .CreateMapRequested):
            self = .NameMapScreen
            return [.NameMap] // should we send to Firebase after user presses 'Finished'?
        case (.NameMapScreen, .StartCreationRequested(let mapName)):
            self = .CreateARView
            return [.StartCreation]
            
            
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
            return [.LoadPreviewDirections]
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
            
        // handling lower level events for NavigateMapState
        case (.NavigateARView(let state), _) where NavigateARViewState.Event(event) != nil:
            var newState = state
            let commands = newState.handle(event: NavigateArViewState.Event(event)!)
            self = .NavigateARView(newState)
            return commands
            
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
        case DropGeospatialAnchorRequested // anchors outside the establishment
        case DropCloudAnchorRequested // cloud anchors are both breadcrumbs and can be named as POIs - need to figure out the time interval at which it should be dropped or if we should make users drop it frequently and name those that they want to
        case DropDoorAnchorRequested
        case DropStairAnchorRequested
        case ViewPOIsRequested
        case NamePOIRequested
        case SaveMapRequested(mapName: String)
        case CancelMapRequested(mapName: String)
        
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
        case (.CreateARView, .DropCloudAnchorRequested):
            self = .CreateARView
            return [.DropCloudAnchor]
        case (.CreateARView, .DropDoorAnchorRequested):
            self = .DropDoorAnchorState
            return [.DropDoorAnchor]
        case (.CreateARView, .DropStairAnchorRequested):
            self = .DropStairAnchorState
            return [.DropStairAnchor]
        case (.CreateARView, .ViewPOIsRequested):
            self = .CreateARView
            return [.ViewPOIs]
        case (.CreateARView, .SaveMapRequested(let mapName))
            self = .POIScreen
            return [.SaveMap(mapName: mapName)]
        case (.CreateARView, .CancelMapRequested(let mapName))
            self = .POIScreen
            return [.CancelMap(mapName: mapName)]
        default: break
        }
        return []
    }
}

// Translate between events in Clew2AppState and events in CreateMapState
extension CreateARViewState.Event {
    init?(_ event: Clew2AppState.Event) {
        switch event {
            
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
        case LeaveMapRequested(mapName: String) // takes users to POIScreen state
        case ChangeRouteRequested(mapName: String, POIName: String) // we may need to save the mapName so that we can redirect users to a new POI destination
        case EndpointReached (mapName: String)
        case HomeScreenRequested
        case POIScreenRequested(mapName: String)
        case RateMapRequested(mapName: String)
        
        // frame handling events
        case NewARFrame(cameraFrame: ARFrame) // to update AR screen during map creation
        case NewTagFound(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) // if we are still using April tags
        case PlanesUpdated(planes: [ARPlaneAnchor])
        
    }
    
    // Refers to commands defined in Clew2AppState - adds onto created commands for NavigateMapState
    typealias Command = Clew2AppState.Command
    
    // In response to an event, CreateMapState may emit a command
    mutating func handle(event:Event) -> [Command] {
        switch (self, event) {
        case (.NavigateARView, .LeaveMapRequested(let mapName))
            self = .NavigateARView
            return [.LeaveMap(mapFileName: mapName)]
        case (.NavigateARView, .ChangeRouteRequested(let mapName, let POIName))
            self = .NavigateARView
            return [.ModifyRoute(mapname: mapName, POIName: POIName)]
        case (.NavigateARView, .EndpointReached(let mapName))
            self = .NavigateARView
            return [.LoadEndPopUp(mapName: mapName)]
        case (.NavigateARView, .HomeScreenRequested)
            self = .HomeScreen
            return []
        case (.NavigateARView, .POIScreenRequested(let mapName))
            self = .POIScreen
            return [.LoadPOIScreen(mapFileName: mapName)]
        case (.NavigateARView, .RateMapRequested(let mapName))
            self = .NavigateARView
            return [.LoadRatePopUp(mapName: mapName)]
        
        default: break
        }
        return []
    }
}

// Translate between events in Clew2AppState and events in NavigateMapState
extension NavigateARViewState.Event {
    init?(_ event: Clew2AppState.Event) {
        switch event {
            
        default: return nil
        }
    }
}
