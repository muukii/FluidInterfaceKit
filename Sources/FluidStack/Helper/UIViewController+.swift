import ObjectiveC
import UIKit

extension UIViewController {
  
  func currentFirstResponder() -> UIResponder? {
    if isFirstResponder {
      return self
    }
    
    return view.currentFirstResponder()
  }

  /**
   Returns all ``FluidStackController``s in hierachy of the ``UIWindow``.
   Including the receiver if it's ``FluidStackController``.
   */
  public func fluidStackControllers() -> [FluidStackController] {

    /// going back using `.parent` instead of `.next` because to ignore modal-presentation.
    return sequence(first: self) {
      $0.parent
    }
    .compactMap { $0 as? FluidStackController }

  }

  public struct FluidStackFindStrategy {

    public let name: String
    
    let pick: @MainActor ([FluidStackController]) -> FluidStackController?

    /// Creates an instance
    /// - Parameter where: Solves find by return true. Given instances come from the nearest one.
    public init(
      name: String,
      pick: @escaping @MainActor ([FluidStackController]) -> FluidStackController?
    ) {
      self.name = name
      self.pick = pick
    }

    /// Finds by identifier
    public static func identifier(_ identifier: sending FluidStackController.Identifier) -> Self {
      .init(name: "identifier.\(identifier)") { stackControllers in
        stackControllers.first { $0.stackIdentifier == identifier }
      }
    }

    /**
     Finds a nearest ``FluidStackController`` including itself
     */
    public static var current: Self { 
      {
        .init(name: "current") { controllers in
          controllers.first
        }
      }()
    }
    
    /**
     Finds a nearest ``FluidStackController`` excluding itself
     */
    public static var nearestAncestor: Self {
      {
        .init(name: "nearestAncestor") { controllers in
          controllers.dropFirst(1).first
        }
      }()
    }

    /**
     Finds a root ``FluidStackController`` in the UIWindow.
     */
    public static var root: Self {
      {
        .init(name: "root") { controllers in
          controllers.last
        }
      }()
    }

    /// Finds by composed strategy
    public static func matching(
      name: String,
      strategies: sending [FluidStackFindStrategy]
    ) -> Self {
      return .init(name: name) { stackControllers in
        for strategy in strategies {
          if let found = strategy.pick(stackControllers) {
            return found
          }
        }
        return nil
      }
    }

  }

  /**
   Returns the view controller's nearest ancestor ``FluidStackController`` (including itself) with a given strategy

   ``FluidStackController`` can set an identifier on init.
   */
  public func fluidStackController(with strategy: FluidStackFindStrategy) -> FluidStackController? {

    let controllersOrderByNearest = fluidStackControllers()

    return strategy.pick(controllersOrderByNearest)

  }

}

@MainActor
private var _fluid_associated_key: Void?

private final class _Associated {
  var fluidStackContentConfiguration: FluidStackContentConfiguration = .init()
  var fluidStackContext: FluidStackContext?
  var fluidStackActionHandlers: [@MainActor (FluidStackAction) -> Void] = []
}

extension UIViewController {
  
  private var _associated: _Associated {
    assert(Thread.isMainThread)
    if let created = objc_getAssociatedObject(self, &_fluid_associated_key) as? _Associated {
      return created
    }
    let new = _Associated()
    objc_setAssociatedObject(self, &_fluid_associated_key, new, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return new
  }

  /// A struct that configures how to display in ``FluidStackController``
  public var fluidStackContentConfiguration: FluidStackContentConfiguration {
    get { _associated.fluidStackContentConfiguration }
    set { _associated.fluidStackContentConfiguration = newValue }
  }
  
  /// A collection of registered action handlers.
  public var fluidStackActionHandlers: [@MainActor (FluidStackAction) -> Void] {
    get { _associated.fluidStackActionHandlers }
    set { _associated.fluidStackActionHandlers = newValue }
  }
  
  /// Registers closure to handle actions from ``FluidStackController``.
  public func addFluidStackActionHandler(_ handler: @escaping @MainActor (FluidStackAction) -> Void) {
    fluidStackActionHandlers.append(handler)
  }
  
  /**
   Propagates action to this view controller and its children.
   Won't be over other FluidStackController.
   */
  func propagateStackAction(_ action: FluidStackAction) {
    
    func _propagateRecursively(viewController: UIViewController) {

      if let stackController = viewController as? FluidStackController {

        for handler in stackController.fluidStackActionHandlers {
          handler(action)
        }

        stackController.topViewController?.propagateStackAction(action)

        return
      }

      // call all of handlers
      for handler in viewController.fluidStackActionHandlers {
        handler(action)
      }

      // propagates to children
      for viewController in viewController.children {
        // recursive
        _propagateRecursively(viewController: viewController)
      }
    }
    
    _propagateRecursively(viewController: self)
    
  }

  /// [Get]: Returns a stored instance or nearest parent's one.
  /// [Set]: Stores given instance.
  public internal(set) var fluidStackContext: FluidStackContext? {
    get {

      guard
        let object = _associated.fluidStackContext
      else {
        if parent is FluidStackController {
          // stop find
          return nil
        }
        // continue to find from parent
        return parent?.fluidStackContext
      }
      return object

    }
    set {
      _associated.fluidStackContext = newValue
    }

  }
}

extension UIViewController {
  
  func isDescendant(of viewController: UIViewController) -> Bool {
    
    viewController == self || viewController.children.contains(self)
    
  }
  
}

extension ViewControllerAssertionProhibitedPresentInFluidStack {
  
  @MainActor
  @available(*, deprecated, message: "This view controller can't be wrapped. Prohibited by `ViewControllerAssertionProhibitedPresentInFluidStack`.")
  public func fluidWrapped(
    configuration: FluidViewController.Configuration
  ) -> FluidViewController where Self : ViewControllerAssertionProhibitedPresentInFluidStack {
    assertionFailure()
    return (self as UIViewController).fluidWrapped(configuration: configuration)
  }
  
}

