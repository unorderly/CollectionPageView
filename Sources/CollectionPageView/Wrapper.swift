import Combine
import SwiftUI

public struct PageView<Cell: View, Value: Hashable>: View where Value: Comparable, Value: Strideable, Value.Stride == Int {
    @Binding var selected: Value

    let page: (Value) -> Cell

    public init(selected: Binding<Value>,
                page: @escaping (Value) -> Cell) {
        self._selected = selected
        self.page = page
    }

    public var body: some View {
        PageViewWrapper(selected: $selected, cell: page)
    }
}

struct PageViewWrapper<Cell: View, Value: Hashable>: UIViewRepresentable where Value: Comparable, Value: Strideable, Value.Stride == Int {
    
    @Binding var selected: Value
        
    let cell: (Value) -> Cell
    
//    typealias UIViewType = CollectionPageView<UIHostingCell<Cell>, Value>
        typealias UIViewType = ScrollPageView<UIHostingView<Cell>, Value>
    
    init(selected: Binding<Value>,
         cell: @escaping (Value) -> Cell) {
        self._selected = selected
        self.cell = cell
    }
    
    func updateUIView(_ picker: UIViewType, context: Context) {
        picker.configureCell = { $0.set(value: self.cell($1)) }
        picker.select(value: self.selected)
    }
    
    func makeUIView(context: Context) -> UIViewType {
        let picker = UIViewType(selected: self.selected,
                                configureCell: { $0.set(value: self.cell($1)) })
        context.coordinator.listing(to: picker.publisher)
        return picker
    }
    
    func makeCoordinator() -> PickerModel<Value> {
        PickerModel(selected: $selected)
    }
}

class PickerModel<Value: Hashable> {
    @Binding var selected: Value
    
    private var cancallable: AnyCancellable?
    
    init(selected: Binding<Value>) {
        self._selected = selected
    }
    
    func listing<P: Publisher>(to publisher: P) where P.Output == Value, P.Failure == Never {
        DispatchQueue.main.async {
            self.cancallable?.cancel()
            self.cancallable = publisher
                .assign(to: \.selected, on: self)
        }
    }
}

final class UIHostingView<Content: View>: UIView {
    private var hosting: UIHostingController<Content>?
    
    func set(value content: Content) {
        self.hosting?.view.removeFromSuperview()
        self.hosting = nil
        if let hosting = self.hosting {
            hosting.rootView = content
        } else {
            let hosting = UIHostingController(rootView: content)
            backgroundColor = .clear
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            hosting.view.backgroundColor = .clear
            self.addSubview(hosting.view)
            
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: self.topAnchor, constant: 0),
                hosting.view.leftAnchor.constraint(equalTo: self.leftAnchor, constant: 0),
                hosting.view.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0),
                hosting.view.rightAnchor.constraint(equalTo: self.rightAnchor, constant: 0)
            ])
            self.hosting = hosting
        }
    }
}

final class UIHostingCell<Content: View>: UICollectionViewCell {
    private var hosting: UIHostingController<Content>?
    
    func set(value content: Content) {
        if let hosting = self.hosting {
            hosting.rootView = content
        } else {
            let hosting = UIHostingController(rootView: content)
            
            backgroundColor = .clear
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            hosting.view.backgroundColor = .clear
            //                hosting.view.layer.borderColor = UIColor.green.withAlphaComponent(0.5).cgColor
            //                hosting.view.layer.borderWidth = 2
            self.contentView.addSubview(hosting.view)
            
            NSLayoutConstraint.activate([
                hosting.view.topAnchor
                    .constraint(equalTo: self.contentView.topAnchor, constant: 0),
                hosting.view.leftAnchor
                    .constraint(equalTo: self.contentView.leftAnchor, constant: 0),
                hosting.view.bottomAnchor
                    .constraint(equalTo: self.contentView.bottomAnchor, constant: 0),
                hosting.view.rightAnchor
                    .constraint(equalTo: self.contentView.rightAnchor, constant: 0)
            ])
            self.hosting = hosting
        }
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.hosting?.view.setNeedsUpdateConstraints()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        self.hosting?.view.removeFromSuperview()
        self.hosting = nil
    }
}

