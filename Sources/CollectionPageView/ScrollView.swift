import Combine
import os.log
import UIKit

import LogMacro

class ScrollPageView<Cell: UIView, Value: Hashable>:
    UIScrollView, UIScrollViewDelegate
where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    let publisher: CurrentValueSubject<Value, Never>

    private var selected: Value {
        didSet {
            #logInfo("selected changed from \(oldValue) to \(self.selected)")
            if oldValue != self.selected {
                #logInfo("selected value different, sending to publisher")
                DispatchQueue.main.async {
                    #logInfo("async sending selected value: \(self.selected)")
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

    static var logger: LogMacro.Logger {
        Logger(isPersisted: true, subsystem: Bundle.main.bundleIdentifier ?? "", category: "PageView")
    }

    private func updatePages() {
        #logInfo("updatePages called with centerPage: \(self.centerPage)")
        #logInfo("updatePages nextValue: \(String(describing: self.nextValue))")

        if let next = self.nextValue, next != self.centerPage {
            #logInfo("updatePages: nextValue exists and differs from centerPage")
            if self.centerPage > next {
                #logInfo("updatePages: centerPage > next")
                self.pages = Array(next.advanced(by: -self.bufferSize + 1)...next)
                + Array(self.centerPage...self.centerPage.advanced(by: self.bufferSize))
            } else {
                #logInfo("updatePages: centerPage <= next")
                self.pages = Array(self.centerPage.advanced(by: -self.bufferSize)...self.centerPage)
                + Array(next...next.advanced(by: self.bufferSize - 1))
            }
        } else {
            #logInfo("updatePages: using default page range")
            self.pages = Array(self.centerPage.advanced(by: -self.bufferSize)...self.centerPage.advanced(by: self.bufferSize))
        }
        #logInfo("updatePages: new pages count: \(self.pages.count)")
    }

    init(selected: Value,
         configureCell: @escaping (Cell, Value) -> Void) {
        #logInfo("ScrollPageView init with selected: \(selected)")
        self.configureCell = configureCell
        self.publisher = CurrentValueSubject(selected)
        self.selected = selected
        self.centerPage = selected
        super.init(frame: .zero)
        #logInfo("ScrollPageView setting up scrollView properties")
        self.showsHorizontalScrollIndicator = false
        self.showsVerticalScrollIndicator = false
        self.scrollsToTop = false
        self.isPagingEnabled = true
        self.backgroundColor = .clear
        self.delegate = self
        #logInfo("ScrollPageView calling updatePages")
        self.updatePages()
        #logInfo("ScrollPageView calling updateViews")
        self.updateViews()
        #logInfo("ScrollPageView setting initial contentOffset")
        self.contentOffset = self.offset(for: self.selected)
    }

    var animator: UIViewPropertyAnimator?
    func select(value: Value) {
        #logInfo("select called with value: \(value)")
        #logInfo("select current selected: \(self.selected), nextValue: \(String(describing: self.nextValue))")


        if value != self.nextValue, self.selected != value || self.nextValue != nil {
            guard self.bounds.width > 0 else {
                #logInfo("select called but bounds.width <= 0. Setting select from \(self.selected) to \(value) and returning")
                self.selected = value
                return
            }
            
            #logInfo("select: value differs from current selection or nextValue exists")
            self.nextValue = value
            #logInfo("select: set nextValue to \(value)")

            DispatchQueue.main.async {
                #logInfo("select: async sending value to publisher: \(value)")
                self.publisher.send(value)
            }

            if let animator = animator, animator.isRunning {
                #logInfo("select: stopping running animator")
                animator.stopAnimation(true)
            }

            #logInfo("select: calling updatePages")
            self.updatePages()
            #logInfo("select: calling updateViews")
            self.updateViews()

            #logInfo("select: creating new animator")
            let animator = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut)
            animator.addAnimations {
                #logInfo("select: animation setting contentOffset")
                self.setContentOffset(self.offset(for: value), animated: false)
            }
            animator.addCompletion { position in
                #logInfo("select: animation completed with position: \(position.rawValue)")
                self.updateSelection(force: true)
                self.ensurePaging()
                self.recenter(force: true)
            }
            #logInfo("select: starting animation")
            animator.startAnimation()
            self.animator = animator
        } else {
            #logInfo("select: no change needed, value already selected or pending")
        }
    }

    func createPlaceholderView() -> UIView {
        #logInfo("createPlaceholderView called")
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        return view
    }

    func updateViews() {
        #logInfo("updateViews called")
        #logInfo("updateViews: current views count: \(self.views.count), pages count: \(self.pages.count)")

        var (reusableCells, reusablePlaceholders) = self.views.filter { !self.pages.contains($0.key) }.values
            .compactMapSplit { $0 as? Cell }

        #logInfo("updateViews: reusableCells count: \(reusableCells.count), reusablePlaceholders count: \(reusablePlaceholders.count)")

        var updated: [Value: UIView] = [:]
        for value in self.pages {
            #logInfo("updateViews: processing page value: \(value)")

            if let existing = self.views[value] {
                #logInfo("updateViews: found existing view for value: \(value)")

                if !self.isViewVisible(for: value), let cell = existing as? Cell {
                    #logInfo("updateViews: view not visible, replacing with placeholder")
                    let new: UIView
                    if let reused = reusablePlaceholders.popLast() {
                        #logInfo("updateViews: reusing placeholder")
                        new = reused
                    } else {
                        #logInfo("updateViews: creating new placeholder")
                        new = self.createPlaceholderView()
                        self.addSubview(new)
                    }
                    updated[value] = new
                    reusableCells.append(cell)
                } else {
                    #logInfo("updateViews: keeping existing view")
                    updated[value] = existing
                }
            } else {
                #logInfo("updateViews: no existing view for value: \(value)")

                if self.isViewVisible(for: value) {
                    #logInfo("updateViews: value is visible, creating cell")
                    let new: Cell
                    if let reused = reusableCells.popLast() {
                        #logInfo("updateViews: reusing cell")
                        new = reused
                    } else {
                        #logInfo("updateViews: creating new cell")
                        new = Cell(frame: .zero)
                        self.addSubview(new)
                    }
                    #logInfo("updateViews: configuring cell")
                    self.configureCell(new, value)
                    updated[value] = new
                } else {
                    #logInfo("updateViews: value not visible, creating placeholder")
                    let new: UIView
                    if let reused = reusablePlaceholders.popLast() {
                        #logInfo("updateViews: reusing placeholder")
                        new = reused
                    } else {
                        #logInfo("updateViews: creating new placeholder")
                        new = self.createPlaceholderView()
                        self.addSubview(new)
                    }
                    updated[value] = new
                }
            }
        }

        #logInfo("updateViews: removing unused cells: \(reusableCells.count)")
        for reusableCell in reusableCells {
            reusableCell.removeFromSuperview()
        }

        #logInfo("updateViews: removing unused placeholders: \(reusablePlaceholders.count)")
        for reusablePlaceholder in reusablePlaceholders {
            reusablePlaceholder.removeFromSuperview()
        }

        #logInfo("updateViews: updating views dictionary with \(updated.count) entries")
        self.views = updated
        #logInfo("updateViews: setting forceRelayout to true")
        self.forceRelayout = true
        self.setNeedsLayout()
    }

    func isViewVisible(for value: Value) -> Bool {
        #logInfo("isViewVisible called for value: \(value)")

        if value == self.selected || value == self.nextValue {
            #logInfo("isViewVisible: value is selected or nextValue, returning true")
            return true
        } else {
            let offset = self.offset(for: value).x
            let threshold: CGFloat = min(2, self.bounds.width)
            let viewBounds = (self.contentOffset.x + threshold)..<(self.contentOffset.x + self.bounds.width - threshold)
            let result = viewBounds.overlaps(offset..<offset + self.bounds.width)
            #logInfo("isViewVisible: checking bounds overlap, result: \(result)")
            return result
        }
    }

    func index(for value: Value) -> Int {
        #logInfo("index called for value: \(value)")
        let result = self.pages.firstIndex(of: value) ?? 0
        #logInfo("index result: \(result)")
        return result
    }

    func offset(for value: Value) -> CGPoint {
        #logInfo("offset called for value: \(value)")
        let index = self.index(for: value)
        let result = CGPoint(x: self.bounds.width * CGFloat(index), y: 0)
        #logInfo("offset result: \(result.x), \(result.y)")
        return result
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var oldSize = CGSize.zero
    var forceRelayout = false

    var hasActiveScroll: Bool {
        #logInfo("hasActiveScroll called")
        if #available(iOS 17.4, *), self.isScrollAnimating {
            #logInfo("hasActiveScroll: isScrollAnimating true")
            return true
        } else {
            let result = self.isDragging || self.isTracking || self.isDecelerating
            #logInfo("hasActiveScroll: isDragging: \(self.isDragging), isTracking: \(self.isTracking), isDecelerating: \(self.isDecelerating)")
            return result
        }
    }

    override func layoutSubviews() {
        #logInfo("layoutSubviews called")
        #logInfo("layoutSubviews: bounds: \(self.bounds.size.width) x \(self.bounds.size.height)")
        #logInfo("layoutSubviews: contentOffset: \(self.contentOffset.x), \(self.contentOffset.y)")

        super.layoutSubviews()
        var contentOffset: CGFloat = self.contentOffset.x
        if self.oldSize != self.bounds.size || self.forceRelayout {
            #logInfo("layoutSubviews: size changed or forceRelayout")
            self.forceRelayout = false
            var oldOffset = self.contentOffset.x

            // UIScrollView rounds the contentOffset sometimes, which can lead to `isViewVisible` reporting wrong views because of rounding errors when the view is resizing.
            // We fix this, by using the real contentOffset of the visible page, incase we are not currently animating.
            let oldSelectedOffset = self.oldSize.width * CGFloat(self.index(for: self.selected))
            #logInfo("layoutSubviews: oldOffset: \(oldOffset), oldSelectedOffset: \(oldSelectedOffset)")

            if abs(oldOffset - oldSelectedOffset) < 1, !self.hasActiveScroll {
                #logInfo("layoutSubviews: adjusting oldOffset to oldSelectedOffset")
                oldOffset = oldSelectedOffset
            }

            #logInfo("layoutSubviews: updating contentSize")
            self.contentSize = CGSize(width: self.bounds.width * CGFloat(self.views.count),
                                      height: self.bounds.height)

            #logInfo("layoutSubviews: updating view frames")
            for (index, value) in self.pages.enumerated() {
                let offset = CGPoint(x: self.bounds.width * CGFloat(index),
                                     y: 0)
                self.views[value]?.frame = CGRect(origin: offset, size: self.bounds.size)
            }

            if self.oldSize.width <= 0 {
                #logInfo("layoutSubviews: oldSize width <= 0, using selected offset")
                contentOffset = self.offset(for: self.selected).x
            } else {
                #logInfo("layoutSubviews: calculating new contentOffset")
                contentOffset = oldOffset / self.oldSize.width * self.bounds.width
            }
            #logInfo("layoutSubviews: setting contentOffset.x to \(contentOffset)")
            self.contentOffset.x = contentOffset
            #logInfo("layoutSubviews: updating oldSize to \(self.bounds.size.width) x \(self.bounds.size.height)")
            self.oldSize = self.bounds.size
        }

        #logInfo("layoutSubviews: calling updateSelection")
        self.updateSelection()
        #logInfo("layoutSubviews: calling recenter")
        self.recenter()
        #logInfo("layoutSubviews: calling checkVisible")
        self.checkVisible()

        if self.traitCollection.layoutDirection == .rightToLeft {
            #logInfo("layoutSubviews: applying RTL transform")
            self.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
            self.subviews.forEach { $0.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi)) }
        }
    }

    func checkVisible() {
        #logInfo("checkVisible called")

        for value in self.pages {
            #logInfo("checkVisible: checking value: \(value)")
            if self.isViewVisible(for: value), let oldView = self.views[value], !(oldView is Cell) {
                #logInfo("checkVisible: replacing placeholder with cell for value: \(value)")
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
        #logInfo("updateSelection called with force: \(force)")

        guard self.bounds.width > 0 else {
            #logInfo("updateSelection: bounds width <= 0, returning")
            self.nextValue = nil
            return
        }

        let offset = self.offset(for: self.selected).x
        #logInfo("updateSelection: selected offset: \(offset), contentOffset: \(self.contentOffset.x)")

        guard force
                || self.contentOffset.x <= offset - self.bounds.width
                || self.contentOffset.x >= offset + self.bounds.width
        else {
            #logInfo("updateSelection: no update needed, returning")
            return
        }

        let index = Int(round(self.contentOffset.x / self.bounds.width))
        #logInfo("updateSelection: calculated index: \(index)")

        if self.pages.indices ~= index {
            #logInfo("updateSelection: index is valid")
            if self.nextValue == nil || self.nextValue == self.pages[index] {
                #logInfo("updateSelection: updating selection to \(self.pages[index])")
                self.nextValue = nil
                self.selected = self.pages[index]
            }
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        #logInfo("scrollViewWillBeginDragging called")

        if self.isDecelerating {
            #logInfo("scrollViewWillBeginDragging: isDecelerating, forcing recenter")
            self.recenter(force: true)
        }
        #logInfo("scrollViewWillBeginDragging: clearing nextValue")
        self.nextValue = nil
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        #logInfo("scrollViewDidEndDecelerating called")

        #logInfo("scrollViewDidEndDecelerating: forcing updateSelection")
        self.updateSelection(force: true)
        #logInfo("scrollViewDidEndDecelerating: calling ensurePaging")
        self.ensurePaging()
        #logInfo("scrollViewDidEndDecelerating: forcing recenter")
        self.recenter(force: true)
    }

    func ensurePaging() {
        #logInfo("ensurePaging called")

        let selectedOffset = self.offset(for: self.selected).x
        #logInfo("ensurePaging: contentOffset: \(self.contentOffset.x), selectedOffset: \(selectedOffset)")

        if abs(self.contentOffset.x - selectedOffset) > 1 {
            #logInfo("ensurePaging: adjusting contentOffset to \(selectedOffset)")
            self.contentOffset.x = selectedOffset
        }
    }

    func recenter(force: Bool = false) {
        #logInfo("recenter called with force: \(force)")

        guard self.bounds.width > 0 else {
            #logInfo("recenter: bounds width <= 0, returning")
            return
        }

        let centerOffset = self.offset(for: self.centerPage)
        let selectedOffset = self.offset(for: self.selected)
        #logInfo("recenter: centerOffset: \(centerOffset.x), selectedOffset: \(selectedOffset.x)")
        #logInfo("recenter: centerPage: \(self.centerPage), selected: \(self.selected)")

        if (!self.isDecelerating && abs(centerOffset.x - selectedOffset.x) / self.bounds.width >= CGFloat(self.bufferSize))
            || (force && self.centerPage != self.selected) {
            #logInfo("recenter: recentering needed")
            #logInfo("recenter: updating centerPage from \(self.centerPage) to \(self.selected)")
            self.centerPage = self.selected
            #logInfo("recenter: calling updatePages")
            self.updatePages()

            let newOffset = self.offset(for: self.selected)
            #logInfo("recenter: newOffset: \(newOffset.x)")
            #logInfo("recenter: adjusting contentOffset from \(self.contentOffset.x) to \(self.contentOffset.x + (newOffset.x - selectedOffset.x))")
            self.contentOffset.x = self.contentOffset.x + (newOffset.x - selectedOffset.x)
            #logInfo("recenter: calling updateViews")
            self.updateViews()
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        #logInfo("gestureRecognizerShouldBegin called")

        if gestureRecognizer.view is ScrollPageView
            && gestureRecognizer == self.panGestureRecognizer
            && gestureRecognizer.numberOfTouches == 3 {
            #logInfo("gestureRecognizerShouldBegin: blocking 3-finger pan gesture")
            return false
        }

        let result = super.gestureRecognizerShouldBegin(gestureRecognizer)
        #logInfo("gestureRecognizerShouldBegin: returning \(result)")
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
