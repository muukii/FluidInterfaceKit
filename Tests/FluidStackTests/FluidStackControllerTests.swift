import Foundation
import XCTest

@testable import FluidStack

@MainActor
final class FluidStackControllerTests: XCTestCase {

  func testStackTree() {

    let stack = FluidStackController()

    let rep: ViewControllerRep = stack.makeRepresentation()

    let result = rep.compare(
      expectation: ViewControllerRep(
        pointer: Unmanaged.passUnretained(stack),
        view: ViewRep(
          pointer: nil,
          subviews: {

            ViewRep(
              pointer: nil,
              subviews: {

              }
            )

          }
        ),
        children: {

        }
      )
    )

    XCTAssertEqual(result.result, true)
  }

  func testAddingRemovingDefaultBehavior() {

    let stack = FluidStackController()

    XCTAssertEqual(stack.stackingViewControllers.count, 0)

    stack.addContentViewController(UIViewController(), transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)

    stack.addContentViewController(UIViewController(), transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 2)

    stack.removeLastViewController(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)

    stack.removeLastViewController(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)
  }

  func testAddingRemovingIncludingRoot() {

    let stack = FluidStackController(configuration: .init(retainsRootViewController: false))

    XCTAssertEqual(stack.stackingViewControllers.count, 0)

    stack.addContentViewController(UIViewController(), transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)

    stack.addContentViewController(UIViewController(), transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 2)

    stack.removeLastViewController(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)

    // won't remove root view controller
    stack.removeLastViewController(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 0)
  }

  func testRemoving2() {

    let stack = FluidStackController()

    _ = VC(stack) {
      VC(.init()) {}
      VC(.init()) {}
      VC(.init()) {}
      VC(.init()) {}
      VC(.init()) {}
    }

    XCTAssertEqual(stack.stackingViewControllers.count, 5)

    stack.removeLastViewController(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 4)
  }

  func testFindContext() {

    let controller = UIViewController()

    let instance = VC(FluidStackController()) {
      VC(.init()) {
        VC(.init()) {
          VC(controller) {

          }
        }
      }
    }

    XCTAssertNotNil(controller.fluidStackContext)

    withExtendedLifetime(instance, {})

  }

  func testFindStackByIdentifier() {

    let controller = UIViewController()

    _ = VC(FluidStackController(identifier: .init("1"))) {
      VC(.init()) {
        VC(FluidStackController(identifier: .init("2"))) {
          VC(.init()) {
            VC(.init()) {
              VC(.init()) {

              }
            }
          }
        }
        VC(.init()) {
          VC(FluidStackController(identifier: .init("3"))) {
            VC(.init()) {
              VC(.init()) {
                VC(controller) {

                }
              }
            }
          }
        }
      }
    }

    XCTAssertNotNil(controller.fluidStackController(with: .identifier(.init("1"))))
    XCTAssertNotNil(controller.fluidStackController(with: .identifier(.init("3"))))
    XCTAssertNil(controller.fluidStackController(with: .identifier(.init("2"))))

  }

  /**
   UINavigationController retains root view controller
   */
  func testNavigation() {

    let n = UINavigationController()

    XCTAssertEqual(n.viewControllers.count, 0)

    n.pushViewController(.init(), animated: false)
    n.pushViewController(.init(), animated: false)

    XCTAssertEqual(n.viewControllers.count, 2)

    n.popViewController(animated: false)

    XCTAssertEqual(n.viewControllers.count, 1)

    n.popViewController(animated: false)

    XCTAssertEqual(n.viewControllers.count, 1)

  }

  func testRemovingRecursively_1() {

    let dispatcher = UIViewController()

    let stack = FluidStackController()

    _ = VC(stack) {
      VC(.init()) {
      }
      VC(.init()) {
        VC(FluidStackController()) {
          VC(dispatcher) {}
        }
      }
    }

    XCTAssertEqual(stack.stackingViewControllers.count, 2)

    // forwards to parent stack
    dispatcher.fluidPop(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)
  }

