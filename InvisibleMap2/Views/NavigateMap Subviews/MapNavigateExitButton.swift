//
//  MapNavigateExitButton.swift
//  InvisibleMap2
//
//  Created by occamlab on 6/24/22.
//  Copyright © 2022 Occam Lab. All rights reserved.
//
//  Exit Button for Invisible Map

import SwiftUI

struct MapNavigateExitButton: View {
    @Environment(\.presentationMode) var mode: Binding<PresentationMode>
    @State private var showCancelConfirmation = false
    var mapFileName: String

    var body: some View {
        Button(action: {
            showCancelConfirmation = true
        }){
            Image(systemName: "xmark")
                .accessibility(label: Text("Exit Navigation button"))
        }
        .buttonStyle(RectangleButtonStyle())
        .alert(isPresented: $showCancelConfirmation) {
            Alert(
                title: Text("Would you like to stop navigating?"),
                primaryButton: .destructive(Text("Exit")) {
                print("exiting map navigation view...")
                self.mode.wrappedValue.dismiss()
             //   NavigationLink(destination: SelectPathView())
                    Clew2AppController.shared.process(event: .LeaveMapRequested(mapFileName: mapFileName)) // Tells the state machine to cancel the map navigating
                },
                secondaryButton: .cancel()
            )
        }
    }
}

