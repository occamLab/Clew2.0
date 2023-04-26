//
//  NavigateMapView.swift
//  Clew 2.0
//
//  Created by Joyce Chung & Gabby Blake on 2/11/23.
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import SwiftUI
import FirebaseAuth

// Describes all the instructions that will exist on-screen for the user
enum NavigationInstructionType: Equatable {
    // April tag instruction cases
    case start(startTime: Double)  // initial instructions when navigate map screen is opened
    case tagFound(startTime: Double)  // pops up each time a tag is found during navigation
    
    // Geospatial anchor instruction case: outside establishment
    case geospatialAnchorResolved(startTime: Double) // starting point outside establishment found
    
    // Cloud anchor instruction cases
    case POICloudAnchorResolved(startTime: Double) // cloud anchor found
    case doorCloudAnchorResolved(startTime: Double)
    case stairCloudAnchorResolved(startTime: Double)

    // Other cases
    case destinationReached(startTime: Double)  // feedback that user has reached their endpoint
    case none  // when there are no instructions/feedback to display

    var text: String? {
        get {
            switch self {
                case .start: return "To start navigation, press START TAG DETECTION and pan your camera until you are notified of a tag detection. Follow the ping sound along the path. The ping will grow quieter the further you face away from the right direction. "
                case .tagFound: return "Tag detected! In order to stabalize the path, press STOP TAG DETECTION." //Press STOP TAG DETECTION until you reach the next tag."
                
                case .geospatialAnchorResolved: return "Starting point outside the establishment found. You may begin navigation to the entrance."
                case .POICloudAnchorResolved: return "Point of interest found." // point of interest (ex. H&M at a Mall) found
                case .doorCloudAnchorResolved: return "Door found."
                case .stairCloudAnchorResolved: return "Stair found."
                case .destinationReached: return "You have arrived at your destination!"
                case .none: return nil
            }
        }
        // Set start times for each instruction text so that it shows on the screen for a set amount of time (set in transition func).
        set {
            switch self {
                case .start: self = .start(startTime: NSDate().timeIntervalSince1970)
                case .tagFound: self = .tagFound(startTime: NSDate().timeIntervalSince1970)
                case .geospatialAnchorResolved: self = .geospatialAnchorResolved(startTime: NSDate().timeIntervalSince1970)
                case .POICloudAnchorResolved: self = .POICloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            case .doorCloudAnchorResolved: self = .doorCloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            case .stairCloudAnchorResolved: self = .stairCloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
                case .destinationReached: self = .destinationReached(startTime: NSDate().timeIntervalSince1970)
                case .none: self = .none
            }
        }
    }
    
    // To get start time of when the instructions were displayed
    func getStartTime() -> Double {
        switch self {
        case .start(let startTime), .tagFound(let startTime), .geospatialAnchorResolved(let startTime), .POICloudAnchorResolved(let startTime), .doorCloudAnchorResolved(let startTime), .stairCloudAnchorResolved(let startTime), .destinationReached(let startTime):
            return startTime
        default:
            // .none case
            return -1
        }
    }
    
