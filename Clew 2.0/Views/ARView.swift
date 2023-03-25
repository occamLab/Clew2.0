//
//  ARView.swift
//
//  Created by Marion Madanguit on 3/19/21.
//

import Foundation
import ARKit
import GLKit
import SwiftUI
import AVFoundation
import AudioToolbox
import MediaPlayer
// ARView ~ VC and ARSessionManager
// NEW CODE 03/10: Adding cloud anchors
import ARCore
import ARCoreCloudAnchors

protocol ARViewController {
    // Commands that interact with the ARView
    var supportsLidar: Bool { get }
    var lastRecordedTimestamp: Double { get set }
    func initialize()
    func detectTag(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool)
    func raycastTag(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) -> simd_float4x4?
    func pinLocation(locationName: String)
    func resetRecordingSession()
    func hostCloudAnchor(withTransform transform: simd_float4x4)
    func didHostCloudAnchor(cloudIndentifier: String, anchorIdentifier: String, withTransform transform : simd_float4x4)
    func sessionDidRelocalize()
}

//TODO: Check if this is needed
// ARViewIndicator
//struct ARViewIndicator: UIViewControllerRepresentable {
//   typealias UIViewControllerType = ARView
//
//   func makeUIViewController(context: Context) -> ARView {
//      return ARView()
//   }
//   func updateUIViewController(_ uiViewController:
//   ARViewIndicator.UIViewControllerType, context:
//   UIViewControllerRepresentableContext<ARViewIndicator>) { }
//}

class ARView: UIViewController {
    
    // var for debugging purposes for DirectionFeedback
    var cosValue: Float = 0.0
    
    /// next point on the map's path; always in front of the current phone position
    var audioSourceX: Float = 0.0
    var audioSourceZ: Float = 0.0
    
    /// position of the endpoint of the path
    var endpointX: Float = 0.0
    var endpointY: Float = 0.0
    var endpointZ: Float = 0.0
    
    /// position of current phone/camera
    var currentCameraPosX: Float = 0.0
    var currentCameraPosY: Float = 0.0
    var currentCameraPosZ: Float = 0.0
    
    /// angle in radians that tells you how off users are from the correct path on the map; 0 radians is when camera is facing in the same direction as path - var that's updated every 5 AR frames to not make DirectionFeedback less glitchy(?)
    var angleDifference: Float = 0.0
    
    // TODO: make less gross
    var pathNodes: [String: (SCNNode, Bool)] = [:]
    let memoryChecker : MemoryChecker = MemoryChecker()
    let configuration = ARWorldTrackingConfiguration()
    #if IS_MAP_CREATOR
        let sharedController = InvisibleMapCreatorController.shared
    #else
        let sharedController = InvisibleMapController.shared
    #endif
    let recordInterval = 0.1
    var lastRecordedTimestamp = -0.1
    let distanceToAnnounceWaypoint: Float = 1.5
    
    var mapNode: SCNNode?
    var detectionNode: SCNNode?
    var cameraNode: SCNNode?
    let locationNodeName = "Locations"
    let tagNodeName = "Tags"
    let crumbNodeName = "Crumbs"
    let edgeNodeName = "Edges"
    
    /// Speech synthesis objects (reuse these or memory will leak)
    let synth = AVSpeechSynthesizer()
    let voice = AVSpeechSynthesisVoice(language: "en-US")
    var lastSpeechTime : [String:Date] = [:]
    
    // audio and haptic feedback
    var audioPlayers: [String: AVAudioPlayer?] = [:]
    var pingTimer = Timer()
    var hapticGenerator : UIImpactFeedbackGenerator?
    
    var pathObjs: [SCNNode] = []
    
    // keep track of whether or not the session was, at any point, in the relocalizing state.  The behavior of the ARCamera.TrackingState is a bit erratic in that the session will sometimes execute unexpected sequences (e.g., initializing -> normal -> not available -> initializing -> relocalizing).
    var sessionWasRelocalizing = false
    
    
    // CLOUD & GEOSPATIAL ANCHOR
    enum LocalizationState {
        case none
        case withCloudAnchors
        case withARWorldMap
    }
    var localization: LocalizationState = .none
    var cameraPoses: [Any] = []
    var visualKeypoints: [KeypointInfo] = []
    var cameraLocationInfos: [LocationInfo] = []
    let storageBaseRef = Storage.storage().reference()
    static var shared = ARSessionManager()
    var delegate: ARSessionManagerDelegate?
    var lastTimeOutputtedGeoAnchors = Date()
    var lastGeospatialLogTime = Date()
    let geoSpatialAlignmentFilter = GeoSpatialAlignment()
    var filterGeoSpatial: Bool = false
    var disableARWorldMap: Bool = true
    var visualizeCloudAnchors: Bool = false
    var cloudAnchorSCNNodes: [String: SCNNode] = [:]
    let cloudNodeUpdater = DispatchQueue(label: "cloudNodeUpdater")
    
    @Published var worldTransformGeoSpatialPair: (simd_float4x4, GARGeospatialTransform)?

    /// This is embeds an AR scene.  The ARSession is a part of the scene view, which allows us to capture where the phone is in space and the state of the world tracking.  The scene also allows us to insert virtual objects
    var sceneView: ARSCNView = ARSCNView()
    
    /// this is the alignment between the reloaded route
    var manualAlignment: simd_float4x4? {
        willSet(myNewValue) {
            if let newValue = myNewValue {
                let oldValue = self.manualAlignment ?? matrix_identity_float4x4
                let relativeTransform = newValue * oldValue.inverse
                if let keypointNode = keypointNode {
                    keypointNode.simdTransform = relativeTransform * keypointNode.simdTransform
                }
                if let pathObj = pathObj {
                    pathObj.simdTransform = relativeTransform * pathObj.simdTransform
                }
            }
        }
    }
    
    var garSession: GARSession?
        
    /// Keep track of when to log a frame
    var lastFrameLogTime = Date()
    /// Keep track of when to log a pose
    var lastPoseLogTime = Date()
    
    /// Use these variables to keep track of rendering work that has to be done.  This allows us to do all of the rendering from one thread
    private var keypointRenderJob: (()->())?
    private var pathRenderJob: (()->())?
    private var intermediateAnchorRenderJobs: [RouteAnchorPoint : (()->())?] = [:]
    
    /// keep track of whether or not the session was, at any point, in the relocalizing state.  The behavior of the ARCamera.TrackingState is a bit erratic in that the session will sometimes execute unexpected sequences (e.g., initializing -> normal -> not available -> initializing -> relocalizing).
    var sessionWasRelocalizing = false
    
    var initialWorldMap: ARWorldMap? {
        set {
            if !disableARWorldMap {
                configuration.initialWorldMap = newValue
            }
        }
        get {
            return configuration.initialWorldMap
        }
    }
    
