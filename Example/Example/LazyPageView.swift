import SwiftUI
import UIKit

struct LazyPageView<Content: View>: UIViewControllerRepresentable {
    @Binding var current: Int

    let content: (Int) -> Content

    init(selected: Binding<Int>,
         @ViewBuilder page: @escaping (Int) -> Content) {
        _current = selected
        self.content = page
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(page: self.$current,
                    content: self.content)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<LazyPageView<Content>>)
    -> UIPageViewController {
        let controller = BuglessPageViewController(transitionStyle: .scroll,
                                                   navigationOrientation: .horizontal)

        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        context.coordinator.set(current: self.current,
                                in: controller,
                                layoutDirection: context.environment.layoutDirection)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController,
                                context: UIViewControllerRepresentableContext<LazyPageView<Content>>) {
        context.coordinator.set(current: self.current,
                                in: controller,
                                layoutDirection: context.environment.layoutDirection)
    }

    class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource, BuglessPageViewControllerDelegate {
        typealias Controller = TaggedHostingController<Content, Int>

        @Binding var page: Int

        let content: (Int) -> Content

        init(page: Binding<Int>, content: @escaping (Int) -> Content) {
            _page = page
            self.content = content
        }

        func set(current: Int, in controller: UIPageViewController, layoutDirection: LayoutDirection) {
            if let controller = controller.viewControllers?.first as? Controller,
               controller.tag == current {
                controller.rootView = self.content(current)
            } else {
                let oldTag = (controller.viewControllers?.first as? Controller)?.tag ?? 0
                let direction: UIPageViewController.NavigationDirection = if layoutDirection == .leftToRight {
                    oldTag < current ? .forward : .reverse
                } else {
                    oldTag < current ? .reverse : .forward
                }
                controller.setViewControllers([
                    Controller(rootView: self.content(current), tag: current)
                ],
                direction: direction,
                animated: true)
            }
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating _: Bool,
                                previousViewControllers previous: [UIViewController],
                                transitionCompleted completed: Bool) {
            if let controller = pageViewController.viewControllers?.first as? Controller {
                self.fixDropTargets(for: pageViewController.viewControllers ?? [])
                self.page = controller.tag
            }
        }

        func fixDropTargets(for controllers: [UIViewController]) {
            for controller in controllers {
                if let tagged = controller as? Controller {
                    tagged.applyDropTargetFix = true
                }
            }
        }

        func pageViewController(_: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            if let index = (viewController as? Controller)?.tag {
                return Controller(rootView: self.content(index - 1), tag: index - 1)
            }
            return nil
        }

        func pageViewController(_: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            if let index = (viewController as? Controller)?.tag {
                return Controller(rootView: self.content(index + 1), tag: index + 1)
            }
            return nil
        }
    }
}

class TaggedHostingController<Content: View, Tag: CustomStringConvertible>: UIHostingController<Content> {
    var tag: Tag

    var applyDropTargetFix = false

    init(rootView: Content, tag: Tag) {
        self.tag = tag
        super.init(rootView: rootView)
        view.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var debugDescription: String {
        "TaggedHostingController: \(self.tag)"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if self.applyDropTargetFix {
            self.applyDropTargetFix = false
            if let interactions = self.view.interactions.compactMap({ $0 as? UIDropInteraction }).first {
                let contextKey = "context"
                if interactions.responds(to: Selector((contextKey))), interactions.value(forKey: contextKey) != nil {
                    self.view.isUserInteractionEnabled = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.view.isUserInteractionEnabled = true
                    }
                }
            }
        }
    }
}

extension UIPageViewController {
    var scrollView: UIScrollView! {
        for view in view.subviews {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
        }
        return nil
    }
}

protocol BuglessPageViewControllerDelegate: UIPageViewControllerDelegate {
    func fixDropTargets(for controllers: [UIViewController])
}

// WORKAROUND: Fixes a bug, where dragging to the side of the page view would move the page and the next page would be empty: https://developer.apple.com/forums/thread/89396
class BuglessPageViewController: UIPageViewController, UIScrollViewDelegate {
    private var preventScrollBug = true

    override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.delegate = self
    }

    override func setViewControllers(_ viewControllers: [UIViewController]?, direction: UIPageViewController.NavigationDirection, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        if self.isViewLoaded {
            self.preventScrollBug = false
        }
        super.setViewControllers(viewControllers, direction: direction, animated: animated) { completed in
            self.preventScrollBug = true
            if completion != nil {
                completion!(completed)
            }
            (self.delegate as? BuglessPageViewControllerDelegate)?.fixDropTargets(for: viewControllers ?? [])
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.preventScrollBug = false
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if self.preventScrollBug {
            scrollView.setContentOffset(CGPoint(x: view.frame.width, y: 0), animated: false)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.preventScrollBug = true
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.preventScrollBug = true
    }
}
