# Clew 2.0 Project

The Clew 2.0 Project is intended to assist the blind and visually impaired more easily navigate indoor spaces. We utilize april tags and the pose of an iPhone to localize the person in a three dimensional map of their surrounding environment and help them navigate. We also use cloud anchors and geospatial anchors to help them navigate.

Built for OccamLab @Olin College 2021

## Running the app
(1) After cloning this repository as Clew2.0, Download and unzip [release 3.3.0 of the library VISP](http://visp-doc.inria.fr/download/framework/visp-3.3.0.framework.zip).

(2) In Finder, drag the `opencv2.framework` and `visp3.framework` frameworks into your local InvisibleMap folder.

(3) You will need to contact a member of OccamLab in order to be added to the Firebase console project to get the `GoogleService-Info.plist` file. Once you have this file, copy it into your `InvisibleMap/InvisibleMap` folder.

(4) In your terminal, run `open Clew2.0.xcworkspace/`.

(5) Build and run the app!

To learn more about OccamLab, please visit our website: http://occam.olin.edu/.
