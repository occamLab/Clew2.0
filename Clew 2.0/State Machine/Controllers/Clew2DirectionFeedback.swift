//
//  Clew2DirectionFeedback.swift
//  Clew 2.0
//
//  Created by Joyce Chung and Gabby Blake on 7/13/22.
//  Adapted from Clew Maps' Navigation.swift
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import Foundation

/// Current state of the user along the path in the map relative to the endpoint
public enum PositionState {
    /// user is far from endpoint
    case notAtEndpoint
    /// user is at endpoint
    case atEndpoint
    /// user is close to the endpoint
    case closeToEndpoint
}

/// Struct to store information about user's current position relative to path on map
public struct DirectionInfo {
    /// key of the clock direction that's associated with the description of the angle to next keypoint
    var clockDirectionKey: NavigationClockDirection
    /// key of the binary direction that's associated with the description of the angle to next keypoint
    var binaryDirectionKey: NavigationBinaryDirection
    /// distance in meters from the tag or waypoint destination
    var distanceToEndpoint: Float
    /// angle in radians of the user's current path from the right path in the map
    var angleDiffFromPath: Float
    var endPointState = PositionState.notAtEndpoint
    
    /// Initialize a DirectionInfo Object
    init(clockDirectionKey: NavigationClockDirection, binaryDirectionKey: NavigationBinaryDirection, distanceToEndpoint: Float, angleDiffFromPath: Float) {
        self.clockDirectionKey = clockDirectionKey
        self.binaryDirectionKey = binaryDirectionKey
        self.distanceToEndpoint = distanceToEndpoint
        self.angleDiffFromPath = angleDiffFromPath
    }
}

    enum NavigationClockDirection {
        case twelve
        case one
        case two
        case three
        case four
        case five
        case six
        case seven
        case eight
        case nine
        case ten
        case eleven
        case none
    }
    
    /// Dictionary of clock directions
    ///
    /// * Keys (`Int` from 1 to 12 inclusive): clock position
    /// * Values (`String`): corresponding spoken direction (e.g. "Slight right towards 2 o'clock")
    func clockDirectionToDirectionText(dir: NavigationClockDirection) -> String {
        switch (dir) {
        case .twelve:
            return NSLocalizedString("straightDirection", comment: "Direction to user to continue moving in forward direction")
        case .one:
            return NSLocalizedString("1o'clockDirection", comment: "direction to the user to turn towards the 1 o'clock direction")
        case .two:
            return NSLocalizedString("2o'clockDirection", comment: "direction to the user to turn towards the 2 o'clock direction")
        case .three:
            return NSLocalizedString("rightDirection", comment: "Direction to the user to make an approximately 90 degree right turn.")
        case .four:
            return NSLocalizedString("4o'clockDirection", comment: "direction to the user to turn towards the 4 o'clock direction")
        case .five:
            return NSLocalizedString("5o'clockDirection", comment: "direction to the user to turn towards the 5 o'clock direction")
        case .six:
            return NSLocalizedString("6o'clockDirection", comment: "direction to the user to turn towards the 6 o'clock direction")
        case .seven:
            return NSLocalizedString("7o'clockDirection", comment: "direction to the user to turn towards the 7 o'clock direction")
        case .eight:
            return NSLocalizedString("8o'clockDirection", comment: "direction to the user to turn towards the 8 o'clock direction")
        case .nine:
            return NSLocalizedString("leftDirection", comment: "Direction to the user to make an approximately 90 degree left turn.")
        case .ten:
            return NSLocalizedString("10o'clockDirection", comment: "direction to the user to turn towards the 10 o'clock direction")
        case .eleven:
            return NSLocalizedString("11o'clockDirection", comment: "direction to the user to turn towards the 11 o'clock direction")
        case .none:
            return ""
        }
    }
    
    enum NavigationBinaryDirection {
        case straight
        case slightRight
        case right
        case uturn
        case left
        case slightLeft
        case none
    }

    func binaryDirectionToDirectionText(dir: NavigationBinaryDirection) -> String {
        switch (dir) {
        case .straight:
            return NSLocalizedString("straightDirection", comment: "Direction to user to continue moving in forward direction")
        case .slightRight:
            return NSLocalizedString("slightRightDirection", comment: "Direction to user to take a slight right turn")
        case .right:
            return NSLocalizedString("rightDirection", comment: "Direction to the user to make an approximately 90 degree right turn.")
        case .uturn:
            return NSLocalizedString("uTurnDirection", comment: "Direction to the user to turn around")
        case .left:
            return NSLocalizedString("leftDirection", comment: "Direction to the user to make an approximately 90 degree left turn.")
        case .slightLeft:
            return NSLocalizedString("slightLeftDirection", comment: "Direction to user to take a slight left turn")
        case .none:
            return ""
        }
    }

