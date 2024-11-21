import SwiftUI
import UIKit
import ResultBuilderKit
import FluidPortal

/// Actions that comes from ``FluidStackController``
public enum FluidStackAction {

  /// It will appear on a stack.
  /// Emits before the transition starts but after viewDidLoad and inserted into the stack.
  case willPush

  /// Potentially it won't be emmited after ``FluidStackAction/willPush``
  case didPush

  /// on started pop operation
  case willPop

  /// Potentially it won't be emmited after ``FluidStackAction/willPop``
  case didPop
}

public enum RemovingRule {
  /// Removes all of view controllers above itself.
  case cascade
  /// Removes only itself, leaving view controllers above itself.
  case single
}

/// A struct that configures how to display in ``FluidStackController``
public struct FluidStackContentConfiguration {
  
  public enum ContentType {
    /// Allows background view offloads.
    case opaque
    /// Leaves background view controller in the hierarchy.
    case overlay
  }

  /// Specifies whether ``FluidStackController`` updates status bar appearance when displaying its target view controller.
  public var capturesStatusBarAppearance: Bool = true
  
  public var contentType: ContentType = .opaque

}

/// A container view controller that manages view controller and view as child view controllers.
/// It provides transitions when adding and removing.
///
/// You may create subclass of this to make a first view.
///
/// Passing an identifier on initializing, make it could be found in hierarchy.
/// Use ``UIViewController/fluidStackController(with: )`` to find.
open class FluidStackController: UIViewController {
  
  public enum Action {
    case onChanged(viewControllers: [UIViewController])
  }

  // MARK: - Properties
  
  /// A closure that receives ``Action``
  public final var stackActionHandler: (Action) -> Void = { _ in }

  /// A configuration
  public let stackConfiguration: Configuration

  /// an string value that identifies the instance of ``FluidStackController``.
  public var stackIdentifier: Identifier?

  /// A content view that stays in back
  public let contentView: UIView

  /// The view controller at the top of the stack.
  public var topViewController: UIViewController? {
    return topItem?.viewController
  }

  /// An array of view controllers currently managed.
  /// Might be different with ``UIViewController.children``.
  public var stackingViewControllers: [UIViewController] {
    stackingItems.map { $0.viewController }
  }
  
  private var topItem: StackingPlatterView? {
    stackingItems.last
  }
  
  private(set) var stackingItems: [StackingPlatterView] = [] {
    didSet {
      
      if stackingItems != oldValue {
        
        // TODO: Update with animation
        UIViewPropertyAnimator(duration: 0.4, dampingRatio: 1) {
          self.setNeedsStatusBarAppearanceUpdate()
        }
        .startAnimation()
        stackingViewControllersDidChange(stackingViewControllers)
        
        stackActionHandler(.onChanged(viewControllers: stackingViewControllers))
      }
    }
  }
  
  private var state: State = .init()

  private let __rootView: UIView?
  