    /// AR Session Configuration
    private var configuration: ARWorldTrackingConfiguration!
    
    /// SCNNode of the next keypoint
    private var keypointNode: SCNNode?
    
    /// SCNNode of the bar path
    private var pathObj: SCNNode?
    
    /// SCNNode of the spherical pathpoints
    private var pathpointObjs: [SCNNode] = []
    
    /// SCNNode of the intermediate anchor points
    private var anchorPointNodes: [RouteAnchorPoint: SCNNode] = [:]
    /// Keypoint object
    var keypointObject : MDLObject!
    
    /// Speaker object
    var speakerObject: MDLObject!
    
    var currentFrame: ARFrame? {
        return sceneView.session.currentFrame
    }
    
    var outdoorLocalizationQualityThreshold: GeospatialOverallQuality = .excellent
    
    var currentGARFrame: GARFrame?
    
    var geoSpatialAlignmentCrumbs: [LocationInfoGeoSpatial] = [] {
        didSet {
            let accurateGeoSpatialCrumbs = geoSpatialAlignmentCrumbs.filter( {$0.headingUncertainty < GARGeospatialTransform.excellentQualityHeadingAccuracy && $0.altitudeUncertainty < GARGeospatialTransform.excellentQualityAltitudeAccuracy && $0.horizontalUncertainty < GARGeospatialTransform.excellentQualityHorizontalAccuracy } )
            for crumb in accurateGeoSpatialCrumbs {
                if let newAnchor = addGeoSpatialAnchor(location: crumb) {
                    crumb.GARAnchorUUID = newAnchor.identifier
                }
            }
        }
    }
    
    // TODO: we can probably get rid of these and use the cloudIdentifier as our key
    private var sessionCloudAnchors: [UUID: ARAnchor] = [:]
    
    var lastResolvedCloudAnchorID: String?
    
    // TODO: we could have used String instead of NSString (be careful of breaking existing routes though)
    var cloudAnchorsForAlignment: [NSString: ARAnchor] = [:] {
        didSet {
            sessionCloudAnchors = [:]
            if cloudAnchorsForAlignment.count > 20 {
                let tooManyAnchors = "Too many cloud anchors. Results may be unpredictable."
               // AnnouncementManager.shared.announce(announcement: tooManyAnchors)
          //      PathLogger.shared.logSpeech(utterance: tooManyAnchors)
            }
            for cloudAnchor in cloudAnchorsForAlignment {
                do {
                    if let gAnchor = try garSession?.resolveCloudAnchor(String(cloudAnchor.0)) {
                        
                        
                        // log the cloud anchors
                     //   PathLogger.shared.logCloudAnchorForAlignment(anchorIdentifier: gAnchor.identifier.uuidString, cloudAnchorID: String(cloudAnchor.0), anchorTransform: cloudAnchor.1)

                        sessionCloudAnchors[gAnchor.identifier] = cloudAnchor.1
                        print("trying to resolve \(cloudAnchor.0)")
                    }
                } catch {
                    print("synchronous failure to resolve")
                }
            }
        }
    }


    // Create an AR view
    @IBOutlet var arView: ARSCNView! {
        get {
            return self.view as? ARSCNView
        }
        set(newView) {
            self.view = newView
        }
    }
    
    override func loadView() {
      self.view = ARSCNView(frame: .zero)
    }
    
    // Load, assign a delegate, and create a scene
    override func viewDidLoad() {
        super.viewDidLoad()
        arView.session.delegate = self
        arView.scene = SCNScene()
        sharedController.arViewer = self
        configuration.planeDetection = [.horizontal, .vertical]
        //if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
        //    configuration.sceneReconstruction = .mesh
        //}
        sharedController.initialize()
    }
    
    // Functions for standard AR view handling
    override func viewDidAppear(_ animated: Bool) {
       super.viewDidAppear(animated)
    }
    override func viewDidLayoutSubviews() {
       super.viewDidLayoutSubviews()
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        arView.session.run(configuration)
        // TODO: have one function to run session (run Session)
    }
    override func viewWillDisappear(_ animated: Bool) {
       super.viewWillDisappear(animated)
       arView.session.pause()
    }
    
    /// Creating cloud anchor using an existing local ARAnchor
    func hostCloudAnchor(withTransform transform: simd_float4x4)->(GARAnchor, ARAnchor)? {
        let newAnchor = ARAnchor(transform: transform)
        add(anchor: newAnchor)
        do {
            if let newGARAnchor = try garSession?.hostCloudAnchor(newAnchor) {
                return (newGARAnchor, newAnchor)
            }
        } catch {
            print("host cloud anchor failed \(error.localizedDescription)")
        }
        return nil
    }
    
    /// creating a geospatial anchor
    func addGeoSpatialAnchor(location: LocationInfoGeoSpatial)->GARAnchor? {
        let headingAngle = (Double.pi / 180) * (180.0 - location.heading);
        let eastUpSouthQAnchor = simd_quaternion(Float(headingAngle), simd_float3(0, 1, 0));
        do {
            return try! garSession?.createAnchor(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude), altitude: location.altitude, eastUpSouthQAnchor: eastUpSouthQAnchor)
        }
    }
}

