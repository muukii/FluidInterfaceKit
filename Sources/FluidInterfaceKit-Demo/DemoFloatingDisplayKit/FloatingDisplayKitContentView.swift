//
//  ContentView.swift
//  Demo
//
//  Created by Muukii on 2021/04/24.
//

import FluidInterfaceKit
import SwiftUI

let snackbarController = FloatingDisplayController()

struct FloatingDisplayKitContentView: View {
  var body: some View {
    VStack {
      Button("Display Bar") {
        snackbarController.deliver(
          notification: .init {
            DemoSnackbarView(text: "Hello")
          },
          animator: FloatingDisplaySlideInTrantision()
        )
      }

      Button("Display Popup") {
        snackbarController.display(
          context: .init(
            viewBuilder: {
              DemoSnackbarView(text: "Hello")
            },
            position: .center,
            transition: FloatingDisplayPopupTransition()
          ),
          waitsInQueue: false
        )
      }

    }
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    FloatingDisplayKitContentView()
  }
}
