//
//  FirebaseManager.swift
//  InvisibleMap
//
//  Created by Allison Li and Ben Morris on 10/19/21.
//  Copyright © 2021 Occam Lab. All rights reserved.
//

import Foundation
import Firebase
import FirebaseDatabase
import FirebaseStorage

class FirebaseManager {
    
    static var storageRef: StorageReference = Storage.storage().reference()
    
    /// Downloads the selected map from firebase
    static func createMap(from mapFileName: String) -> Map {
        let mapRef = storageRef.child(mapFileName)
        var map: Map?
        mapRef.getData(maxSize: 10 * 1024 * 1024) { mapData, error in
            if let error = error {
                print(error.localizedDescription)
                // Error occurred
            } else {
                if mapData != nil {
                    map = Map(from: mapData!)!
                }
            }
        }
        return map!
    }
    
    static func createMapDatabase() -> MapDatabase {
        var userMapsPath = "maps/"
        if Auth.auth().currentUser != nil {
            userMapsPath = userMapsPath + String(Auth.auth().currentUser!.uid)
        }
        let mapsRef = Database.database(url: "https://invisible-map-sandbox.firebaseio.com/").reference(withPath: userMapsPath)
        return MapDatabase(from: storageRef, with: mapsRef)
    }
}

class MapDatabase: ObservableObject {
    @Published var maps: [String] = []
    @Published var images: [UIImage] = []
    @Published var files: [String] = []
    var mapsRef: DatabaseReference
    var storageRef: StorageReference
    
    init(from storageRef: StorageReference, with mapsRef: DatabaseReference) {
        self.mapsRef = mapsRef
        self.storageRef = storageRef
        
        // Tracks any addition, change, or removal to the map database
        self.mapsRef.observe(.childAdded) { (snapshot) -> Void in
            self.processMap(key: snapshot.key, values: snapshot.value as! [String: Any])
        }
        self.mapsRef.observe(.childChanged) { (snapshot) -> Void in
            self.processMap(key: snapshot.key, values: snapshot.value as! [String: Any])
        }
        self.mapsRef.observe(.childRemoved) { (snapshot) -> Void in
            if let existingMapIndex = self.maps.firstIndex(of: snapshot.key) {
                self.maps.remove(at: existingMapIndex)
                self.images.remove(at: existingMapIndex)
                self.files.remove(at: existingMapIndex)
            }
        }
    }
    
    func processMap(key: String, values: [String: Any]) {
        // Only include in the list if it is processed
        if let processedMapFile = values["map_file"] as? String {
            // TODO: pick a sensible default image
            let imageRef = storageRef.child((values["image"] as? String) ?? "olin_library.jpg")
            imageRef.getData(maxSize: 10*1024*1024) { imageData, error in
                if let error = error {
                    print(error.localizedDescription)
                    // Error occurred
                } else {
                    if let data = imageData {
                        self.images.append(UIImage(data: data)!)
                        self.files.append(processedMapFile)
                        self.maps.append(key)
                    }
                }
            }
        }
    }
}