    // Function to transition from one instruction text field to another; when to display instructions/feedback text and to control how long it stays on screen
    mutating func transition(tagFound: Bool, didGeospatialAnchorResolved: Bool, didCloudAnchorResolved: Bool, cloudAnchorType: String, endPointReached: Bool = false) {
        
        let previousInstruction = self // current instruction that's updated every time there's a transition
        
        print("text state previous instruction: \(previousInstruction)") // debugging purposes
        print("text state: \(self.text)")
        
        switch self {
        case .start:
            if tagFound { // when first tag is found -> tagFound
                print("switch instructions from start to tagFound after camera finds the first tag")
                self = .tagFound(startTime: NSDate().timeIntervalSince1970)
            // instead of the first tag, an anchor can be resolved to start navigation
            } else if didGeospatialAnchorResolved {
                print("switch instructions from start to geospatialAnchor after finding geospatial anchor outside establishment")
                self = .geospatialAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if didCloudAnchorResolved && (cloudAnchorType == "POI") {
                print("switch instructions from start to POICloudAnchorResolved after finding a cloud anchor at a point of interest marked (i.e. a store POI in a market)")
                self = .POICloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if didCloudAnchorResolved && (cloudAnchorType == "door") {
                print("switch instructions from start to doorCloudAnchorResolved after finding cloud anchor at a door")
                self = .doorCloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if didCloudAnchorResolved && (cloudAnchorType == "stair") {
                print("switch instructions from start to stairCloudAnchorResolved after finding cloud anchor at stairs")
                self = .stairCloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            }
            
        case .tagFound:
            // case stays as .tagFound until frame is processed again when 'Start Tag Detection' is pressed again -> resets seesTag variable depending on reprocessed camera AR frame.
            if !Clew2AppController.shared.mapNavigator.seesTag {
                print("tagFound -> none case - camera doesn't see tag so get rid of instruction text field")
                self = .none
            }
            
        case .geospatialAnchorResolved:
            print("case is geospatial anchor resolved")
            self = .none
            
        case .POICloudAnchorResolved:
            print("case is POI cloud anchor resolved")
            self = .none
            
        case .doorCloudAnchorResolved:
            print("case is door cloud anchor resolved")
            self = .none
            
        case .stairCloudAnchorResolved:
            print("case is stair cloud anchor resolved")
            self = .none
            
        case .destinationReached:
            print("case is destination reached")
            break
            
        case .none:
            print("case is none")
            // seesTag is not reset until tag detection starts again
            if Clew2AppController.shared.mapNavigator.seesTag {
                self = .tagFound(startTime: NSDate().timeIntervalSince1970)
            // update instructions when an anchor is resolved
            } else if didGeospatialAnchorResolved {
                self = .geospatialAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if didCloudAnchorResolved && (Clew2AppController.shared.cloudAnchorType == "POI") {
                self = .POICloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if didCloudAnchorResolved && (Clew2AppController.shared.cloudAnchorType == "door") {
                self = .doorCloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if didCloudAnchorResolved && (Clew2AppController.shared.cloudAnchorType == "stair") {
                self = .stairCloudAnchorResolved(startTime: NSDate().timeIntervalSince1970)
            } else if endPointReached {
                self = .destinationReached(startTime: NSDate().timeIntervalSince1970)
            }
        
        if self != previousInstruction {
            let instructions = self.text
            print("text state: \(instructions)")
            print("end point reached: \(endPointReached)")
            if endPointReached {
                print("text state: \(instructions)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    UIAccessibility.post(notification: .announcement, argument: instructions)
                }
            } else {
                print("text state: \(instructions)")
                UIAccessibility.post(notification: .announcement, argument: instructions)
            }
        } else {
            let currentTime = NSDate().timeIntervalSince1970
            // time that instructions stay on screen
            print("current time: \(currentTime)")
            print("start time: \(self.getStartTime())")
            print("current - start time = \(currentTime - self.getStartTime())")
            
            if currentTime - self.getStartTime() > 12 {
                self = .none
            }
        }
    }
}
}



// Provides persistent storage for on-screen instructions and state variables outside of the view struct
    class NavigateGlobalState: ObservableObject, NavigateViewController {
    
    // for testing purposes
    @ObservedObject var navigation = Navigation()
    @Published var binaryDirectionKey = NavigationBinaryDirection.none
    @Published var binaryDirection: String = ""
    @Published var clockDirectionKey = NavigationClockDirection.none
    @Published var clockDirection: String = ""
    
    @Published var tagFound: Bool
    // TODO: resolve anchors in ARView and use the NavigateGlobalStateSingleton to set the variables to true
    @Published var didGeospatialAnchorResolved: Bool
    @Published var didCloudAnchorResolved: Bool
    @Published var endPointReached: Bool // set to true in ARView using the NavigateGlobalStateSingleton when current position is within endpointSphere
    @Published var navigationInstructionWrapper: NavigationInstructionType
    
    init() {
        tagFound = false
        didGeospatialAnchorResolved = false
        didCloudAnchorResolved = false
        //cloudAnchorType = nil // TODO: update value if didCloudAnchorResolved is true using the label that map creators chose when dropping this cloud anchor (POI, door, stair)
        endPointReached = false
        navigationInstructionWrapper = .start(startTime: NSDate().timeIntervalSince1970)
        Clew2AppController.shared.navigateViewer = self
    }
    
    // Navigate view controller commands
    func updateNavigateInstructionText() {
        DispatchQueue.main.async {
            if let map = Clew2AppController.shared.mapNavigator.map {
                if !map.firstTagFound {
                    self.tagFound = false
                } else {
                    print("first tag was found!")
                    self.tagFound = true
                }
                print("Instruction wrapper: \(self.navigationInstructionWrapper)")
                print("tagFound: \(self.tagFound)")
                
                self.navigationInstructionWrapper.transition(tagFound: self.tagFound, didGeospatialAnchorResolved: self.didGeospatialAnchorResolved, didCloudAnchorResolved: self.didCloudAnchorResolved, cloudAnchorType: Clew2AppController.shared.cloudAnchorType, endPointReached: self.endPointReached)
                
                print("Instruction wrapper: \(self.navigationInstructionWrapper)")
            }
        }
    }
}


class NavigateGlobalStateSingleton {
    public static var shared = NavigateGlobalState()
}

struct NavigateMapView: View {
    @ObservedObject var navigateGlobalState = NavigateGlobalStateSingleton.shared

    var mapFileName: String
    
    init(mapFileName: String = "") {
        print("currentUser is \(Auth.auth().currentUser!.uid)")
        self.mapFileName = mapFileName
    }
    
    var body : some View {
        ZStack {
            BaseNavigationView()
                // Toolbar buttons
                .toolbar(content: {
                    ToolbarItem(placement: .navigationBarLeading) {
                        MapNavigateExitButton(mapFileName: mapFileName)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        GetDirectionsButton()
                    }
                })
            VStack {
                
                // for testing purposes; TODO: update text with directions
                Text("Binary direction: \(navigateGlobalState.binaryDirection)")
                Text("Clock direction: \(navigateGlobalState.clockDirection)")
                
                // Show instructions if there are any
                if navigateGlobalState.navigationInstructionWrapper.text != nil {
                    InstructionOverlay(instruction: $navigateGlobalState.navigationInstructionWrapper.text)
                        .animation(.easeInOut)
                }
                TagDetectionButton(navigateGlobalState: navigateGlobalState)
                    .environmentObject(Clew2AppController.shared.mapNavigator)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .padding()
        }
        .ignoresSafeArea(.keyboard)
    }
}

extension UINavigationController {
    override open func viewDidLoad() {
        super.viewDidLoad()
      //  self.navigationItem.hidesBackButton = true
        // Creates a translucent toolbar
        let toolbarAppearance = UIToolbarAppearance()
        toolbarAppearance.configureWithTransparentBackground()
        toolbarAppearance.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
        UIToolbar.appearance().standardAppearance = toolbarAppearance
    }
}

/*
struct NavigateMapView_Previews: PreviewProvider {
    static var previews: some View {
        NavigateMapView()
    }
}
*/
