import GeometryKit
import UIKit

open class FluidPictureInPictureController: UIViewController {

  public var state: State {
    customView.state
  }

  private var customView: View {
    view as! View
  }

  open override func loadView() {
    view = View()
  }

  public init() {
    super.init(nibName: nil, bundle: nil)

  }

  @available(*, unavailable)
  public required init?(
    coder: NSCoder
  ) {
    fatalError("init(coder:) has not been implemented")
  }

  open override func viewDidLoad() {
    super.viewDidLoad()

  }

  public func setContent(_ content: UIView) {
    customView.containerView.setContent(content)
  }

  public func setMode(_ mode: Mode) {
    customView.setMode(mode)
  }

}

extension FluidPictureInPictureController {

  struct Position: OptionSet {
    let rawValue: Int

    static let right: Position = .init(rawValue: 1 << 0)
    static let left: Position = .init(rawValue: 1 << 1)
    static let top: Position = .init(rawValue: 1 << 2)
    static let bottom: Position = .init(rawValue: 1 << 3)

    init(
      rawValue: Int
    ) {
      self.rawValue = rawValue
    }
  }

  public enum Mode {
    case maximizing
    case folding
    case floating
  }

  public struct Configuration {

  }

  public final class ContainerView: UIView {

    public func setContent(_ content: UIView) {
      addSubview(content)
      content.frame = bounds
      content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
  }

  public struct State {

    struct ConditionToLayout: Equatable {
      var bounds: CGRect
      var safeAreaInsets: UIEdgeInsets
      var layoutMargins: UIEdgeInsets
    }

    public internal(set) var mode: Mode = .floating
    var conditionToLayout: ConditionToLayout?
    var snappingPosition: Position = [.right, .bottom]
  }

  private final class View: UIView {

    let containerView: ContainerView = .init()

    let sizeForFloating = CGSize(width: 100, height: 140)

    private(set) var state: State = .init() {
      didSet {
        receiveUpdate(state: state, oldState: oldValue)
      }
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
      let view = super.hitTest(point, with: event)
      if view == self {
        return nil
      } else {
        return view
      }
    }

    override init(
      frame: CGRect
    ) {
      super.init(frame: frame)

      let dragGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))

      containerView.addGestureRecognizer(dragGesture)

      addSubview(containerView)

      containerView.backgroundColor = .init(white: 0.5, alpha: 0.3)
    }

    required init?(
      coder: NSCoder
    ) {
      fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode) {
      state.mode = mode
      setNeedsLayout()

      let animator = UIViewPropertyAnimator(
        duration: 0.8,
        timingParameters: UISpringTimingParameters(
          dampingRatio: 0.9,
          initialVelocity: .zero
        )
      )

      animator.addAnimations {
        self.layoutIfNeeded()
      }

      animator.startAnimation()

    }

    override func layoutSubviews() {
      super.layoutSubviews()

      switch state.mode {
      case .maximizing:
        containerView.frame = bounds
        state.conditionToLayout = nil
      case .folding:
        break
      case .floating:
        let proposedCondition = State.ConditionToLayout(
          bounds: bounds,
          safeAreaInsets: safeAreaInsets,
          layoutMargins: layoutMargins
        )

        switch state.conditionToLayout {
        case .some(let condition) where condition != proposedCondition:
          state.conditionToLayout = proposedCondition
        case .none:
          state.conditionToLayout = proposedCondition
        default:
          return
        }

        containerView.frame = calculateFrameForFloating(for: state.snappingPosition)
      }

    }

    override func layoutMarginsDidChange() {
      super.layoutMarginsDidChange()
      setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
      super.safeAreaInsetsDidChange()
      setNeedsLayout()
    }

    private func receiveUpdate(state: State, oldState: State) {

    }

