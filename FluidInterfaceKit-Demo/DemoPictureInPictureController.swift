//
//  DemoPictureInPictureController.swift
//  FluidInterfaceKit-Demo
//
//  Created by Muukii on 2022/01/13.
//

import CompositionKit
import FluidInterfaceKit
import Foundation
import MondrianLayout
import UIKit

final class DemoPictureInPictureController: FluidPictureInPictureController {

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground

    let label = UILabel()&>.do {
      $0.text = "PiP"
    }

    let backgroundView = UIView()
    backgroundView.backgroundColor = .systemOrange

    let content = CompositionKit.AnyView { _ in
      ZStackBlock {
        VStackBlock {
          label
        }
      }
      .background(backgroundView)
    }

    let interactiveView = InteractiveView(
      animation: .bodyShrink,
      haptics: .impactOnTouchUpInside(),
      useLongPressGesture: false,
      contentView: content
    )

    interactiveView.handlers.onTap = { [unowned self] in

      switch state.mode {
      case .maximizing:
        setMode(.floating)
      case .folding:
        break
      case .floating:
        setMode(.maximizing)
      }

    }

    setContent(interactiveView)
  }
}