  open override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
    return stackingItems.last?.viewController
  }
  
  open override var childForHomeIndicatorAutoHidden: UIViewController? {
    return stackingItems.last?.viewController
  }

  open override var childForStatusBarStyle: UIViewController? {
    return stackingItems.last {
      $0.viewController.fluidStackContentConfiguration.capturesStatusBarAppearance == true
    }?.viewController
  }

  open override var childForStatusBarHidden: UIViewController? {
    return stackingItems.last {
      $0.viewController.fluidStackContentConfiguration.capturesStatusBarAppearance == true
    }?.viewController
  }

  open override func loadView() {
    if let __rootView = __rootView {
      view = __rootView
    } else {
      super.loadView()
    }
  }

  // MARK: - Initializers

  /// Creates an instance
  /// - Parameters:
  ///   - identifier: ``Identifier-swift.struct`` to find the instance in hierarchy.
  ///   - view: a view that used in ``loadView()``
  ///   - contentView: a view that displays as first view in hierarchy of ``UIViewController/view``
  ///   - stackConfiguration: ``Configuration-swift.struct``
  ///   - rootViewController: Adds as a first content
  public init(
    identifier: Identifier? = nil,
    view: UIView? = nil,
    contentView: UIView? = nil,
    configuration: Configuration = .init(),
    rootViewController: UIViewController? = nil
  ) {
    self.stackIdentifier = identifier
    self.__rootView = view
    self.contentView = contentView ?? .init()
    self.stackConfiguration = configuration
    
    super.init(nibName: nil, bundle: nil)
       
    if let rootViewController = rootViewController {
      addContentViewController(rootViewController, transition: .disabled)
    }
    
  }

  @available(*, unavailable)
  public required init?(
    coder: NSCoder
  ) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: - Functions
  
  open func stackingViewControllersDidChange(_ viewControllers: [UIViewController]) {
    UIAccessibility.post(notification: .screenChanged, argument: nil)
  }
  
  public func stackingDescription() -> String {
    
    let body = stackingItems.map { item in
      "- isLoaded: \(item.isLoaded ? "✅" : "⬜️"), \(item.viewController.debugDescription)"
    }
    .joined(separator: "\n")
    
    return """

      🪜 Stacking: \(stackingItems.count), \(self.debugDescription)
      \(body)
      """
  }
  
  // MARK: - ViewController

  /**
   Make sure call super method when you create override.
   */
  open override func viewDidLoad() {
    super.viewDidLoad()

    view.accessibilityIdentifier = "FluidStack.\(stackIdentifier?.rawValue ?? "unnamed")"

    view.addSubview(contentView)

    contentView.frame = view.bounds
    contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
  }

  // MARK: - Add or Remove view controllers
  
  /**
   Removes the view controller displayed on most top.
   */
  @MainActor
  public func removeLastViewController(
    transition: AnyRemovingTransition?,
    completion: @MainActor @escaping (RemovingTransitionContext.CompletionEvent) -> Void = { _ in }
  ) {

    guard let wrapperView = stackingItems.last else {
      Log.error(.stack, "The last view controller was not found to remove")
      completion(.succeeded)
      return
    }

    removeViewController(
      wrapperView.viewController,
      removingRule: .cascade,
      transition: transition,
      completion: completion
    )
  }

  @discardableResult
  @MainActor
  public func removeLastViewController(
    transition: AnyRemovingTransition?
  ) async -> RemovingTransitionContext.CompletionEvent {

    await withCheckedContinuation { continuation in

      removeLastViewController(transition: transition) { event in
        continuation.resume(returning: event)
      }
    }

  }


  /**
   Add a view controller to display.
   This is a primitive operation to add view controller to display.
   ``UIViewController/fluidPush`` runs this method internally.

   - Parameters:
     - transition:
       a transition for adding. if view controller is type of ``TransitionViewController``, uses this transition instead of TransitionViewController's transition.
       You may set ``.disabled`` to disable animation
   */
  public func addContentViewController(
    _ viewControllerToAdd: UIViewController,
    transition: AnyAddingTransition?,
    afterViewDidLoad: @escaping @MainActor () -> Void = {},
    completion: (@MainActor (AddingTransitionContext.CompletionEvent) -> Void)? = nil
  ) {

    /**
     possible to enter while previous adding operation.
     adding -> removing(interruption) -> adding(interruption) -> dipslay(completed)
     */

    assert(Thread.isMainThread)
    
    // Construct view controller chain
    if viewControllerToAdd.parent != self {
      
      addChild(viewControllerToAdd)
      
      viewControllerToAdd.view.resetToVisible()
      
      viewControllerToAdd.didMove(toParent: self)
      
    } else {
      // case of adding while removing
      // TODO: might something needed
    }
        
    // set a context if not set
    if viewControllerToAdd.fluidStackContext == nil {
      let context = FluidStackContext(
        fluidStackController: self,
        targetViewController: viewControllerToAdd
      )
      // set context
      viewControllerToAdd.fluidStackContext = context
    }
    
    /// Save current first-responder from the current displaying view controller.
    /// To restore it when back to this view controller as the top - ``FluidStackController/StackingPlatterView/restoreResponderState()``
    topItem?.saveResponderState()

    // Trigger `viewDidLoad` explicitly.
    viewControllerToAdd.loadViewIfNeeded()
    
    afterViewDidLoad()
    
    let platterView: StackingPlatterView = {
      if let currentPlatterView = viewControllerToAdd.view.superview as? StackingPlatterView {
        // reuse
        return currentPlatterView
      } else {
        // create new one
        let newPlatterView = StackingPlatterView(
          viewController: viewControllerToAdd,
          frame: self.view.bounds
        )
        return newPlatterView
      }
    }()
    
    view.addSubview(platterView)
    platterView.makeViewControllerFirstResponder()
    
    // propagate after `viewDidLoad`
    viewControllerToAdd.propagateStackAction(.willPush)

    // take before modifying.
    let currentTop = stackingItems.last
    
    // Adds the view controller at the latest position.
    do {
      var modified = stackingItems
      modified.removeAll { $0.viewController == viewControllerToAdd }
      modified.append(platterView)
      stackingItems = modified
    }

    assert(viewControllerToAdd.view.superview != nil)
    assert(viewControllerToAdd.view.superview is StackingPlatterView)

    let newTransitionContext = AddingTransitionContext(
      contentView: platterView,
      fromViewController: currentTop?.viewController,
      toViewController: viewControllerToAdd,
      onAnimationCompleted: { [weak self, weak platterView] context in
                        
        // MARK: Handling after animation
        
        assert(Thread.isMainThread)
        
        guard let self = self, let platterView = platterView else { return }
        
        defer {

          platterView.removeTransitionContext(expect: context)
          
          if self.state.latestTransitionContext == context {
            // handling offload
            if self.stackConfiguration.isOffloadViewsEnabled {
              self.updateOffloadingItems()
            }
          }
        }

        guard context.isInvalidated == false else {
          Log.debug(.stack, "\(context) was invalidated, skips adding")
          return
        }
                                 
        context.transitionSucceeded()
        platterView.viewController.propagateStackAction(.didPush)
        
      }
    )
    
    // To run offloading after latest adding transition.
    // it won't run if got invalidation by started removing-transition.
    state.latestTransitionContext = newTransitionContext

    newTransitionContext.addCompletionEventHandler { event in
      completion?(event)
      UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    platterView.swapTransitionContext(newTransitionContext)

    // Start transition after invalidated current transition.
    do {

      // Turns off touch through to prevent the user attempt to start another adding-transition.
      // `Flexible` means the user can dispatch cancel in the current transition.
      platterView.isTouchThroughEnabled = false

      if let transition = transition {

        transition.startTransition(context: newTransitionContext)
      } else if let transitionViewController = viewControllerToAdd as? FluidTransitionViewController
      {

        transitionViewController.startAddingTransition(
          context: newTransitionContext
        )
      } else {
        AnyAddingTransition.disabled.startTransition(context: newTransitionContext)
      }
    }

  }

  /**
   Add a view to display with wrapping internal view controller.

   - Parameters:
     - transition: You may set ``.disabled`` to disable transition animation.
   */

  public func addContentView(
    _ view: UIView,
    transition: AnyAddingTransition?,
    completion: (@MainActor (AddingTransitionContext.CompletionEvent) -> Void)? = nil
  ) {

    assert(Thread.isMainThread)

    let viewController = ContentWrapperViewController(view: view)
    addContentViewController(viewController, transition: transition, completion: completion)

  }

  /**
   Starts removing transaction for interaction.
   Make sure to complete the transition with the context.
   */
  public func startRemovingForInteraction(
    _ viewControllerToRemove: UIViewController,
    completion: (@MainActor (RemovingTransitionContext.CompletionEvent) -> Void)? = nil
  ) -> RemovingTransitionContext {

    // Handles stackConfiguration
    if stackConfiguration.retainsRootViewController,
       viewControllerToRemove == stackingItems.first?.viewController
    {
      Log.error(
        .stack,
        "the stacking will broke. Attempted to remove the view controller which displaying as root view controller. but the stackConfiguration requires to retains the root view controller."
      )
    }
    
    guard let viewToRemove = stackingItems.first(where: { $0.viewController == viewControllerToRemove }) else {
      preconditionFailure("Not found wrapper view to manage \(viewControllerToRemove)")
    }

    return _startRemoving(viewToRemove, completion: completion)
  }

  /**
   Starts removing transaction.
   Make sure to complete the transition with the context.
   */
  private func _startRemoving(
    _ platterView: StackingPlatterView,
    completion: (@MainActor (RemovingTransitionContext.CompletionEvent) -> Void)? = nil
  ) -> RemovingTransitionContext {

    // Ensure it's managed
    guard
      let index = stackingItems.firstIndex(of: platterView)
    else {
      Log.error(.stack, "\(platterView.viewController) was not found to remove")
      fatalError()
    }

    // finds a view controller that will be displayed next.
    let backView: StackingPlatterView? = {
      let target = index.advanced(by: -1)
      if stackingItems.indices.contains(target) {
        return stackingItems[target]
      } else {
        return nil
      }
    }()
    
    platterView.viewController.propagateStackAction(.willPop)
    backView?.viewController.propagateStackAction(.willPush)
    
    let newTransitionContext = RemovingTransitionContext(
      contentView: platterView,
      fromViewController: platterView.viewController,
      toViewController: backView?.viewController,
      onAnimationCompleted: { [weak self, weak platterView] context in

        guard let self, let platterView else { return }
        
        defer {
          
          platterView.removeTransitionContext(expect: context)
          
          if self.state.latestTransitionContext == context {
            // handling offload
            if self.stackConfiguration.isOffloadViewsEnabled {
              self.updateOffloadingItems()
            }
          }
        }

        guard context.isInvalidated == false else {
          Log.debug(.stack, "\(context) was invalidated, skips removing")
          return
        }

        /**
         Completion of transition, cleaning up
         */
        
        let viewControllerToRemove = platterView.viewController
        self.stackingItems.removeAll { $0.viewController == viewControllerToRemove }
        viewControllerToRemove.fluidStackContext = nil

        viewControllerToRemove.willMove(toParent: nil)
        viewControllerToRemove.removeFromParent()
        platterView.removeFromSuperview()

        context.transitionSucceeded()
        platterView.viewController.propagateStackAction(.didPop)
        
        self.topItem?.restoreResponderState()
                
      },
      onRequestedDisplayOnTop: { [weak self, weak platterView] source in

        guard let self = self, let viewToRemove = platterView else {
          assertionFailure("FluidStackController has been already deallocated.")
          return .init(run: {})
        }

        return self.addPortalView(for: source, on: viewToRemove)
      }
    )
    
    // To run offloading after latest adding transition.
    // it won't run if got invalidation by started removing-transition.
    state.latestTransitionContext = newTransitionContext

    newTransitionContext.addCompletionEventHandler { event in
      completion?(event)
    }

    // To enable through to make back view controller can be interactive.
    // Consequently, the user can start another transition.
    platterView.isTouchThroughEnabled = true
    
    // set before update offloading
    platterView.swapTransitionContext(newTransitionContext)
    
    // handling offload
    if self.stackConfiguration.isOffloadViewsEnabled {
      updateOffloadingItems(displayItem: backView ?? platterView)
    }

    return newTransitionContext
  }
  
  public func canRemove(viewController: UIViewController) -> Bool {
    
    if stackConfiguration.retainsRootViewController,
       viewController == stackingItems.first?.viewController
    {
      return false
    }

    return true
  }

  /**
   Removes given view controller with transition.
   
   Switches to batch removing if there are multiple view controllers on top of the given view controller.
   - Parameters:
   */
  public func removeViewController(
    _ viewControllerToRemove: UIViewController,
    removingRule: RemovingRule = .cascade,
    transition: AnyRemovingTransition?,
    transitionForBatch: @autoclosure @escaping () -> AnyBatchRemovingTransition? = .crossDissolve,
    completion: (@MainActor (RemovingTransitionContext.CompletionEvent) -> Void)? = nil
  ) {

    // Handles configuration
    
    guard canRemove(viewController: viewControllerToRemove) else {
      Log.error(
        .stack,
        "Attempted to remove the view controller which displaying as root view controller. but the configuration requires to retains the root view controller."
      )
      return
    }
        
    guard let viewToRemove = stackingItems.first(where: { $0.viewController == viewControllerToRemove }) else {
      assertionFailure("Not found wrapper view to manage \(viewControllerToRemove)")
      return
    }

    switch removingRule {
    case .cascade:

      if stackingItems.last?.viewController != viewControllerToRemove {

        // Removes view controllers with batch

        let transition = transitionForBatch()

        Log.debug(
          .stack,
          "The removing view controller is not displaying on top. it's behind of the other view controllers. Switches to batch-removing using transition: \(transition as Any)"
        )

        removeAllViewController(
          from: viewToRemove.viewController,
          transition: transition,
          completion: { event in

            switch event {
            case .succeeded:
              completion?(.succeeded)
            case .interrupted:
              completion?(.interrupted)
            }

          }
        )
        return
      }

    case .single:
      break
    }

    // Removes view controller
      
    let transitionContext = _startRemoving(viewToRemove, completion: completion)

    if let transition = transition {
      transition.startTransition(context: transitionContext)
    } else if let transitionViewController = viewToRemove.viewController
      as? FluidTransitionViewController
    {
      transitionViewController.startRemovingTransition(context: transitionContext)
    } else {
      transitionContext.notifyAnimationCompleted()
    }

  }

  /**
   Removes all view controllers which are displaying
   */
  public func removeAllViewController(
    transition: AnyBatchRemovingTransition?,
    completion: (@MainActor (BatchRemovingTransitionContext.CompletionEvent) -> Void)? = nil
  ) {

    if stackConfiguration.retainsRootViewController {
      guard let target = stackingItems.dropFirst().first else { return }
      removeAllViewController(from: target.viewController, transition: transition, completion: completion)
    } else {
      guard let target = stackingItems.first else { return }
      removeAllViewController(from: target.viewController, transition: transition, completion: completion)
    }
  }

  /**
   Removes all view controllers which displaying on top of the given view controller.
   
   - FIXME
     - Supports re-entrant operation - adding-transition. It's undefined behavior to get adding while removing.

   - Parameters:
     - from:
     - transition:
   */
  private func removeAllViewController(
    from viewController: UIViewController,
    transition: AnyBatchRemovingTransition?,
    completion: (@MainActor (BatchRemovingTransitionContext.CompletionEvent) -> Void)? = nil
  ) {

    Log.debug(.stack, "Remove \(viewController) from \(stackingItems)")

    assert(Thread.isMainThread)
    
    let targetStackingItems = stackingItems

    guard let index = targetStackingItems.firstIndex(where: { $0.viewController == viewController }) else {
      Log.error(.stack, "\(viewController) was not found to remove")
      return
    }

    let targetTopItem = targetStackingItems[0..<(index)].last

    let itemsToRemove = Array(
      targetStackingItems[
        index...stackingItems.indices.last!
      ]
    )

    assert(itemsToRemove.count > 0)
    
    let transition: AnyBatchRemovingTransition = transition ?? .disabled
    
    let newTransitionContext = BatchRemovingTransitionContext(
      contentView: itemsToRemove.first!,
      fromViewControllers: itemsToRemove.map(\.viewController),
      toViewController: targetTopItem?.viewController,
      onCompleted: { [weak self] context in
        
        assert(Thread.isMainThread)
        
        guard let self = self else {
          return          
        }
        
        /**
         Completion of transition, cleaning up
         */
        
        for itemToRemove in itemsToRemove {
                    
          itemToRemove.removeTransitionContext(expect: context)
          
          itemToRemove.viewController.willMove(toParent: nil)
          itemToRemove.removeFromSuperview()
          itemToRemove.viewController.removeFromParent()
          itemToRemove.viewController.fluidStackContext = nil
          
          self.stackingItems.removeAll { instance in
            (instance as StackingPlatterView) == (itemToRemove as StackingPlatterView)
          }
        }
                      
        context.transitionSucceeded()
        
        self.topItem?.restoreResponderState()
        
      }
    )
    
    newTransitionContext.addCompletionEventHandler { event in
      completion?(event)
    }
    
    for itemToRemove in itemsToRemove {
      itemToRemove.swapTransitionContext(newTransitionContext)
    }
    
    if let targetTopItem = targetTopItem {
      updateOffloadingItems(displayItem: targetTopItem)
    }
    
    transition.startTransition(context: newTransitionContext)
    
  }
  
  // MARK: - Accessing displaying view controllers
  
  public func viewController(before viewController: UIViewController) -> UIViewController? {
    
    let stackingViewControllers = stackingViewControllers
    
    guard let index = stackingViewControllers.firstIndex(of: viewController) else {
      return nil
    }
        
    let targetIndex = stackingViewControllers.index(before: index)
    
    guard stackingViewControllers.indices.contains(targetIndex) else {
      return nil
    }

    return stackingViewControllers[targetIndex]
  }
  
  public func viewController(after viewController: UIViewController) -> UIViewController? {
    
    let stackingViewControllers = stackingViewControllers
    
    guard let index = stackingViewControllers.firstIndex(of: viewController) else {
      return nil
    }
    
    let targetIndex = stackingViewControllers.index(after: index)
    
    guard stackingViewControllers.indices.contains(targetIndex) else {
      return nil
    }
    
    return stackingViewControllers[targetIndex]
  }
  
  // MARK: - Others

  private func addPortalView(
    for source: DisplaySource,
    on targetView: StackingPlatterView
  ) -> DisplayingOnTopSubscription {

    assert(Thread.isMainThread)

    let portalView = PortalView(source: source)
    portalView.frame = targetView.bounds
    portalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    portalView.matchesPosition = true
    portalView.hidesSourceLayer = true
    portalView.matchesTransform = true
    portalView.matchesOpacity = true
    targetView.addSubview(portalView)

    return .init {
      portalView.removeFromSuperview()
    }
  }
     
  /// Convinience method
  private func updateOffloadingItems() {
           
    let items = stackingItems
    
    guard let last = items.last else {
      // seems no there to update offloading.
      return
    }
    
    updateOffloadingItems(displayItem: last)
    
  }
  
  /**
   [primitive]
   Offloads view controllers which do not need to display from their wrapper view.
   - Parameters:
     - displayItem: a item that supposed to be visible on top.
   
   - TODO: Write Test
   */
  private func updateOffloadingItems(displayItem: StackingPlatterView) {
        
    let items = stackingItems
    
    var order: [(StackingPlatterView, Bool)] = []
          
    var offloads: Bool = false
    // if current performing in behined given display item
    var isInBehindDisplayItem: Bool = false
        
    // performs from most top view
    // complex 🤷🏻‍♂️ my bad
    for item in items.reversed() {
      
      if isInBehindDisplayItem {
        if offloads {
          order.append((item, true))
        } else {
          order.append((item, false))
          
          if item.isTransitioning == false {
            switch item.viewController.fluidStackContentConfiguration.contentType {
            case .opaque:
              offloads = true
            case .overlay:
              break
            }
          } else {
            offloads = false
          }
        }
      } else {
        order.append((item, false))
        if item.isTransitioning == false {
          switch item.viewController.fluidStackContentConfiguration.contentType {
          case .opaque:
            offloads = true
          case .overlay:
            offloads = false
          }
        } else {
          offloads = false
        }
        isInBehindDisplayItem = item == displayItem
      }
            
    }
        
    Log.debug(.stack, "Update offload \(displayItem)")
    for (item, offloads) in order {
      if offloads {
        item.offloadViewController()
      } else {
        item.loadViewController()
      }
    }
    
    Log.debug(.stack, self.stackingDescription())
    
  }
    
}

