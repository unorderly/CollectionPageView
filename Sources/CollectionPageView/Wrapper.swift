import Combine
import LogMacro
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
                        .safeAreaPadding(proxy.safeAreaInsets)
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
        picker.configureCell = {
            $0.set(value: self.cell($1))
        }
        picker.select(value: self.selected)
        picker.updateCells {
            $0.updateIfNeeded(value: self.cell($1))
        }
    }

    func makeUIView(context: Context) -> UIViewType {
        let picker = UIViewType(selected: self.selected,
                                configureCell: {
                                    $0.set(value: self.cell($1))
                                })
        context.coordinator.listing(to: picker.publisher)
        return picker
    }

    func makeCoordinator() -> PickerModel<Value> {
        return PickerModel(selected: self.$selected)
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
                .sink { [weak self] value in
                    self?.selected = value
                }
        }
    }
}

final class UIHostingView<Content: View>: UIView {
    private var hosting: UIHostingController<Content>?
    private var lastFrame: CGRect?

    func set(value content: Content) {
        if let hosting = self.hosting {
            hosting.view.removeFromSuperview()
        }

        let hosting = UIHostingController(rootView: content)
        self.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        self.hosting = hosting

        self.addSubview(hosting.view)
        self.setNeedsLayout()
        self.lastFrame = self.bounds
    }

    /// Only updating if the frame changed, since the only case we found is if we resize the window in collapsed timeline mode.
    func updateIfNeeded(value content: Content) {
        if self.lastFrame != self.bounds {
            self.hosting?.rootView = content
            self.lastFrame = self.bounds
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let hostingView = self.hosting?.view {
            hostingView.frame = self.bounds
        }
    }
}