    private func calculateFrameForFloating(
      for snappingPositon: Position
    ) -> CGRect {

      let containerSize = sizeForFloating
      let baseFrame = bounds

      let insetFrame =
        baseFrame
        .inset(by: safeAreaInsets)
        .insetBy(dx: 12, dy: 12)

      var origin = CGPoint(x: 0, y: 0)

      let snappingPosition = state.snappingPosition

      if snappingPosition.contains(.top) {
        origin.y = insetFrame.minY
      }

      if snappingPosition.contains(.bottom) {
        origin.y = insetFrame.maxY - containerSize.height
      }

      if snappingPosition.contains(.left) {
        origin.x = insetFrame.minX
      }

      if snappingPosition.contains(.right) {
        origin.x = insetFrame.maxX - containerSize.width
      }

      return .init(origin: origin, size: containerSize)

    }

    @objc
    private dynamic func handlePanGesture(gesture: UIPanGestureRecognizer) {

      guard state.mode == .floating else {
        return
      }

      switch gesture.state {
      case .began:
        fallthrough
      case .changed:
        let translation = gesture.translation(in: gesture.view)

        let animator = UIViewPropertyAnimator(
          duration: 0.4,
          timingParameters: UISpringTimingParameters(
            dampingRatio: 1,
            initialVelocity: .zero
          )
        )

        animator.addAnimations {
          gesture.view.unsafelyUnwrapped.center.x += translation.x
          gesture.view.unsafelyUnwrapped.center.y += translation.y
        }

        animator.startAnimation()

        gesture.setTranslation(.zero, in: gesture.view)

      case .possible:
        break
      case .ended,
        .cancelled,
        .failed:

        let frame = gesture.view!.convert(gesture.view!.bounds, to: self)
        let gestureVelocity = gesture.velocity(in: self)

        var locationBasedAnchorPoint: Position {
          switch (bounds.width / 2 > frame.minX, bounds.height / 2 > frame.midY) {
          case (true, true):
            return [.left, .top]
          case (true, false):
            return [.left, .bottom]
          case (false, true):
            return [.right, .top]
          case (false, false):
            return [.right, .bottom]
          }
        }

        var flickDirection: Position? {
          let bound: CGFloat = 500

          var directions: Position = []

          switch gestureVelocity.x {
          case ..<(-bound):
            directions.insert(.left)
          case bound...:
            directions.insert(.right)
          default: break
          }

          switch gestureVelocity.y {
          case ..<(-bound):
            directions.insert(.top)
          case bound...:
            directions.insert(.bottom)
          default: break
          }

          return directions
        }

        var velocityBasedAnchorPoint: Position? {
          guard let flickDirection = flickDirection else { return nil }
          var base = locationBasedAnchorPoint

          if flickDirection.contains(.top) {
            base.remove(.bottom)
            base.insert(.top)
          }

          if flickDirection.contains(.bottom) {
            base.remove(.top)
            base.insert(.bottom)
          }

          if flickDirection.contains(.right) {
            base.remove(.left)
            base.insert(.right)
          }

          if flickDirection.contains(.left) {
            base.remove(.right)
            base.insert(.left)
          }

          return base
        }

        state.snappingPosition = velocityBasedAnchorPoint ?? locationBasedAnchorPoint

        let fromCenter = Geometry.center(of: frame)
        let toCenter = Geometry.center(of: calculateFrameForFloating(for: state.snappingPosition))

        let delta = CGPoint(
          x: toCenter.x - fromCenter.x,
          y: toCenter.y - fromCenter.y
        )

        var baseVelocity = CGVector(
          dx: gestureVelocity.x / delta.x,
          dy: gestureVelocity.y / delta.y
        )

        baseVelocity.dx = baseVelocity.dx.isFinite ? baseVelocity.dx : 0
        baseVelocity.dy = baseVelocity.dy.isFinite ? baseVelocity.dy : 0

        let animator = UIViewPropertyAnimator(
          duration: 0.8,
          timingParameters: UISpringTimingParameters(
            dampingRatio: 0.8,
            initialVelocity: baseVelocity
          )
        )

        animator.addAnimations {
          self.containerView.center = toCenter
        }

        animator.startAnimation()

      @unknown default:
        assertionFailure()
      }
    }
  }

}