/**
 Extended type of ``FluidStackController`` for working on modal-presentation.
 To create stacking context on modal-presentation.
 
 It dismisses itself automatically when the stacking items is empty.
 
 ```swift
 let stack = PresentationFluidStackController()
 stack.display(on: self)
 
 let content = ContentViewController(color: .neonRandom())
 stack.fluidPush(content.fluidWrapped(configuration: .defaultNavigation), target: .current, relation: .modality)
 ```
 */
open class PresentationFluidStackController: FluidStackController {
  
  public override init(
    identifier: Identifier? = nil,
    view: UIView? = nil,
    contentView: UIView? = nil,
    configuration: Configuration = .init(retainsRootViewController: false),
    rootViewController: UIViewController? = nil
  ) {
    
    super.init(
      identifier: identifier,
      view: view,
      contentView: contentView,
      configuration: configuration,
      rootViewController: rootViewController
    )
    
    modalPresentationStyle = .overFullScreen
    modalTransitionStyle = .crossDissolve
  }
    
  /// Displays this view controller as modal-presentation on the given view controller.
  /// - Parameter viewController: A target view controller to dispach presentation operation.
  public func display(on viewController: UIViewController) {
    viewController.present(self, animated: false)
    CATransaction.flush()
  }
  
  open override func stackingViewControllersDidChange(_ viewControllers: [UIViewController]) {
    if viewControllers.isEmpty {
      dismiss(animated: false)
    }
    UIAccessibility.post(notification: .screenChanged, argument: nil)
  }
  
}