  func testRemovingRecursively_2() {

    let dispatcher = UIViewController()

    let stack = FluidStackController()

    _ = VC(stack) {
      VC(.init()) {
        VC(FluidStackController()) {
          VC(dispatcher) {}
        }
      }
    }

    XCTAssertEqual(stack.stackingViewControllers.count, 1)

    // forwards to parent stack
    dispatcher.fluidPop(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)
  }

  func testRemovingRecursively_3() {

    let dispatcher = UIViewController()

    let stack = FluidStackController()

    _ = VC(stack) {
      VC(.init()) {}
      VC(.init()) {
        VC(FluidStackController()) {
          VC(.init()) {}
          VC(dispatcher) {}
        }
      }
    }

    XCTAssertEqual(stack.stackingViewControllers.count, 2)

    // forwards to parent stack
    dispatcher.fluidPop(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 2)
  }

  func testRemovingRecursively_4() {

    let dispatcher1 = UIViewController()
    let dispatcher2 = UIViewController()

    let stack1 = FluidStackController(identifier: .init("1"))
    let stack2 = FluidStackController(identifier: .init("2"))
    let stack3 = FluidStackController(identifier: .init("3"))

    _ = VC(stack1) {
      VC(.init()) {}
      VC(.init()) {
        VC(stack2) {
          VC(.init()) {
            VC(stack3) {
              VC(dispatcher2) {}
              VC(dispatcher1) {}
            }
          }
        }
      }
      VC(.init()) {}  // would be removed by match-removing
    }

    XCTAssertEqual(stack1.stackingViewControllers.count, 3)
    XCTAssertEqual(stack2.stackingViewControllers.count, 1)
    XCTAssertEqual(stack3.stackingViewControllers.count, 2)

    dispatcher1.fluidPop(transition: .disabled)

    // 2 -> 1
    XCTAssertEqual(stack3.stackingViewControllers.count, 1)

    // forwards to parent stack
    dispatcher2.fluidPop(transition: .disabled, transitionForBatch: .disabled)

    XCTAssertEqual(stack1.stackingViewControllers.count, 1)

  }

  func testRemovingRecursively_5() {

    let dispatcher1 = UIViewController()

    let stack1 = FluidStackController()
    let stack2 = FluidStackController(configuration: .init(preventsFowardingPop: true))

    _ = VC(stack1) {
      VC(.init()) {}
      VC(.init()) {
        VC(stack2) {
          VC(dispatcher1) {}
        }
      }
      VC(.init()) {}
    }

    XCTAssertEqual(stack1.stackingViewControllers.count, 3)
    XCTAssertEqual(stack2.stackingViewControllers.count, 1)

    dispatcher1.fluidPop(transition: .disabled)

    XCTAssertEqual(stack2.stackingViewControllers.count, 1)

    XCTAssertEqual(stack1.stackingViewControllers.count, 3)

  }

  func testAddingDuplicated() {

    let content1 = UIViewController()
    let content2 = UIViewController()
    let stack1 = FluidStackController()

    stack1.addContentViewController(content1, transition: .disabled)
    stack1.addContentViewController(content1, transition: .disabled)
    stack1.addContentViewController(content1, transition: .disabled)

    XCTAssertEqual(stack1.stackingViewControllers.count, 1)

    stack1.addContentViewController(content2, transition: .disabled)
    stack1.addContentViewController(content1, transition: .disabled)

    XCTAssertEqual(stack1.stackingViewControllers.count, 2)
  }

