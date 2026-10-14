import Combine
import LogMacro
import SwiftUI

public struct PageView<Cell: View, Value: Hashable>: View where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    @Binding var selected: Value

    let page: (Value) -> Cell

    var ignoreSafeArea: Bool
    /// Pages re-render when this changes even if their frame doesn't, e.g. for values the page closure captures.
    var updateKey: AnyHashable?

    public init(selected: Binding<Value>,
                page: @escaping (Value) -> Cell,
                ignoreSafeArea: Bool = true,
                updateKey: AnyHashable? = nil) {
        self._selected = selected
        self.page = page
        self.ignoreSafeArea = ignoreSafeArea
        self.updateKey = updateKey
    }

    public var body: some View {
        if self.ignoreSafeArea {
            GeometryReader { proxy in
                let insets = proxy.safeAreaInsets
                // The pages capture the insets, so they must re-render when the insets change without the frame
                // changing, e.g. when a vertical bar moves to the other edge.
                PageViewWrapper(selected: self.$selected,
                                updateKey: [self.updateKey, [insets.top, insets.leading, insets.bottom, insets.trailing]],
                                cell: { value in
                                    self.page(value)
                                        .safeAreaPadding(insets)
                                        .ignoresSafeArea()
                                })
                                .ignoresSafeArea()
            }
        } else {
            PageViewWrapper(selected: self.$selected, updateKey: self.updateKey, cell: { value in
                self.page(value)
            })
        }
    }
}

struct PageViewWrapper<Cell: View, Value: Hashable>: UIViewRepresentable where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    @Binding var selected: Value

    let updateKey: AnyHashable?
    let cell: (Value) -> Cell

    typealias UIViewType = ScrollPageView<UIHostingView<Cell>, Value>

    init(selected: Binding<Value>,
         updateKey: AnyHashable?,
         cell: @escaping (Value) -> Cell) {
        self._selected = selected
        self.updateKey = updateKey
        self.cell = cell
    }

    func updateUIView(_ picker: UIViewType, context: Context) {
        picker.configureCell = {
            $0.set(value: self.cell($1), key: self.updateKey)
        }
        picker.select(value: self.selected)
        picker.updateCells {
            $0.updateIfNeeded(value: self.cell($1), key: self.updateKey)
        }
    }

    func makeUIView(context: Context) -> UIViewType {
        let picker = UIViewType(selected: self.selected,
                                configureCell: {
                                    $0.set(value: self.cell($1), key: self.updateKey)
                                })
        context.coordinator.listing(to: picker.publisher)
        return picker
    }

    func makeCoordinator() -> PickerModel<Value> {
        PickerModel(selected: self.$selected)
    }
}

class PickerModel<Value: Hashable> {
    @Binding var selected: Value

    private var cancellable: AnyCancellable?

    init(selected: Binding<Value>) {
        self._selected = selected
    }

    func listing<P: Publisher>(to publisher: P) where P.Output == Value, P.Failure == Never {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.cancellable?.cancel()
            self.cancellable = publisher
                .sink { [weak self] value in
                    self?.selected = value
                }
        }
    }
}

final class UIHostingView<Content: View>: UIView {
    private var hosting: UIHostingController<Content>?
    private var lastFrame: CGRect?
    private var lastKey: AnyHashable?

    func set(value content: Content, key: AnyHashable? = nil) {
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
        self.lastKey = key
    }

    /// Only updates when the frame or the key changed, since the content captures the values it depends on and
    /// re-rendering every page on every update is costly.
    func updateIfNeeded(value content: Content, key: AnyHashable? = nil) {
        if self.lastFrame != self.bounds || self.lastKey != key {
            self.hosting?.rootView = content
            self.lastFrame = self.bounds
            self.lastKey = key
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if let hostingView = self.hosting?.view {
            hostingView.frame = self.bounds
        }
    }
}
