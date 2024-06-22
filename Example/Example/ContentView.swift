import CollectionPageView
import SwiftUI

class ViewState: ObservableObject {
    @Published var offset: Int = 0
}

struct ContentView: View {
    @State private var selected = 0

    @StateObject var state = ViewState()
    var body: some View {
        VStack {
            HStack {
                Button("-20") {
                    self.selected = -20
                }
                Button("<", action: {
                    self.selected -= 1
                })
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                Text("Selected: \(self.selected)")
                Button("Random") {
                    self.selected = (-100...100).randomElement() ?? 0
                }
                Button(">", action: {
                    self.selected += 1
                })
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button("20") {
                    self.selected = 20
                }
            }
            HStack {
                Button("Decrease Offset") {
                    self.state.offset -= 1
                }
                Button("Increase Offset") {
                    self.state.offset += 1
                }
            }
            PageView(selected: self.$selected) { value in
                PageContent(value: value)
            }
            .environmentObject(self.state)
            //            .padding(.horizontal, CGFloat(selected))
        }
    }
}

struct PageContent: View {
    var value: Int

    @EnvironmentObject private var state: ViewState

    var body: some View {
        Self._printChanges()
        return VStack {
            Spacer()
            HStack {
                Spacer()
                Text("\(self.value + self.state.offset)")
                    .font(.largeTitle.bold())
                Spacer()
            }
            Spacer()
        }
        .background([Color.red, .blue, .green][abs((self.value + self.state.offset) % 3)])
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