extension ARView: ARSessionDelegate {
    public func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        //NavigationController.shared.trackingStatusChanged(session: session, camera: camera)
    }
    
    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        #if IS_MAP_CREATOR
            let processingFrame = self.sharedController.mapRecorder.processingFrame
            let exitingMap = false
        #else
            //if we are in preparingtoleavemap state then break out of this session
            let processingFrame = self.sharedController.mapNavigator.processingFrame
            let exitingMap = InvisibleMapController.shared.exitingMap
        #endif
        print("Exiting map: \(exitingMap)")
        // start processing frame if frame is not processing yet after 0.1 seconds
        if lastRecordedTimestamp + recordInterval <= frame.timestamp && !processingFrame && !exitingMap {
            let scene = SCNMatrix4(frame.camera.transform)
            if let cameraNode = self.cameraNode {
                cameraNode.transform = scene
            } else {
                // TODO: remove camera node when we have some waypoints to test with (we can use ARFrame.camera.transform instead
                cameraNode = SCNNode()
                cameraNode!.transform = scene
                cameraNode!.name = "camera"
                arView.scene.rootNode.addChildNode(cameraNode!)
            }
            lastRecordedTimestamp = frame.timestamp
            //print("Timestamp: \(frame.timestamp)")
            
            //if we are processing the frame and user triggers LeaveMapRequested event then, make processing frame
            sharedController.process(event: .NewARFrame(cameraFrame: frame))
        }
        //self.memoryChecker.printRemainingMemory()
        if(self.memoryChecker.getRemainingMemory() < 500) {
            self.resetRecordingSession()
        }
    }
    
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // let newAnchors = anchors.compactMap({$0 as? ARPlaneAnchor})
        // InvisibleMapCreatorController.shared.process(event: .PlanesUpdated(planes: newAnchors))
    }
    
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // let updatedAnchors = anchors.compactMap({$0 as? ARPlaneAnchor})
        // InvisibleMapCreatorController.shared.process(event: .PlanesUpdated(planes: updatedAnchors))
    }
    
    // Notes: Added for cloud & geospatial anchors
    public func session(_ session: ARSession, didFailWithError error: Error) {
            print("failure")
        }
        
    public func sendPathKeypoints(_ id: String, _ allKeypoints: [KeypointInfo], _ cameraPositions: [Any]) -> String? {
            
            var waypointCoords: [Any] = []
            
            for anchor in allKeypoints
            {
                waypointCoords.append([anchor.location.transform.columns.3[0], anchor.location.transform.columns.3[2]])
            }
            
            let dataDictionary: [String : Any] = ["ID": id, "GeoAnchors": waypointCoords, "CameraPositions": cameraPositions]
            
            do {
                let jsonData = try
                JSONSerialization.data(withJSONObject:dataDictionary, options:.prettyPrinted)
                let storageRef =
                storageBaseRef.child("NECO_TEST").child(id + ".json")
                let fileType = StorageMetadata()
                fileType.contentType = "application/json"
                storageRef.putData(jsonData, metadata: fileType) { (metadata, error) in
                    guard metadata != nil else {
                        // Uh-oh, an error occurred!
                        print("could not upload meta data to firebase", error!.localizedDescription)
                        return
                    }
                    print("Successfully uploaded log!", storageRef.fullPath)
                }
             
                // How to specify where these get uploaded (Create folder for data so it doesn't clog up central bucket)
                // How often can we upload this stuff/how big are these uploads? Don't want to overflow data limitations
                return storageRef.fullPath
            } catch {
                print(error.localizedDescription)
                return nil
            }
        }
        
        func sendPathData(_ id: String,_ allGeoAnchors: [ARGeoAnchor], _ cameraPositions: [Any])->String? {
                
            var anchorCoords: [Any] = []
            
            for anchor in allGeoAnchors
            {
                anchorCoords.append([anchor.transform.columns.3[0], anchor.transform.columns.3[2]])
            }
            
            let dataDictionary: [String : Any] = ["ID": id, "GeoAnchors": anchorCoords, "CameraPositions": cameraPositions]
            
            do {
                let jsonData = try
                JSONSerialization.data(withJSONObject:dataDictionary, options:.prettyPrinted)
                let storageRef =
                storageBaseRef.child("GeoAnchorTest").child(id + ".json")
                let fileType = StorageMetadata()
                fileType.contentType = "application/json"
                storageRef.putData(jsonData, metadata: fileType) { (metadata, error) in
                    guard metadata != nil else {
                        // Uh-oh, an error occurred!
                        print("could not upload meta data to firebase", error!.localizedDescription)
                        return
                    }
                    print("Successfully uploaded log!", storageRef.fullPath)
                }
             
                // How to specify where these get uploaded (Create folder for data so it doesn't clog up central bucket)
                // How often can we upload this stuff/how big are these uploads? Don't want to overflow data limitations
                return storageRef.fullPath
            } catch {
                print(error.localizedDescription)
                return nil
            }
        }
        
        private func getBestAlignmentCrumb(cameraGeoSpatialTransform: GARGeospatialTransform, cameraWorldTransform: simd_float4x4, anchors: [GARAnchor])->(GARAnchor, LocationInfoGeoSpatial)? {
            let accurateGeoSpatialCrumbs = geoSpatialAlignmentCrumbs.filter( {$0.headingUncertainty < GARGeospatialTransform.excellentQualityHeadingAccuracy && $0.altitudeUncertainty < GARGeospatialTransform.excellentQualityAltitudeAccuracy && $0.horizontalUncertainty < GARGeospatialTransform.excellentQualityHorizontalAccuracy } )
            
            var accurateGeoSpatialCrumbMap: [UUID: LocationInfoGeoSpatial] = [:]
            for geoCrumb in accurateGeoSpatialCrumbs {
                if let GARAnchorUUID = geoCrumb.GARAnchorUUID {
                    accurateGeoSpatialCrumbMap[GARAnchorUUID] = geoCrumb
                }
            }
            let currentAccurateGeoAnchors = anchors.filter({ accurateGeoSpatialCrumbMap[$0.identifier] != nil && $0.hasValidTransform })
            let worldPos = cameraWorldTransform.columns.3
            guard let bestGeospatialRecordingAnchor = currentAccurateGeoAnchors.min(by: { simd_distance($0.transform.columns.3, worldPos) < simd_distance($1.transform.columns.3, worldPos) }) else {
                return nil
            }
            return (bestGeospatialRecordingAnchor, accurateGeoSpatialCrumbMap[bestGeospatialRecordingAnchor.identifier]!)
        }
        
        func checkForGeoAlignment(geospatialTransform: GARGeospatialTransform, cameraWorldTransform: simd_float4x4) {
            guard geospatialTransform.trackingQuality.isAsGoodOrBetterThan( outdoorLocalizationQualityThreshold), let GARAnchors = self.currentGARFrame?.anchors else {
                return
            }
            guard let (alignmentAnchor, geoSpatialAlignmentCrumb) = getBestAlignmentCrumb(cameraGeoSpatialTransform: geospatialTransform, cameraWorldTransform: cameraWorldTransform, anchors: GARAnchors) else {
                return
            }
            
            if let manualAlignment = geoSpatialAlignmentFilter.update(anchorTransform: alignmentAnchor.transform, geoSpatialAlignmentCrumb: geoSpatialAlignmentCrumb, cameraGeospatialTransform: geospatialTransform, filterGeoSpatial: filterGeoSpatial) {
                self.manualAlignment = manualAlignment
                print("self.manualAlignment \(self.manualAlignment)")
                delegate?.didDoGeoAlignment()
            }
        }
        
        private func checkForCloudAnchorAlignment(anchors: [GARAnchor]) {
            for anchor in anchors {
                if anchor.hasValidTransform, let correspondingARAnchor = sessionCloudAnchors[anchor.identifier], anchor.cloudIdentifier == lastResolvedCloudAnchorID  {
                    manualAlignment = anchor.transform.alignY() * correspondingARAnchor.transform.inverse.alignY()
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            do {
                ARFrameStatusAdapter.adjustTrackingStatus(frame)
                let garFrame = try garSession?.update(frame)
                for gAnchor in garFrame?.updatedAnchors ?? [] {
                    delegate?.didUpdate(garAnchor: gAnchor)
                }
                self.currentGARFrame = garFrame
                // shift positions of cloud anchor nodes
                cloudNodeUpdater.async {
                    if !self.visualizeCloudAnchors {
                        return
                    }
                    for gAnchor in garFrame?.updatedAnchors ?? [] {
                        if let cloudIdentifier = gAnchor.cloudIdentifier, gAnchor.hasValidTransform, let existingNode = self.cloudAnchorSCNNodes[cloudIdentifier] {
                            existingNode.simdTransform = gAnchor.transform
                        }
                    }
                }
                // don't use Cloud Anchors if we have localized with the ARWorldMap
                if localization != .withARWorldMap, let gAnchors = currentGARFrame?.anchors {
                    checkForCloudAnchorAlignment(anchors: gAnchors)
                }
                
                if let geospatialTransform = self.currentGARFrame?.earth?.cameraGeospatialTransform {
                    if -lastGeospatialLogTime.timeIntervalSinceNow > 0.3 {
                        lastGeospatialLogTime = Date()
                        PathLogger.shared.logGeospatialTransform(geospatialTransform)
                    }
                    self.worldTransformGeoSpatialPair = (frame.camera.transform, geospatialTransform)
                    delegate?.didReceiveFrameWithTrackingQuality(geospatialTransform.trackingQuality)
                    if localization == .none {
                        checkForGeoAlignment(geospatialTransform: geospatialTransform, cameraWorldTransform: frame.camera.transform)
                    }
                }
            } catch {
                print("couldn't update GAR Frame")
            }
            // TODO: test for alignment based on geospatial transform
            ARData.shared.set(transform: frame.camera.transform)
            if let keypointRenderJob = keypointRenderJob {
                keypointRenderJob()
                self.keypointRenderJob = nil
            }
            if let pathRenderJob = pathRenderJob {
                pathRenderJob()
                self.pathRenderJob = nil
            }
            for intermediateAnchorRenderJob in intermediateAnchorRenderJobs {
                if let renderJob = intermediateAnchorRenderJob.1 {
                    renderJob()
                    intermediateAnchorRenderJobs[intermediateAnchorRenderJob.0] = nil
                }
            }
            
            let imageAnchors = frame.anchors.compactMap({$0 as? ARImageAnchor})
            if !imageAnchors.isEmpty {
                delegate?.receivedImageAnchors(imageAnchors: imageAnchors)
            }
        }
        
        /// Called when there is a change in tracking state.  This is important for both announcing tracking errors to the user and also to triggering some app state transitions.
        /// - Parameters:
        ///   - session: the AR session associated with the change in tracking state
        ///   - camera: the AR camera associated with the change in tracking state
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            var logString: String? = nil

            switch camera.trackingState {
            case .limited(let reason):
                switch reason {
                case .excessiveMotion:
                    logString = "ExcessiveMotion"
                    delegate?.trackingErrorOccurred(.excessiveMotion)
                case .insufficientFeatures:
                    logString = "InsufficientFeatures"
                    delegate?.trackingErrorOccurred(.insufficientFeatures)
                case .initializing:
                    // don't log anything
                    print("initializing")
                case .relocalizing:
                    sessionWasRelocalizing = true
                    delegate?.sessionInitialized()
                    delegate?.sessionRelocalizing()
                @unknown default:
                    print("An error condition arose that we didn't know about when the app was last compiled")
                }
            case .normal:
                logString = "Normal"
                delegate?.sessionInitialized()
                delegate?.trackingIsNormal()
                if sessionWasRelocalizing {
                    if localization == .none {
                        delegate?.sessionDidRelocalize()
                    }
                    localization = .withARWorldMap
                    manualAlignment = matrix_identity_float4x4
                    legacyHandleRelocalization()
                }
                print("normal")
            case .notAvailable:
                logString = "NotAvailable"
                print("notAvailable")
            }
            if let logString = logString, let recordingPhase = delegate?.isRecording() {
                PathLogger.shared.logTrackingError(isRecordingPhase: recordingPhase, trackingError: logString)
            }
        }
        
        func legacyHandleRelocalization() {
            removeNavigationNodes()
            guard let defaultColor = delegate?.getKeypointColor(), let defaultPathColor = delegate?.getPathColor(), let showPath = delegate?.getShowPath() else {
                return
            }
            if let nextKeypoint = RouteManager.shared.nextKeypoint, let cameraTransform = ARSessionManager.shared.currentFrame?.camera.transform {
                let previousKeypointLocation = RouteManager.shared.getPreviousKeypoint(to: nextKeypoint)?.location ?? LocationInfo(transform: cameraTransform)
                renderKeypoint(nextKeypoint.location, defaultColor: defaultColor)
                if showPath {
                    renderPath(nextKeypoint.location, previousKeypointLocation, defaultPathColor: defaultPathColor)
                }
            }
            for intermediateAnchorPoint in RouteManager.shared.intermediateAnchorPoints {
                ARSessionManager.shared.render(intermediateAnchorPoints: [intermediateAnchorPoint])
            }
        }
        
        private func createSCNNodeFor(identifier: String, at: simd_float4x4) {
            if !visualizeCloudAnchors{
                return
            }
            cloudNodeUpdater.async {
                let newNode = SCNNode(geometry: SCNBox(width: 0.25, height: 0.25, length: 0.25, chamferRadius: 0.1))
                
                newNode.simdTransform = at
                newNode.geometry?.firstMaterial!.diffuse.contents = UIColor.green
                self.cloudAnchorSCNNodes[identifier] = newNode
                self.sceneView.scene.rootNode.addChildNode(newNode)
            }
        }
        
    }
}