/// Navigation class that provides direction information based on current camera position and the endpoint position in the mapFrame
class Navigation: ObservableObject {
    @Published var cosValue: Float = 0.0
    /// Gets the clock direction, binary direction, and distance to endpoint information from the user's current location
    func getDirections() -> DirectionInfo {
        // default value in case arViewer doesn't exist which is never the case(?)
        var direction = DirectionInfo(clockDirectionKey: .none, binaryDirectionKey: .none, distanceToEndpoint: 0.0, angleDiffFromPath: 0.0)
        
        if let arViewer = Clew2AppController.shared.arViewer {
            self.cosValue = arViewer.cosValue
            
            let endpointX = arViewer.endpointX
            let endpointY = arViewer.endpointY
            let endpointZ = arViewer.endpointZ
            
           // let nextPointOnPathX = arView.audioSourceX
           // let nextPointOnPathZ = arView.audioSourceZ
            
            let currentCameraPositionX = arViewer.currentCameraPosX
            let currentCameraPositionY = arViewer.currentCameraPosY
            let currentCameraPositionZ = arViewer.currentCameraPosZ
                
            let angleDiff = arViewer.angleDifference
            
            let clockDirectionKey = getClockDirection(angle: angleDiff)
            let binaryDirectionKey = getBinaryDirection(angle: angleDiff)
            let distanceToEndpoint = getDistanceToEndpoint(endpointX: endpointX, endpointY: endpointY, endpointZ: endpointZ, currPosX: currentCameraPositionX, currPosY: currentCameraPositionY, currPosZ: currentCameraPositionZ)
            
            direction = DirectionInfo(clockDirectionKey: clockDirectionKey, binaryDirectionKey: binaryDirectionKey, distanceToEndpoint: distanceToEndpoint, angleDiffFromPath: angleDiff)
            
            if NavigateGlobalStateSingleton.shared.endPointReached == true {
                direction.endPointState = .atEndpoint
            }
            else if distanceToEndpoint < Clew2AppController.shared.mapNavigator.endpointSphere {
                direction.endPointState = .closeToEndpoint
            }
            else {
                direction.endPointState = .notAtEndpoint
            }
            return direction
        
        } else {
            return direction
        }
    }
}

/// Determine clock direction from angle in radians, where 0 radians is 12 o'clock.
///
/// - Parameter angle: input angle in radians
/// - Returns: `Int` between 1 and 12, inclusive, representing clock position
private func getClockDirection(angle: Float) -> NavigationClockDirection {
    let clockDirectionKey: Int = Int(angle * (6 / Float.pi))
    print("clock direction key: \(clockDirectionKey)")
    if clockDirectionKey == 0 {
        return .twelve
    }
    else if clockDirectionKey == 1 {
        return .one
    }
    else if clockDirectionKey == 2 {
        return .two
    }
    else if clockDirectionKey == 3 {
        return .three
    }
    else if clockDirectionKey == 4 {
        return .four
    }
    else if clockDirectionKey == 5 {
        return .five
    }
    else if clockDirectionKey == 6 {
        return .six
    }
    else if clockDirectionKey == 7 {
        return .seven
    }
    else if clockDirectionKey == 8 {
        return .eight
    }
    else if clockDirectionKey == 9 {
        return .nine
    }
    else if clockDirectionKey == 10 {
        return .ten
    }
    else if clockDirectionKey == 11 {
        return .eleven
    }
    else {
        return .none
    }
}

/// Divides all possible directional angles into 7 sections for using with haptic feedback.
///
/// - Parameter angle: angle in radians from straight ahead.
/// - Returns: `String` that represents the direction the user needs to go
private func getBinaryDirection(angle: Float) -> NavigationBinaryDirection {
    // angle should be between [0, pi] and [0, -pi]
   /* var angleDiff = angle
    if angle > Float.pi {
        angleDiff = -1 * ((2 * Float.pi) - angle)
    } */
    
    print("angle in rad: \(angle)")
    print("angle in degrees: \(angle * (180/Float.pi))")
    
    if (-Float.pi/6 <= angle && angle <= Float.pi/6) {
        return .straight
    } else if (Float.pi/6 <= angle && angle <= Float.pi/3) {
        return .slightLeft
    } else if (Float.pi/3 <= angle && angle <= (2*Float.pi/3)) {
        return .left
    } else if ((2*Float.pi/3) <= angle && angle <= Float.pi) {
        return .uturn
    } else if (-Float.pi <= angle && angle <= -(2*Float.pi/3)) {
        return .uturn
    } else if (-(2*Float.pi/3) <= angle && angle <= -(Float.pi/3)) {
        return .right
    } else if (-Float.pi/3 <= angle && angle <= -Float.pi/6) {
        return .slightRight
    } else {
        return .none
    }
}

/// Calculates the distance from the user's current location to the endpoint's location
private func getDistanceToEndpoint(endpointX: Float, endpointY: Float, endpointZ: Float, currPosX: Float, currPosY: Float, currPosZ: Float) -> Float {
    let distanceToEndpoint = sqrt(pow((endpointX - currPosX),2) + pow((endpointY - currPosY),2) + pow((endpointZ - currPosZ),2))
    return distanceToEndpoint
}
