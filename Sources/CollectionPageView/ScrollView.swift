import Combine
import UIKit

import LogMacro

class ScrollPageView<Cell: UIView, Value: Hashable>:
    UIScrollView, UIScrollViewDelegate
    where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    let publisher: CurrentValueSubject<Value, Never>

    private var selected: Value {
        didSet {
            if oldValue != self.selected {
                DispatchQueue.main.async {
                    self.publisher.send(self.selected)
                }
            }
        }
    }

    var configureCell: (Cell, Value) -> Void

    private var pages: [Value] = []
    private var nextValue: Value?
    private var bufferSize = 2
    private var views: [Value: UIView] = [:]
    private var centerPage: Value

    private func updatePages() {
        if let next = self.nextValue, next != self.centerPage {
            if self.centerPage > next {
                self.pages = Array(next.advanced(by: -self.bufferSize + 1)...next)
                    + Array(self.centerPage...self.centerPage.advanced(by: self.bufferSize))
            } else {
                self.pages = Array(self.centerPage.advanced(by: -self.bufferSize)...self.centerPage)
                    + Array(next...next.advanced(by: self.bufferSize - 1))
            }
        } else {
            self.pages = Array(self.centerPage.advanced(by: -self.bufferSize)...self.centerPage.advanced(by: self.bufferSize))
        }
    }

    init(selected: Value,
         configureCell: @escaping (Cell, Value) -> Void) {
        self.configureCell = configureCell
        self.publisher = CurrentValueSubject(selected)
        self.selected = selected
        self.centerPage = selected
        super.init(frame: .zero)
        self.showsHorizontalScrollIndicator = false
        self.showsVerticalScrollIndicator = false
        self.scrollsToTop = false
        self.isPagingEnabled = true
        self.backgroundColor = .clear
        self.delegate = self
        self.updatePages()
        self.updateViews()
        self.contentOffset = self.offset(for: self.selected)
    }

    var animator: UIViewPropertyAnimator?
    func select(value: Value) {
        if value != self.nextValue, self.selected != value || self.nextValue != nil {
            guard self.bounds.width > 0 else {
                self.selected = value
                return
            }

            self.nextValue = value

            DispatchQueue.main.async {
                self.publisher.send(value)
            }

            if let animator = animator, animator.isRunning {
                animator.stopAnimation(true)
            }

            self.updatePages()
            self.updateViews()

            let animator = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut)
            animator.addAnimations {
                self.setContentOffset(self.offset(for: value), animated: false)
            }
            animator.addCompletion { position in
                self.updateSelection(force: true)
                self.ensurePaging()
                self.recenter(force: true)
            }
            animator.startAnimation()
            self.animator = animator
        }
    }

    func createPlaceholderView() -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        return view
    }

    func updateViews() {
        var (reusableCells, reusablePlaceholders) = self.views.filter { !self.pages.contains($0.key) }.values
            .compactMapSplit { $0 as? Cell }

        var updated: [Value: UIView] = [:]
        for value in self.pages {
            if let existing = self.views[value] {
                if !self.isViewVisible(for: value), let cell = existing as? Cell {
                    let new: UIView
                    if let reused = reusablePlaceholders.popLast() {
                        new = reused
                    } else {
                        new = self.createPlaceholderView()
                        self.addSubview(new)
                    }
                    updated[value] = new
                    reusableCells.append(cell)
                } else {
                    updated[value] = existing
                }
            } else {
                if self.isViewVisible(for: value) {
                    let new: Cell
                    if let reused = reusableCells.popLast() {
                        new = reused
                    } else {
                        new = Cell(frame: .zero)
                        self.addSubview(new)
                    }

                    self.configureCell(new, value)
                    updated[value] = new
                } else {
                    let new: UIView
                    if let reused = reusablePlaceholders.popLast() {
                        new = reused
                    } else {
                        new = self.createPlaceholderView()
                        self.addSubview(new)
                    }
                    updated[value] = new
                }
            }
        }

        for reusableCell in reusableCells {
            reusableCell.removeFromSuperview()
        }

        for reusablePlaceholder in reusablePlaceholders {
            reusablePlaceholder.removeFromSuperview()
        }

        self.views = updated

        self.forceRelayout = true
        self.setNeedsLayout()
    }

    func isViewVisible(for value: Value) -> Bool {
        if value == self.selected || value == self.nextValue {
            return true
        } else {
            let offset = self.offset(for: value).x
            let threshold: CGFloat = min(2, self.bounds.width)
            let viewBounds = (self.contentOffset.x + threshold)..<(self.contentOffset.x + self.bounds.width - threshold)
            let result = viewBounds.overlaps(offset..<offset + self.bounds.width)
            return result
        }
    }

    func index(for value: Value) -> Int {
        let result = self.pages.firstIndex(of: value) ?? 0
        return result
    }

    func offset(for value: Value) -> CGPoint {
        let index = self.index(for: value)
        let result = CGPoint(x: self.bounds.width * CGFloat(index), y: 0)
        return result
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var oldSize = CGSize.zero
    var forceRelayout = false

    var hasActiveScroll: Bool {
        if #available(iOS 17.4, *), self.isScrollAnimating {
            return true
        } else {
            let result = self.isDragging || self.isTracking || self.isDecelerating
            return result
        }
    }

    override func layoutSubviews() {
       super.layoutSubviews()
        var contentOffset: CGFloat = self.contentOffset.x
        if self.oldSize != self.bounds.size || self.forceRelayout {
            self.forceRelayout = false
            var oldOffset = self.contentOffset.x

            // UIScrollView rounds the contentOffset sometimes, which can lead to `isViewVisible` reporting wrong views because of rounding errors when the view is resizing.
            // We fix this, by using the real contentOffset of the visible page, incase we are not currently animating.
            let oldSelectedOffset = self.oldSize.width * CGFloat(self.index(for: self.selected))
            if abs(oldOffset - oldSelectedOffset) < 1, !self.hasActiveScroll {
                oldOffset = oldSelectedOffset
            }

            self.contentSize = CGSize(width: self.bounds.width * CGFloat(self.views.count),
                                      height: self.bounds.height)

            for (index, value) in self.pages.enumerated() {
                let offset = CGPoint(x: self.bounds.width * CGFloat(index),
                                     y: 0)
                self.views[value]?.frame = CGRect(origin: offset, size: self.bounds.size)
            }

            if self.oldSize.width <= 0 {
                contentOffset = self.offset(for: self.selected).x
            } else {
                contentOffset = oldOffset / self.oldSize.width * self.bounds.width
            }
            self.contentOffset.x = contentOffset
            self.oldSize = self.bounds.size
        }

        self.updateSelection()
        self.recenter()
        self.checkVisible()

        if self.traitCollection.layoutDirection == .rightToLeft {
            self.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
            self.subviews.forEach { $0.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi)) }
        }
    }

    func checkVisible() {
        for value in self.pages {
            if self.isViewVisible(for: value), let oldView = self.views[value], !(oldView is Cell) {
                let cell = Cell(frame: .zero)
                cell.frame = oldView.frame
                self.configureCell(cell, value)
                oldView.removeFromSuperview()
                self.addSubview(cell)
                self.views[value] = cell
            }
        }
    }

    func updateSelection(force: Bool = false) {
        guard self.bounds.width > 0 else {
            self.nextValue = nil
            return
        }

        let offset = self.offset(for: self.selected).x

        guard force
            || self.contentOffset.x <= offset - self.bounds.width
            || self.contentOffset.x >= offset + self.bounds.width
        else {
            return
        }

        let index = Int(round(self.contentOffset.x / self.bounds.width))

        if self.pages.indices ~= index {
            if self.nextValue == nil || self.nextValue == self.pages[index] {
                self.nextValue = nil
                self.selected = self.pages[index]
            }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if self.isDecelerating {
            self.recenter(force: true)
        }
        self.nextValue = nil
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.updateSelection(force: true)
        self.ensurePaging()
        self.recenter(force: true)
    }

    func ensurePaging() {
        let selectedOffset = self.offset(for: self.selected).x

        if abs(self.contentOffset.x - selectedOffset) > 1 {
            self.contentOffset.x = selectedOffset
        }
    }

    func recenter(force: Bool = false) {
        guard self.bounds.width > 0 else {
            return
        }

        let centerOffset = self.offset(for: self.centerPage)
        let selectedOffset = self.offset(for: self.selected)

        if (!self.isDecelerating && abs(centerOffset.x - selectedOffset.x) / self.bounds.width >= CGFloat(self.bufferSize))
            || (force && self.centerPage != self.selected) {
            self.centerPage = self.selected
            self.updatePages()

            let newOffset = self.offset(for: self.selected)
            self.contentOffset.x = self.contentOffset.x + (newOffset.x - selectedOffset.x)
            self.updateViews()
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view is ScrollPageView,
           gestureRecognizer == self.panGestureRecognizer,
           gestureRecognizer.numberOfTouches == 3 {
            return false
        }

        let result = super.gestureRecognizerShouldBegin(gestureRecognizer)
        return result
    }
}

extension Collection {
    func compactMapSplit<ElementOfResult>(_ transform: (Element) throws -> ElementOfResult?) rethrows -> ([ElementOfResult], [Element]) {
        var filtered = [ElementOfResult]()
        var rest = [Element]()
        for element in self {
            if let new = try transform(element) {
                filtered.append(new)
            } else {
                rest.append(element)
            }
        }
        return (filtered, rest)
    }
}
