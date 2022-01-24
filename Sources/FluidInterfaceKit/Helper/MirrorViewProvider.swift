
import UIKit

public final class AnyMirrorViewProvider {
      
  public struct Handlers {
    public var make: ((_ cached: UIView?) -> UIView)?
  }
  
  private let handlers: Handlers
  
  private var cached: UIView?
  
  public init(_ maker: (inout Handlers) -> Void) {
    var handlers = Handlers()
    maker(&handlers)
    self.handlers = handlers
  }
  
  func view() -> UIView {
    assert(Thread.isMainThread)
    let created = handlers.make!(cached)
    cached = created
    return created
  }
  
  public func make() -> AnyMirrorViewProvider {
    assert(Thread.isMainThread)
    let created = handlers.make!(cached)
    cached = created
    return self
  }
}

extension AnyMirrorViewProvider {
  
  public static func snapshot(caches: Bool, viewProvider: @escaping () -> UIView) -> Self {
    
    return .init { handlers in
      
      handlers.make = { cached in
        if caches, let cached = cached {
          return cached
        }
        return viewProvider().snapshotView(afterScreenUpdates: false) ?? UIView()
      }
      
    }
  }
  
}
