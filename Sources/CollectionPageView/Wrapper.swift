import Combine
import SwiftUI

public struct PageView<Cell: View, Value: Hashable>: View where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    @Binding var selected: Value

    let page: (Value) -> Cell

    var ignoreSafeArea: Bool

    public init(selected: Binding<Value>,
                page: @escaping (Value) -> Cell,
                ignoreSafeArea: Bool = true) {
        self._selected = selected
        self.page = page
        self.ignoreSafeArea = ignoreSafeArea
    }

    public var body: some View {
        if self.ignoreSafeArea {
            GeometryReader { proxy in
                PageViewWrapper(selected: self.$selected, cell: { value in
                    self.page(value)
                        .safeAreaInset(edge: .bottom, spacing: 0, content: { Color.clear.frame(height: proxy.safeAreaInsets.bottom) })
                        .safeAreaInset(edge: .top, spacing: 0, content: { Color.clear.frame(height: proxy.safeAreaInsets.top) })
                        .safeAreaInset(edge: .leading, spacing: 0, content: { Color.clear.frame(width: proxy.safeAreaInsets.leading) })
                        .safeAreaInset(edge: .trailing, spacing: 0, content: { Color.clear.frame(width: proxy.safeAreaInsets.trailing) })
                        .ignoresSafeArea()
                })
                .ignoresSafeArea()
            }
        } else {
            PageViewWrapper(selected: self.$selected, cell: { value in
                self.page(value)
            })
        }
    }
}

struct PageViewWrapper<Cell: View, Value: Hashable>: UIViewRepresentable where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    @Binding var selected: Value

    let cell: (Value) -> Cell

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
        PickerModel(selected: self.$selected)
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
        let hosting = UIHostingController(rootView: content)
        self.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        self.hosting = hosting
        self.addSubview(hosting.view)
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.hosting?.view.frame = self.bounds
    }
}
