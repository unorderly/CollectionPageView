import Combine
import SwiftUI
import LogMacro

public struct PageView<Cell: View, Value: Hashable>: View where Value: Comparable, Value: Strideable, Value.Stride == Int, Value: CustomStringConvertible {
    @Binding var selected: Value

    let page: (Value) -> Cell

    var ignoreSafeArea: Bool

    public init(selected: Binding<Value>,
                page: @escaping (Value) -> Cell,
                ignoreSafeArea: Bool = true) {
        #logInfo("PageView init with selected: \(selected.wrappedValue)")
        self._selected = selected
        self.page = page
        self.ignoreSafeArea = ignoreSafeArea
    }

    static var logger: LogMacro.Logger {
        Logger(isPersisted: true, subsystem: Bundle.main.bundleIdentifier ?? "", category: "PageView")
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
        #logInfo("PageViewWrapper init with selected: \(selected.wrappedValue)")
        self._selected = selected
        self.cell = cell
    }

    static var logger: LogMacro.Logger {
        Logger(isPersisted: true, subsystem: Bundle.main.bundleIdentifier ?? "", category: "PageView")
    }

    func updateUIView(_ picker: UIViewType, context: Context) {
        #logInfo("PageViewWrapper updateUIView called")
        picker.configureCell = {
            $0.set(value: self.cell($1))
        }
        #logInfo("PageViewWrapper calling select with value: \(self.selected)")
        picker.select(value: self.selected)
    }

    func makeUIView(context: Context) -> UIViewType {
        #logInfo("PageViewWrapper makeUIView called")
        let picker = UIViewType(selected: self.selected,
                                configureCell: {
            $0.set(value: self.cell($1))
        })
        #logInfo("PageViewWrapper setting up coordinator to listen to picker publisher")
        context.coordinator.listing(to: picker.publisher)
        return picker
    }

    func makeCoordinator() -> PickerModel<Value> {
        #logInfo("PageViewWrapper makeCoordinator called")
        return PickerModel(selected: self.$selected)
    }
}

class PickerModel<Value: Hashable> {
    @Binding var selected: Value

    private var cancallable: AnyCancellable?

    init(selected: Binding<Value>) {
        #logInfo("PickerModel init with selected: \(selected.wrappedValue.hashValue)")
        self._selected = selected
    }

    static var logger: LogMacro.Logger {
        Logger(isPersisted: true, subsystem: Bundle.main.bundleIdentifier ?? "", category: "PageView")
    }

    func listing<P: Publisher>(to publisher: P) where P.Output == Value, P.Failure == Never {
        #logInfo("PickerModel listing to publisher")
        DispatchQueue.main.async {
            #logInfo("PickerModel async setup of publisher binding")
            self.cancallable?.cancel()
            self.cancallable = publisher
                .sink { [weak self] value in
                    #logInfo("PickerModel received value from publisher: \(value.hashValue)")
                    self?.selected = value
                }
        }
    }
}

final class UIHostingView<Content: View>: UIView {
    private var hosting: UIHostingController<Content>?
    static var logger: LogMacro.Logger {
        Logger(isPersisted: true, subsystem: Bundle.main.bundleIdentifier ?? "", category: "PageView")
    }

    func set(value content: Content) {
        #logInfo("UIHostingView set called")

        if let hosting = self.hosting {
            #logInfo("UIHostingView removing existing hosting view")
            hosting.view.removeFromSuperview()
        }

        #logInfo("UIHostingView creating new hosting controller")
        let hosting = UIHostingController(rootView: content)
        self.backgroundColor = .clear
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        self.hosting = hosting

        #logInfo("UIHostingView adding hosting view as subview")
        self.addSubview(hosting.view)
        self.setNeedsLayout()
    }

    override func layoutSubviews() {
        #logInfo("UIHostingView layoutSubviews called")
        super.layoutSubviews()

        if let hostingView = self.hosting?.view {
            #logInfo("UIHostingView updating hosting view frame to: \(self.bounds.width) x \(self.bounds.height)")
            hostingView.frame = self.bounds
        }
    }
}