  func testOffload_1() {

    let stack = FluidStackController()

    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .opaque), transition: .disabled)

    XCTAssertEqual(
      stack.stackingItems.map { $0.isLoaded },
      [
        false,
        false,
        false,
        false,
        true,
      ]
    )

    stack.removeLastViewController(transition: .disabled)

    XCTAssertEqual(
      stack.stackingItems.map { $0.isLoaded },
      [
        true,
        true,
        true,
        true,
      ]
    )

  }

  func testOffload_2() {

    let stack = FluidStackController()

    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .opaque), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)

    XCTAssertEqual(
      stack.stackingItems.map { $0.isLoaded },
      [
        false,
        false,
        true,
        true,
        true,
      ]
    )

  }

  func testOffload_3() {

    let stack = FluidStackController()

    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .opaque), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .overlay), transition: .disabled)
    stack.addContentViewController(ContentTypeOption(contentType: .opaque), transition: .disabled)

    XCTAssertEqual(
      stack.stackingItems.map { $0.isLoaded },
      [
        false,
        false,
        false,
        false,
        false,
        true,
      ]
    )

  }

  func testPopInStack() {

    let stack = FluidStackController(configuration: .init(retainsRootViewController: false))

    XCTAssertEqual(stack.stackingViewControllers.count, 0)

    let controller = UIViewController()

    stack.addContentViewController(controller, transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 1)

    stack.topViewController!.fluidPop(transition: .disabled)

    XCTAssertEqual(stack.stackingViewControllers.count, 0)

  }

  func testPropagationActions_push_pop() {

    let stack = FluidStackController(configuration: .init(retainsRootViewController: false))

    let childStack = FluidStackController(configuration: .init(retainsRootViewController: false))

    let childExp = expectation(description: "child")

    childStack.addFluidStackActionHandler { action in

      if case .willPush = action {
        // child will get an event that happens in the higher layer.
        childExp.fulfill()
      }

    }

    let expWillPop = expectation(description: "called")
    expWillPop.expectedFulfillmentCount = 1
    
    let expDidPop = expectation(description: "called")
    expDidPop.expectedFulfillmentCount = 1

    let controller = FluidWrapperViewController(content: .init(bodyViewController: childStack))
    controller.addFluidStackActionHandler { action in
      switch action {
      case .willPush:
        break
      case .willPop:
        expWillPop.fulfill()
      case .didPush:
        break
      case .didPop:
        expDidPop.fulfill()
      }
    }

    let wrapper = FluidWrapperViewController(content: .init(bodyViewController: controller))

    stack.fluidPush(
      wrapper.fluidWrapped(configuration: .defaultModal),
      target: .current,
      relation: .modality
    )

    stack.topViewController?.fluidPop()

    wait(for: [expWillPop, expDidPop, childExp], timeout: 1)
  }

  func testPropagationActions_willBecomeTop() {

    let stack = FluidStackController(configuration: .init(retainsRootViewController: false))

    let expWillBecomeTop = expectation(description: "called")
    expWillBecomeTop.expectedFulfillmentCount = 2

    let controller_1 = FluidViewController()
    controller_1.addFluidStackActionHandler { action in
      switch action {
      case .willPush:
        expWillBecomeTop.fulfill()
      case .willPop:
        break
      case .didPush:
        break
      case .didPop:
        break
      }
    }

    stack.fluidPush(
      controller_1,
      target: .current,
      relation: .modality
    )

    let controller_2 = FluidViewController()

    stack.fluidPush(
      controller_2,
      target: .current,
      relation: .modality
    )

    controller_2.fluidPop()

    wait(for: [expWillBecomeTop], timeout: 1)
  }

  func test_fluidPush_make_parent_tree_immediately() {

    let stack = FluidStackController(configuration: .init(retainsRootViewController: false))
    let controller = UIViewController()

    stack.fluidPush(
      controller.fluidWrapped(configuration: .defaultModal),
      target: .current,
      relation: .modality
    )

    XCTAssertNotNil(controller.parent)
  }

  @MainActor
  func test_fluidPop_dereference_viewcontroller() async {

    let stack = FluidStackController(configuration: .init(retainsRootViewController: false))

    var controller: UIViewController! = UIViewController()
    weak var ref = controller

    stack.fluidPush(
      controller.fluidWrapped(configuration: .defaultModal),
      target: .current,
      relation: .modality,
      transition: .disabled,
      completion: nil
    )

    controller.fluidPop(completion: nil)
    controller = nil

    try! await Task.sleep(nanoseconds: 1_000_000_000)

    XCTAssertNil(ref)

  }

  final class ContentTypeOption: UIViewController {
    init(contentType: FluidStackContentConfiguration.ContentType) {
      super.init(nibName: nil, bundle: nil)
      self.fluidStackContentConfiguration.contentType = contentType
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
}
