#if os(macOS)
import AppKit
import SwiftUI

struct PageViewWrapper<Cell: View, Value: Hashable>: NSViewControllerRepresentable where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    @Binding var selected: Value

    let cell: (Value) -> Cell

    func makeCoordinator() -> Coordinator {
        Coordinator(selected: self.$selected, cell: self.cell)
    }

    func makeNSViewController(context: Context) -> NSPageController {
        let pageController = NSPageController()
        pageController.view = NSView()
        pageController.view.wantsLayer = true
        pageController.transitionStyle = .horizontalStrip
        pageController.delegate = context.coordinator
        context.coordinator.environmentValues = context.environment
        context.coordinator.reloadArrangedObjects(in: pageController, around: self.selected)
        return pageController
    }

    func updateNSViewController(_ pageController: NSPageController, context: Context) {
        context.coordinator.cell = self.cell
        context.coordinator.environmentValues = context.environment
        context.coordinator.refreshCachedViews()
        guard context.coordinator.selectedValue(in: pageController) != self.selected else {
            return
        }
        context.coordinator.go(to: self.selected,
                               in: pageController,
                               animated: context.transaction.animation != nil)
    }
}

extension PageViewWrapper {
    final class Coordinator: NSObject, NSPageControllerDelegate {
        @Binding var selected: Value

        var cell: (Value) -> Cell
        var environmentValues: EnvironmentValues?
        private var viewCache: [Value: HostingView] = [:]
        private let arrangedObjectLimit = 3

        init(selected: Binding<Value>, cell: @escaping (Value) -> Cell) {
            self._selected = selected
            self.cell = cell
        }

        func pageController(_ pageController: NSPageController,
                            identifierFor object: Any) -> NSPageController.ObjectIdentifier {
            .container
        }

        func pageController(_ pageController: NSPageController,
                            viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
            let viewController = ContainerViewController()
            viewController.coordinator = self
            return viewController
        }

        func pageController(_ pageController: NSPageController,
                            prepare viewController: NSViewController,
                            with object: Any?) {
            guard let viewController = viewController as? ContainerViewController,
                  let value = object as? Value else {
                return
            }
            viewController.prepare(value)
        }

        func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
            pageController.completeTransition()
            self.selected = self.selectedValue(in: pageController) ?? self.selected
        }

        func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
            guard let value = object as? Value else {
                return
            }
            self.selected = value

            let firstValue = pageController.arrangedObjects.first as? Value
            let lastValue = pageController.arrangedObjects.last as? Value
            if value == firstValue || value == lastValue {
                self.reloadArrangedObjects(in: pageController, around: value)
            }
        }

        func refreshCachedViews() {
            for (value, view) in self.viewCache {
                view.rootView = self.rootView(for: value)
            }
        }

        func selectedValue(in pageController: NSPageController) -> Value? {
            guard let selectedController = pageController.selectedViewController as? ContainerViewController else {
                return pageController.arrangedObjects[safe: pageController.selectedIndex] as? Value
            }
            return selectedController.representedValue
        }

        func go(to value: Value, in pageController: NSPageController, animated: Bool = false) {
            let (arrangedObjects, selectedIndex) = self.makeArrangedObjects(around: value)
            pageController.arrangedObjects = arrangedObjects
            self.flushViewCache(in: pageController)

            if animated {
                NSAnimationContext.runAnimationGroup { _ in
                    pageController.animator().selectedIndex = selectedIndex
                } completionHandler: {
                    pageController.completeTransition()
                }
            } else {
                pageController.selectedIndex = selectedIndex
            }
        }

        func reloadArrangedObjects(in pageController: NSPageController, around value: Value) {
            let (arrangedObjects, selectedIndex) = self.makeArrangedObjects(around: value)
            pageController.arrangedObjects = arrangedObjects
            pageController.selectedIndex = selectedIndex
            self.flushViewCache(in: pageController)
        }

        func makeArrangedObjects(around value: Value, limit: Int? = nil) -> ([Any], Int) {
            let actualLimit = limit ?? self.arrangedObjectLimit

            var previousObjects: [Value] = []
            var previousValue = value
            while previousObjects.count < actualLimit {
                let candidate = previousValue.advanced(by: -1)
                previousObjects.insert(candidate, at: 0)
                previousValue = candidate
            }

            var nextObjects: [Value] = [value]
            var nextValue = value
            while nextObjects.count <= actualLimit {
                let candidate = nextValue.advanced(by: 1)
                nextObjects.append(candidate)
                nextValue = candidate
            }

            return (previousObjects + nextObjects, previousObjects.count)
        }

        func makeView(for value: Value) -> HostingView {
            if let cached = self.viewCache[value] {
                cached.rootView = self.rootView(for: value)
                return cached
            }

            let view = HostingView(rootView: self.rootView(for: value))
            self.viewCache[value] = view
            return view
        }

        private func rootView(for value: Value) -> AnyView {
            if let environmentValues = self.environmentValues {
                return AnyView(self.cell(value)
                    .environment(\.self, environmentValues))
            }
            return AnyView(self.cell(value))
        }

        func flushViewCache(in pageController: NSPageController) {
            guard let currentValues = pageController.arrangedObjects as? [Value] else {
                return
            }
            let staleValues = self.viewCache.keys.filter { currentValues.contains($0) == false }
            for value in staleValues {
                self.viewCache.removeValue(forKey: value)
            }
        }
    }

    final class ContainerViewController: NSViewController {
        weak var coordinator: Coordinator?

        override func loadView() {
            self.view = NSView()
            self.view.autoresizingMask = [.width, .height]
        }

        var representedValue: Value? {
            self.representedObject as? Value
        }

        func prepare(_ value: Value) {
            self.representedObject = value

            for subview in self.view.subviews {
                subview.removeFromSuperview()
            }

            guard let contentView = self.coordinator?.makeView(for: value) else {
                return
            }

            contentView.autoresizingMask = [.width, .height]
            contentView.frame = self.view.bounds
            contentView.removeFromSuperview()
            self.view.addSubview(contentView)
        }
    }

    final class HostingView: NSHostingView<AnyView> {
        override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
            true
        }
    }
}

extension NSPageController.ObjectIdentifier {
    static let container = "container"
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        self.indices.contains(index) ? self[index] : nil
    }
}
#endif