// MARK: - Nested types
extension FluidStackController {

  public struct DisplayingOnTopSubscription {

    private let _run: () -> Void

    init(run: @escaping () -> Void) {
      self._run = run
    }

    public func dispose() {
      _run()
    }

  }

  /// A wrapper object that stores an string value that identifies a instance of ``FluidStackController``.
  public struct Identifier: Hashable, Sendable {

    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }

  }

  public struct Configuration {
    
    /// Keeps hodling a root view controller.
    public var retainsRootViewController: Bool
    
    /// Offloads background view controllers from hierarchy.
    public var isOffloadViewsEnabled: Bool
    
    /// Whether prevents `forwading-pop`
    /// `forwarding-pop` is forwarding pop-operation to the parent stack if there are no items to pop in the current stack.
    public var preventsFowardingPop: Bool
    
    public init(
      retainsRootViewController: Bool = true,
      isOffloadViewsEnabled: Bool = true,
      preventsFowardingPop: Bool = false
    ) {
      self.retainsRootViewController = retainsRootViewController
      self.isOffloadViewsEnabled = isOffloadViewsEnabled
      self.preventsFowardingPop = preventsFowardingPop
    }

  }

  /**
   A view that manages view controller in stack.
   Has a responsibility to guard touches into behind views.
   */
  public final class StackingPlatterView: UIView {
    
    public private(set) var isLoaded: Bool = true
    
    private(set) weak var restoreFirstResponderTarget: UIResponder?

    public var isTouchThroughEnabled = true
    
    public let viewController: UIViewController
    
    private weak var currentTransitionContext: TransitionContext?
    
    var isTransitioning: Bool {
      currentTransitionContext != nil
    }

    init(
      viewController: UIViewController,
      frame: CGRect
    ) {
      
      self.viewController = viewController
            
      super.init(frame: frame)
      
      accessibilityIdentifier = String(reflecting: viewController)

      backgroundColor = .clear
      
      loadViewController()
    }
    
    @available(*, unavailable)
    public required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
      Log.debug(.stack, "Deinit \(self)")
    }
    
    func loadViewController() {
      assert(Thread.isMainThread)
      
      isLoaded = true
      
      if let superview = viewController.view.superview {
        assert(superview == self)
      } else {
        addSubview(viewController.view)
        Fluid.setFrameAsIdentity(frame, for: viewController.view)
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
      }
    }

    func makeViewControllerFirstResponder() {
      guard viewController.canBecomeFirstResponder else { return }
      guard viewController.view.currentFirstResponder() == nil else { return }
      viewController.becomeFirstResponder()
    }
    
    /**
     Unorganized notes:
     
     Invalidates a current transition (mostly caused by adding transition) and set new transitionContext
     it's important to do this before starting a new transition.
     set a new context to receive invalidation from transition for adding started while removing.
     
     Invalidate current transition before start new transition
     to prevent overlapping cleanup operations by completion handlers in transition context.
     For instance, when animating for adding, then interrupted by cleanup operation.
     */
    func swapTransitionContext(_ transitionContext: TransitionContext?) {
      currentTransitionContext?.invalidate()
      currentTransitionContext = transitionContext
    }
    
    func removeTransitionContext(expect: TransitionContext?) {
      if let expect = expect {
        if currentTransitionContext == expect {
          currentTransitionContext = nil
        }
      } else {
        currentTransitionContext = nil
      }
    }
    
    func offloadViewController() {
      
      assert(Thread.isMainThread)
      
      isLoaded = false
      
      viewController.view.removeFromSuperview()
    }
    
    func saveResponderState() {
      restoreFirstResponderTarget = viewController.currentFirstResponder()
      restoreFirstResponderTarget?.resignFirstResponder()
    }
    
    func restoreResponderState() {
      restoreFirstResponderTarget?.becomeFirstResponder()
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {

      if isTouchThroughEnabled {
        let view = super.hitTest(point, with: event)
        if view == self {
          return nil
        } else {
          return view
        }
      } else {
        return super.hitTest(point, with: event)
      }
    }

  }

  private struct State: Equatable {
    weak var latestTransitionContext: TransitionContext?
  }

}

extension FluidStackController {

  private final class ContentWrapperViewController: UIViewController {

    private let __rootView: UIView

    override func loadView() {
      view = __rootView
    }

    init(
      view: UIView
    ) {
      self.__rootView = view
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(
      coder: NSCoder
    ) {
      fatalError("init(coder:) has not been implemented")
    }
  }

}
