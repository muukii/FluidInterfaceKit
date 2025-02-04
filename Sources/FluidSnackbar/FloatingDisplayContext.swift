import SwiftUI
import SwiftUIHosting
import UIKit

/// A context object that provides a concrete view to display
open class FloatingDisplayContext: Hashable {

  public static func == (lhs: FloatingDisplayContext, rhs: FloatingDisplayContext) -> Bool {
    lhs === rhs
  }

  public func hash(into hasher: inout Hasher) {
    ObjectIdentifier(self).hash(into: &hasher)
  }

  private let factory: @MainActor () -> FloatingDisplayViewType

  public let transition: FloatingDisplayTransitionType

  public let position: FloatingDisplayController.DisplayPosition

  public init(
    viewBuilder: @escaping @MainActor () -> FloatingDisplayViewType,
    position: FloatingDisplayController.DisplayPosition,
    transition: FloatingDisplayTransitionType
  ) {
    self.factory = viewBuilder
    self.transition = transition
    self.position = position
  }

  @MainActor
  func makeView() -> FloatingDisplayViewType {
    factory()
  }
}

extension FloatingDisplayContext {

  public convenience init<Content: View>(
    position: FloatingDisplayController.DisplayPosition,
    transition: FloatingDisplayTransitionType,
    onTap: @escaping @MainActor () -> Void,
    @ViewBuilder content: sending @escaping () -> Content
  ) {

    self.init(
      viewBuilder: {
        _HostingWrapperView(hostingView: SwiftUIHostingView(content: content), onTap: onTap)
      },
      position: position,
      transition: transition
    )

  }

}

private final class _HostingWrapperView<Content: View>: SnackbarDraggableBase {

  private let hostingView: SwiftUIHostingView<Content>

  init(hostingView: SwiftUIHostingView<Content>, onTap: @escaping @MainActor () -> Void) {
    self.hostingView = hostingView
    super.init(topMargin: .zero)
    contentView.addSubview(hostingView)
    hostingView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      hostingView.topAnchor.constraint(equalTo: contentView.topAnchor),
      hostingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      hostingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      hostingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    ])

    self.onTap = onTap
  }

}
