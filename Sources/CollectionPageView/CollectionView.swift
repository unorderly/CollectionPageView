import Combine
import UIKit
import SwiftUI

extension String: InfiniteScollingData { }

class CollectionPageView<Cell: UICollectionViewCell, Value: Strideable>:
    UIView, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource
where Value: Comparable, Value: Strideable, Value.Stride == Int {

    private let selectionFeedback = UISelectionFeedbackGenerator()

    public let publisher: CurrentValueSubject<Value, Never>


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
    
    private var nextValue: Value?
    
    private weak var collectionView: UICollectionView!
    private var bufferSize = 3
    
    private var pages: [Value] {
        var pages = Array(selected.advanced(by: -bufferSize)...selected.advanced(by: bufferSize))
        if let next = self.nextValue, !pages.contains(next) {
            if pages[0] > next {
                pages.removeFirst()
                pages.insert(next, at: 0)
            } else {
                pages.removeLast()
                pages.append(next)
            }
        }
        return pages
    }
    
    init(selected: Value,
         configureCell: @escaping (Cell, Value) -> Void) {
        self.configureCell = configureCell
        self.publisher = CurrentValueSubject(selected)
        self.selected = selected
        super.init(frame: .zero)

        self.backgroundColor = .clear


        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.register(Cell.self, forCellWithReuseIdentifier: "cell")
        self.collectionView = cv
        cv.delaysContentTouches = false
        cv.canCancelContentTouches = true
        cv.delegate = self
        cv.dataSource = self
        cv.isScrollEnabled = true
        cv.showsHorizontalScrollIndicator = false
        cv.showsVerticalScrollIndicator = false
        cv.isPagingEnabled = true
        cv.decelerationRate = UIScrollView.DecelerationRate.normal
        cv.backgroundColor = .clear

        cv.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(cv)
        NSLayoutConstraint.activate([
            cv.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
            cv.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 0),
            cv.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
            cv.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0)
        ])

        self.isAccessibilityElement = false
        self.reload()
    }
    
    func reload() {
        self.collectionView.reloadData()
        self.collectionView.setContentOffset(self.offset(for: self.selected), animated: false)
    }
    
    func offset(for value: Value) -> CGPoint {
        let index = self.pages.firstIndex(of: value) ?? 0
        return .init(x: self.collectionView.bounds.width * CGFloat(index), y: 0)
    }
    
    func select(value: Value) {
        if value != self.selected {
            let isAnimating = self.collectionView.isDragging || self.nextValue != nil
            self.nextValue = value
            self.collectionView.reloadData()
            if !isAnimating {
                self.collectionView.setContentOffset(self.offset(for: value), animated: true)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        DispatchQueue.main.async {
            self.collectionView.collectionViewLayout.invalidateLayout()
            if !self.collectionView.isDragging && self.nextValue == nil {
                self.collectionView.setContentOffset(self.offset(for: self.selected), animated: false)
            }
        }
    }
    

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.pages.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        if let cell = cell as? Cell, self.pages.indices ~= indexPath.item {
            self.configureCell(cell, self.pages[indexPath.item])
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 0
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let size = CGSize(width: self.bounds.size.width, height: self.bounds.size.height)
        return size
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.updateSelected()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        self.updateSelected()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.updateSelected(reload: !self.collectionView.isDecelerating && self.nextValue == nil )
    }
    
    private func updateSelected(reload: Bool = true) {
        let index = Int(round(self.collectionView.contentOffset.x / self.collectionView.bounds.width))
        if self.pages.indices ~= index {
            let old = self.selected
            let new = self.pages[index]
            if old != new && reload {
                self.selected = new
                self.nextValue = nil
                self.collectionView.reloadData()
                let liveOffset: CGFloat
                if self.pages.contains(old) {
                    let oldOffset = self.offset(for: old).x
                    let newOffset = self.offset(for: self.selected).x
                    liveOffset = self.collectionView.contentOffset.x + (oldOffset - newOffset)
                } else {
                    liveOffset = self.offset(for: self.selected).x
                }
                self.collectionView.setContentOffset(.init(x: liveOffset, y: 0), animated: false)
            }
        }
    }
    
}