extension ARView: ARViewController {
    
    /// Transforms the AprilTag position into world frame
    var supportsLidar: Bool {
        get {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
    }
    
    // initialize ArView
    func initialize() {
        self.startSession()
        self.createMapNode()
    }
    
    /// Stops ping sound that plays during navigation
        func stopPing() {
            self.pingTimer.invalidate()
            self.pingTimer = Timer()
        }
    
    
    /// Reset ARSession after a map recording has been exited
    func resetRecordingSession() {
        arView.session.pause()
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
    }
    
    /// Resets ArView and pings when user leaves map navigating view
    func resetNavigatingSession() {
        pathNodes = [:]
        self.stopPing()
        arView.session.pause()
    }
    
    /// Adds or updates a tag node when a tag is detected
    func detectTag(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) {
        DispatchQueue.main.async {
            #if !IS_MAP_CREATOR
            guard let map = InvisibleMapController.shared.mapNavigator.map else {
                return
            }
            #endif
            let pose = tag.poseData

            let originalTagPose = simd_float4x4(pose)
            
            let transVar = simd_float3(Float(tag.transVecVar.0), Float(tag.transVecVar.1), Float(tag.transVecVar.2))
            let quatVar = simd_float4(x: Float(tag.quatVar.0), y: Float(tag.quatVar.1), z: Float(tag.quatVar.2), w: Float(tag.quatVar.3))
            
            let scenePose = detectionFrameToGlobal(tagPose: originalTagPose, cameraTransform: cameraTransform, snapTagsToVertical: snapTagsToVertical)
            let transVarMatrix = simd_float3x3(diagonal: transVar)
            let quatVarMatrix = simd_float4x4(diagonal: quatVar)

            // this is the linear transform that takes the original tag pose to the final world pose
            let linearTransform = scenePose*originalTagPose.inverse
            let q = simd_quatf(linearTransform)

            let quatMultiplyAsLinearTransform =
            simd_float4x4(columns: (simd_float4(q.vector.w, q.vector.z, -q.vector.y, -q.vector.x),
                                    simd_float4(-q.vector.z, q.vector.w, q.vector.x, -q.vector.y),
                                    simd_float4(q.vector.y, -q.vector.x, q.vector.w, -q.vector.z),
                                    simd_float4(q.vector.x, q.vector.y, q.vector.z, q.vector.w)))
            let sceneTransVar = linearTransform.getUpper3x3()*transVarMatrix*linearTransform.getUpper3x3().transpose
            let sceneQuatVar = quatMultiplyAsLinearTransform*quatVarMatrix*quatMultiplyAsLinearTransform.transpose
            let scenePoseQuat = simd_quatf(scenePose)
            let scenePoseTranslation = scenePose.getTrans()
                        
            let doKalman = false
            
            #if !IS_MAP_CREATOR
            let aprilTagTracker = map.aprilTagDetectionDictionary[Int(tag.number), default: AprilTagTracker(self.arView, tagId: Int(tag.number))]
                map.aprilTagDetectionDictionary[Int(tag.number)] = aprilTagTracker
            
            #else
            let aprilTagTracker = InvisibleMapCreatorController.shared.mapRecorder.aprilTagDetectionDictionary[Int(tag.number), default: AprilTagTracker(self.arView, tagId: Int(tag.number))]
            InvisibleMapCreatorController.shared.mapRecorder.aprilTagDetectionDictionary[Int(tag.number)] = aprilTagTracker
            #endif
            
            // TODO: need some sort of logic to discard old detections.  One method that seems good would be to add some process noise (Q_k non-zero)
            aprilTagTracker.updateTagPoseMeans(id: Int(tag.number), detectedPosition: scenePoseTranslation, detectedPositionVar: sceneTransVar, detectedQuat: scenePoseQuat, detectedQuatVar: sceneQuatVar, doKalman: doKalman)

            let tagNode: SCNNode
            if let existingTagNode = self.detectionNode?.childNode(withName: "Tag_\(String(tag.number))", recursively: false)  {
                tagNode = existingTagNode
                tagNode.simdPosition = aprilTagTracker.tagPosition
                tagNode.simdOrientation = aprilTagTracker.tagOrientation
            } else {
                tagNode = SCNNode()
                tagNode.simdPosition = aprilTagTracker.tagPosition
                tagNode.simdOrientation = aprilTagTracker.tagOrientation
                tagNode.geometry = SCNBox(width: 0.19, height: 0.19, length: 0.05, chamferRadius: 0)
                tagNode.name = "Tag_\(String(tag.number))"
                tagNode.geometry?.firstMaterial?.diffuse.contents = UIColor.cyan
                self.detectionNode?.addChildNode(tagNode)
            }
            
            /// Adds axes to the tag to aid in the visualization
            let xAxis = SCNNode(geometry: SCNBox(width: 1.0, height: 0.05, length: 0.05, chamferRadius: 0))
            xAxis.position = SCNVector3.init(0.75, 0, 0)
            xAxis.geometry?.firstMaterial?.diffuse.contents = UIColor.red
            let yAxis = SCNNode(geometry: SCNBox(width: 0.05, height: 1.0, length: 0.05, chamferRadius: 0))
            yAxis.position = SCNVector3.init(0, 0.75, 0)
            yAxis.geometry?.firstMaterial?.diffuse.contents = UIColor.green
            let zAxis = SCNNode(geometry: SCNBox(width: 0.05, height: 0.05, length: 1.0, chamferRadius: 0))
            zAxis.position = SCNVector3.init(0, 0, 0.75)
            zAxis.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
            tagNode.addChildNode(xAxis)
            tagNode.addChildNode(yAxis)
            tagNode.addChildNode(zAxis)
            
        //    print("April tag number: ", tag.number)
        }
    }

    
    /// Raycasts from camera to tag and places tag on the nearest mesh if the device supports LiDAR
    func raycastTag(tag: AprilTags, cameraTransform: simd_float4x4, snapTagsToVertical: Bool) -> simd_float4x4? {
        let pose = tag.poseData

        let originalTagPose = simd_float4x4(pose)
        
        let scenePose = detectionFrameToGlobal(tagPose: originalTagPose, cameraTransform: cameraTransform, snapTagsToVertical: snapTagsToVertical)
        
        let tagPos = simd_float3(scenePose.columns.3.x, scenePose.columns.3.y, scenePose.columns.3.z)
        let cameraPos = simd_float3(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        
        let raycastQuery = ARRaycastQuery(origin: cameraPos, direction: tagPos - cameraPos, allowing: .existingPlaneGeometry, alignment: .any)
        let raycastResult = self.arView.session.raycast(raycastQuery)
        
        if raycastResult.count == 0 {
            return nil
        } else {
            let meshTransform = raycastResult[0].worldTransform
            let raycastTagTransform: simd_float4x4 = simd_float4x4(diagonal:simd_float4(1, -1, -1, 1)) * cameraTransform.inverse * meshTransform
            
            return raycastTagTransform
        }
    }
    
    /// Creates location node when a location is added
    func pinLocation(locationName: String) {
        DispatchQueue.main.async {
            // Generate UUID here and pass it in with the recordLocation data
            let box = SCNBox(width: 0.05, height: 0.2, length: 0.05, chamferRadius: 0)
            
            let text = SCNText(string: locationName, extrusionDepth: 0)
            
            let cameraNode = self.arView.pointOfView
            let boxNode = SCNNode()
            let textNode = SCNNode()
            boxNode.geometry = box
            boxNode.name = locationName
            textNode.geometry = text
            textNode.name = locationName + "Text"
            let boxPosition = SCNVector3(0,0,0)
            textNode.position = SCNVector3(0,0.1,0)
            
            self.updatePositionAndOrientationOf(boxNode, withPosition: boxPosition, relativeTo: cameraNode!)
            
            textNode.scale = SCNVector3(0.005,0.005,0.005)
            
            self.mapNode?.childNode(withName: self.locationNodeName, recursively: false)!.addChildNode(boxNode)
            boxNode.addChildNode(textNode)
            
            let snapshot = self.arView.snapshot()
            #if IS_MAP_CREATOR
            self.sharedController.cacheLocationRequested(node: boxNode, picture: snapshot, textNode: textNode)
            #endif
        }
    }
    
    /// Move node position relative to another node's position.
    func updatePositionAndOrientationOf(_ node: SCNNode, withPosition position: SCNVector3, relativeTo referenceNode: SCNNode) {
        let referenceNodeTransform = matrix_float4x4(referenceNode.transform)
        
        var translationMatrix = matrix_identity_float4x4
        translationMatrix.columns.3.x = position.x
        translationMatrix.columns.3.y = position.y
        translationMatrix.columns.3.z = position.z
        
        let updatedTransform = matrix_multiply(referenceNodeTransform, translationMatrix)
        node.transform = SCNMatrix4(updatedTransform)
    }
    
    /// Initializes the map node, of which all of the tags and waypoints downloaded from firebase are children
    func createMapNode() {
        mapNode = SCNNode()
        mapNode?.position = SCNVector3(x: 0, y: 0, z: 0)
        arView?.scene.rootNode.addChildNode(mapNode!)
        for nodeName in [locationNodeName, tagNodeName, crumbNodeName, edgeNodeName] {
            let node = SCNNode()
            node.name = nodeName
            node.position = SCNVector3(x: 0, y: 0, z: 0)
            mapNode?.addChildNode(node)
        }
        self.createDetectionNode()
    }
    
    /// Initializes the detection node, which all tag detections are children of
    func createDetectionNode() {
        detectionNode = SCNNode()
        detectionNode?.position = SCNVector3(x: 0, y: 0, z: 0)
        arView?.scene.rootNode.addChildNode(detectionNode!)
    }
    
    func removeNavigationNodes() {
        keypointNode?.removeFromParentNode()
        keypointNode = nil
        pathObj?.removeFromParentNode()
        pathObj = nil
        for anchorPointNode in anchorPointNodes {
            anchorPointNode.1.removeFromParentNode()
        }
        anchorPointNodes = [:]
    }
    
    /// Initialize the ARSession
    func startSession() {
        manualAlignment = matrix_identity_float4x4
        keypointRenderJob = nil
        pathRenderJob = nil
        intermediateAnchorRenderJobs = [:]
        worldTransformGeoSpatialPair = nil
        sessionWasRelocalizing = false
        localization = .none
        removeNavigationNodes()
        cloudNodeUpdater.async {
            for (_, scnNode) in self.cloudAnchorSCNNodes {
                scnNode.removeFromParentNode()
            }
            self.cloudAnchorSCNNodes = [:]
        }
        geoSpatialAlignmentFilter.reset()
        
        configuration.planeDetection = [.horizontal, .vertical]
        pathNodes = [:]
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        startGARSession()
    }
    
    /// start the AR session for Cloud anchors
    private func startGARSession() {
        do {
            garSession = try GARSession(apiKey: garAPIKey, bundleIdentifier: nil)
            var error: NSError?
            let GARconfiguration = GARSessionConfiguration()
            GARconfiguration.cloudAnchorMode = .enabled
            GARSession?.setConfiguration(GARconfiguration, error: &error)
            GARSession?.delegate = self
            print("gar set configuration error \(error)")
        } catch {
            print("failed to create GARSession")
        }
    }
    
    // Setup audio elements
    func setupPing() {
        do {
            try self.audioPlayers["startNav"] = AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/System/Library/Audio/UISounds/tweet_sent.caf"))
            try self.audioPlayers["arrived"] = AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/System/Library/Audio/UISounds/New/Fanfare.caf"))
            try self.audioPlayers["ping"] = AVAudioPlayer(contentsOf: URL(fileURLWithPath: "/System/Library/Audio/UISounds/Tock.caf"))
            self.hapticGenerator = UIImpactFeedbackGenerator(style: .light)
            self.hapticGenerator!.prepare()
            for p in self.audioPlayers.values {
                p!.prepareToPlay()
            }
            self.scheduledPingTimer()
        }
        catch let audioError {
          print("Could not setup audio: \(audioError)")
        }
    }

    /// Creates a node for a path edge between two vertices
    func renderEdge(from firstVertex: RawMap.OdomVertex, to secondVertex: RawMap.OdomVertex, isPath: Bool) {
            let pathObj: SCNNode
        let verticalOffset: Float = -0.6
        
        let x = (secondVertex.translation.x + firstVertex.translation.x) / 2
        let y = (secondVertex.translation.y + firstVertex.translation.y) / 2
        let z = (secondVertex.translation.z + firstVertex.translation.z) / 2
        let xDist = secondVertex.translation.x - firstVertex.translation.x
        let yDist = secondVertex.translation.y - firstVertex.translation.y
        let zDist = secondVertex.translation.z - firstVertex.translation.z
        let dist = sqrt(pow(xDist, 2) + pow(yDist, 2) + pow(zDist, 2))
        
        let shouldAddToMapNode: Bool
        if let (cachedPathObj, _) = pathNodes["\(firstVertex.poseId)_\(secondVertex.poseId)"] {
            pathObj = cachedPathObj
            shouldAddToMapNode = false
        } else {
            /// SCNNode of the bar path
            pathObj = SCNNode(geometry: SCNBox(width: CGFloat(dist), height: 0.06, length: 0.06, chamferRadius: 1))
                        shouldAddToMapNode = true
        }
        pathNodes["\(firstVertex.poseId)_\(secondVertex.poseId)"] = (pathObj, true)

        //configure node attributes
        if !isPath {
            let odometryNode = SCNNode(geometry: SCNBox(width: 0.05, height: 0.05, length: 0.05, chamferRadius: 0))
            odometryNode.geometry?.firstMaterial?.diffuse.contents = UIColor.blue
            odometryNode.simdPosition = simd_float3(firstVertex.translation.x, firstVertex.translation.y + verticalOffset, firstVertex.translation.z)
            mapNode?.childNode(withName: crumbNodeName, recursively: false)!.addChildNode(odometryNode)
            
            pathObj.geometry?.firstMaterial!.diffuse.contents = UIColor.yellow
            pathObj.opacity = CGFloat(1)
        } else {
            pathObj.geometry?.firstMaterial!.diffuse.contents = UIColor.red
            pathObj.opacity = CGFloat(1)
        }
        
        let xAxis = simd_normalize(simd_float3(xDist, yDist, zDist))
        let yAxis: simd_float3
        if xDist == 0 && zDist == 0 {
            // this is the case where the path goes straight up and we can set yAxis more or less arbitrarily
            yAxis = simd_float3(1, 0, 0)
        } else if xDist == 0 {
            // zDist must be non-zero, which means that for yAxis to be perpendicular to the xAxis and have a zero y-component, we must make yAxis equal to simd_float3(1, 0, 0)
            yAxis = simd_float3(1, 0, 0)
        } else if zDist == 0 {
            // xDist must be non-zero, which means that for yAxis to be perpendicular to the xAxis and have a zero y-component, we must make yAxis equal to simd_float3(0, 0, 1)
            yAxis = simd_float3(0, 0, 1)
        } else {
            // TODO: real math
            let yAxisZComponent = sqrt(1 / (zDist*zDist/(xDist*xDist) + 1))
            let yAxisXComponent = -zDist*yAxisZComponent/xDist
            yAxis = simd_float3(yAxisXComponent, 0, yAxisZComponent)
        }
        let zAxis = simd_cross(xAxis, yAxis)
        let pathTransform = simd_float4x4(columns: (simd_float4(xAxis, 0), simd_float4(yAxis, 0), simd_float4(zAxis, 0), simd_float4(x, y + verticalOffset, z, 1)))

        pathObj.simdTransform = pathTransform
        
        if isPath, shouldAddToMapNode {
            mapNode?.childNode(withName: edgeNodeName, recursively: false)!.addChildNode(pathObj)
        }
    }
    
    func renderEdges(fromList vertices: [RawMap.OdomVertex], isPath: Bool) {
        for key in pathNodes.keys {
            // keeps track of seen nodes
            pathNodes[key] = (pathNodes[key]!.0, false)
        }
        // hides or shows nodes
        for i in 0...vertices.count-2 {
          self.renderEdge(from: vertices[i], to: vertices[i + 1], isPath: isPath)
        }
        for key in pathNodes.keys {
          let pathObj = pathNodes[key]!.0
          let shouldRender = pathNodes[key]!.1
          pathObj.isHidden = !shouldRender
        }
        if isPath {
            /// Ping audio from a few nodes down to ensure direction
           // print("vertices.count \(vertices.count)")
            // compare the camera's current position to the destination's position, and if they are close enough, tell users they reached destination
            if let cameraNode = cameraNode, let rootNode = arView?.scene.rootNode, let cameraPosConverted = convertNodeOrigintoMapFrame(node: cameraNode), let endpointVertex = vertices.last {
                
                self.endpointX = endpointVertex.translation.x
                self.endpointY = endpointVertex.translation.y
                self.endpointZ = endpointVertex.translation.z
                
                self.currentCameraPosX = cameraPosConverted.x
                self.currentCameraPosY = cameraPosConverted.y
                self.currentCameraPosX = cameraPosConverted.z
                
                #if !IS_MAP_CREATOR
                if simd_distance(simd_float3(cameraPosConverted), simd_float3(endpointVertex.translation.x, endpointVertex.translation.y, endpointVertex.translation.z)) < self.sharedController.mapNavigator.endpointSphere {
                    InvisibleMapController.shared.process(event: .EndpointReached(finalEndpoint: true))
                    NavigateGlobalStateSingleton.shared.endPointReached = true
                    print("Reached endpoint")
                } else {
                    // TODO: revisit this to see how to better set the source location
                    let audioSource = vertices[min(2, vertices.count-1)]  // the point in the map's path in front of current phone position
                    
                    self.audioSourceX = audioSource.translation.x
                    self.audioSourceZ = audioSource.translation.z
            
                    // vector from audioSource to current camera location
                    let directionToSource = vector2(cameraPosConverted.x, cameraPosConverted.z) - vector2(audioSource.translation.x, audioSource.translation.z)
                    // vector in phone axis
                    let phoneAxisInGlobalFrame = SCNVector3(x: cameraNode.transform.m31, y: cameraNode.transform.m32, z: cameraNode.transform.m33)
                    let phoneAxisInMapFrame = rootNode.convertVector(phoneAxisInGlobalFrame, to: mapNode)
                    var volumeScale = simd_dot(simd_normalize(directionToSource), simd_normalize(vector2(phoneAxisInMapFrame.x, phoneAxisInMapFrame.z)))
                    
                    // var for debugging purposes
                    self.cosValue = volumeScale
                    
                 //   if InvisibleMapController.shared.countFrame >= 5 {
                        // angle between the two vectors that's used to determine how off current phone orientation is in relative to the map's path in mapFrame
                        if volumeScale < 0 {
                            // left side of unit circle -> right directions
                            self.angleDifference = -1 * acos(volumeScale)
                        }
                        else {
                            // right side of unit circle -> left directions
                            self.angleDifference = acos(volumeScale)
                        }
                 //   }
                    
                    volumeScale = acos(volumeScale) / Float.pi
                    print("volume: \(volumeScale)") // increases off track; decreases at right track -> subtracts it from 1 to have greater volumeScale when on right track
                    volumeScale = 1 - volumeScale
                    volumeScale = pow(volumeScale, 3)
                    self.audioPlayers["ping"]??.setVolume(volumeScale, fadeDuration: 0)
                //    print("Volume scale: \(volumeScale)")
                }
                #endif
            }
        }
    }
    
    
    /// Renders entire path for debugging
    func renderDebugGraph(){
        #if !IS_MAP_CREATOR
        guard let map = self.sharedController.mapNavigator.map else {
            return
        }
            for vertex in map.rawData.odometryVertices {
                for neighbor in vertex.neighbors {
                    // Only render path if it hasn't been rendered yet
                    if (neighbor < vertex.poseId){
                        let neighborVertex = map.odometryDict![neighbor]!
                        
                        // Render edge
                        self.renderEdge(from: vertex, to: neighborVertex, isPath: false)
                    }
                }
            }
        #endif
    }
    
    func renderTags() {
        #if !IS_MAP_CREATOR
        guard let map = sharedController.mapNavigator.map else {
            return
        }
        for tagId in map.tagDictionary.keys {
            let tag = map.tagDictionary[tagId]!
            let tagNode = SCNNode()
            tagNode.geometry = SCNBox(width: 0.19, height: 0.19, length: 0.05, chamferRadius: 0)
            tagNode.geometry?.firstMaterial?.diffuse.contents = UIColor.black
            tagNode.name = "Tag_\(tagId)"
            tagNode.transform = SCNMatrix4(simd_float4x4(tag))
            self.mapNode?.childNode(withName: self.tagNodeName, recursively: false)?.addChildNode(tagNode)
        }
        #endif
    }
    
    func renderGraph(fromStops stops: [RawMap.OdomVertex]) {
        self.renderEdges(fromList: stops, isPath: true)
        self.renderTags()
    }
    
    /// Checks the distance to all of the waypoints and announces those that are closer than a given threshold distance
    func announceNearbyWaypoints() {
        guard let cameraNode = cameraNode, let mapNode = mapNode else {
            return
        }
        if let curr_pose = convertNodeOrigintoMapFrame(node: cameraNode) {
            var potentialAnnouncements : [String:(String, Double)] = [:]
            for waypointNode in mapNode.childNode(withName: locationNodeName, recursively: false)!.childNodes {
                let nodeName = waypointNode.name!
                let waypointName = String(nodeName[nodeName.index(nodeName.firstIndex(of: "_")!, offsetBy: 1)...])
                let waypoint_pose = arView.scene.rootNode.convertPosition(waypointNode.position, from: mapNode)
                let distanceToCurrPose = sqrt(pow((waypoint_pose.x - curr_pose.x),2) + pow((waypoint_pose.y - curr_pose.y),2) + pow((waypoint_pose.z - curr_pose.z),2))
                if distanceToCurrPose < self.distanceToAnnounceWaypoint, (lastSpeechTime[waypointName] ?? Date.distantPast).timeIntervalSinceNow < -5.0, !synth.isSpeaking {
                    let twoDimensionalDistanceToCurrPose = sqrt(pow((waypoint_pose.x - curr_pose.x),2) + pow((waypoint_pose.y - curr_pose.y),2))
                    let announcement: String = waypointName + " is " + String(format: "%.1f", twoDimensionalDistanceToCurrPose) + " meters away."
                    potentialAnnouncements[waypointName] = (announcement, (lastSpeechTime[waypointName] ?? Date.distantPast).timeIntervalSinceNow)
                }
                // If multiple announcements are possible, pick the one that was least recently spoken
                let leastRecentlyAnnounced = potentialAnnouncements.min { a, b in a.value.1 < b.value.1 }
                if let leastRecentlyAnnounced = leastRecentlyAnnounced {
                    let utterance = AVSpeechUtterance(string: leastRecentlyAnnounced.value.0)
                    utterance.voice = voice
                    lastSpeechTime[leastRecentlyAnnounced.key] = Date()
                    synth.speak(utterance)
                }
            
            }
        }
        
    }
    
    func scheduledPingTimer() {
         self.pingTimer.invalidate()
         self.pingTimer = Timer()
         self.pingTimer = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(self.ping), userInfo: nil, repeats: true)
     }
    
    @objc func arrivedSound() {
        self.playSound(type: "arrived")
    }
     
     @objc func ping() {
         #if IS_MAP_CREATOR
         //don't play ping sound
            return
         #else
         if self.sharedController.mapNavigator.map?.firstTagFound != true {
                 //don't play ping sound if first tag isn't detected
                 return
             }
         
        #endif
         self.playSound(type: "ping")
         let volume = self.audioPlayers["ping"]!!.volume
         // Audio volume was set to a cubic scale, revert back to linear
         let hapticScale = pow(volume, 1.0 / 3.0)
         if hapticScale > 0.75 {
             self.hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
         } else if hapticScale > 0.5 {
             self.hapticGenerator = UIImpactFeedbackGenerator(style: .medium)
         } else if hapticScale > 0.25 {
             self.hapticGenerator = UIImpactFeedbackGenerator(style: .light)
         } else {
             self.hapticGenerator = nil
         }
         self.hapticGenerator?.impactOccurred()
     }
    
     @objc func playSound(type: String) {
         do {
             try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback)
             try AVAudioSession.sharedInstance().setActive(true)
             guard let player = self.audioPlayers[type]! else {
                 return
             }
             player.play()
         } catch let error {
             print(error.localizedDescription)
         }
     }
   
