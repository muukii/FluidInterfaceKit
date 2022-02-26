import UIKit

/**
 A context object to interact with container view controller for transitions.
 */
public final class RemovingTransitionContext: TransitionContext {
  
  public enum CompletionEvent {
    /// Transition has been finished (no interruption was in there)
    case succeeded
    /// Transition has been interrupted
    case interrupted
    /// Transition has been cancelled in interaction
    case cancelled
  }

  public private(set) var isCompleted: Bool = false

  /// A view controller for removing
  public let fromViewController: UIViewController
  
  /// A view controller that displays after removed
  public let toViewController: UIViewController?

  private let onAnimationCompleted: (RemovingTransitionContext) -> Void
  private let onRequestedDisplayOnTop: (DisplaySource) -> FluidStackController.DisplayingOnTopSubscription

  private var callbacks: [(CompletionEvent) -> Void] = []
  
  init(
    contentView: UIView,
    fromViewController: UIViewController,
    toViewController: UIViewController?,
    onAnimationCompleted: @escaping (RemovingTransitionContext) -> Void,
    onRequestedDisplayOnTop: @escaping (DisplaySource) -> FluidStackController.DisplayingOnTopSubscription
  ) {
    self.fromViewController = fromViewController
    self.toViewController = toViewController
    self.onAnimationCompleted = onAnimationCompleted
    self.onRequestedDisplayOnTop = onRequestedDisplayOnTop
    super.init(contentView: contentView)
  }
    
  /**
   Notifies controller transition has been completed.
   */
  public func notifyAnimationCompleted() {
    assert(Thread.isMainThread)
    guard isCompleted == false else { return }
    isCompleted = true
    onAnimationCompleted(self)
  }
  
  public func notifyCancelled() {
    assert(Thread.isMainThread)
    isInvalidated = true
    callbacks.forEach { $0(.cancelled) }
    onAnimationCompleted(self)
  }
  
  public func requestDisplayOnTop(_ source: DisplaySource) -> FluidStackController.DisplayingOnTopSubscription {
    onRequestedDisplayOnTop(source)
  }
  
  /// Marks as this current transition has been outdated.
  /// Another transition's started by owner.
  /// Triggers ``addCompletionEventHandler(_:)`` with ``TransitionContext/CompletionEvent/interrupted``
  override func invalidate() {
    assert(Thread.isMainThread)
    isInvalidated = true
    callbacks.forEach { $0(.interrupted) }
  }
  
  /**
   Adds closure that handles completion events (``CompletionEvent``)
   */
  public func addCompletionEventHandler(_ closure: @escaping (CompletionEvent) -> Void) {
    assert(Thread.isMainThread)
    callbacks.append(closure)
  }

  /**
   Triggers ``addCompletionEventHandler(_:)`` with ``TransitionContext/CompletionEvent/succeeded``
   */
  func transitionSucceeded() {
    callbacks.forEach{ $0(.succeeded) }
  }
    
  deinit {
    assert(
      isInvalidated == true || isCompleted == true,
      "\(self) is deallocated without appropriate operation. Call `notifyAnimationCompleted()` or `notifyCancelled()`"
    )
  }
}