    func updateMapPose(to mapToGlobal: simd_float4x4) {
        self.mapNode?.simdTransform = mapToGlobal
    }
    
    func convertNodeOrigintoMapFrame(node: SCNNode) -> SCNVector3? {
        if let mapNode = mapNode {
            let cameraPos = node.convertPosition(SCNVector3(), to: mapNode)
            return cameraPos
        } else {
            return nil
        }
    }


    private func createSCNNodeFor(identifier: String, at: simd_float4x4) {
        if !visualizeCloudAnchors{
            return
        }
        cloudNodeUpdater.async {
            let newNode = SCNNode(geometry: SCNBox(width: 0.25, height: 0.25, length: 0.25, chamferRadius: 0.1))
            
            newNode.simdTransform = at
            newNode.geometry?.firstMaterial!.diffuse.contents = UIColor.green
            self.cloudAnchorSCNNodes[identifier] = newNode
            self.sceneView.scene.rootNode.addChildNode(newNode)
        }
    }
}

extension ARView: GARSessionDelegate {
    func session(_ session: GARSession, didResolve anchor:GARAnchor) {
        if localization == .withARWorldMap {
            // defer to the ARWorldMap
            return
        }
        if localization == .none {
            delegate?.sessionDidRelocalize()
        }
        localization = .withCloudAnchors
        if let cloudIdentifier = anchor.cloudIdentifier, anchor.hasValidTransform, let alignTransform = cloudAnchorsForAlignment[NSString(string: cloudIdentifier)]?.transform {
            lastResolvedCloudAnchorID = cloudIdentifier
            self.manualAlignment = anchor.transform.alignY() * alignTransform.inverse.alignY() // Ask: what is this? Do we need a Float4x4Extension
            createSCNNodeFor(identifier: cloudIdentifier, at: anchor.transform)
            let announceResolution = "Cloud Anchor Resolved"
           // PathLogger.shared.logSpeech(utterance: announceResolution)
           // AnnouncementManager.shared.announce(announcement: announceResolution)
        }
    }
    
    func session(_ session: GARSession, didHost garAnchor:GARAnchor) {
        if let cloudIdentifier = garAnchor.cloudIdentifier {
            // Note: lets delegate know that change has been made (passes along the info it got)
            
            if (Clew2AppController.shared.cloudAnchorType == "POI") {
                Clew2AppController.shared.process(event: .DropCloudAnchorRequested(cloudIdentifier: cloudIdentifier, withTransform: garAnchor.transform))
            } else if (Clew2AppController.shared.cloudAnchorType == "door") {
                Clew2AppController.shared.process(event: .DropDoorAnchorRequested(cloudIdentifier: cloudIdentifier, withTransform: garAnchor.transform))
            } else if (Clew2AppController.shared.cloudAnchorType == "stair") {
                Clew2AppController.shared.process(event: .DropStairAnchorRequested(cloudIdentifier: cloudIdentifier, withTransform: garAnchor.transform))
            }
            // ask: why do we need this node
            createSCNNodeFor(identifier: cloudIdentifier, at: garAnchor.transform)
        }
    }
    
    func session(_ session: GARSession, didFailToResolve didFailToResolveAnchor: GARAnchor) {
        print("FAILURE")
    }
}
