//
//  ContentView.swift
//  Example
//
//  Created by Leo Mehlig on 20.11.22.
//

import SwiftUI
import CollectionPageView

class ViewState: ObservableObject {
    @Published var offset: Int = 0
}

struct ContentView: View {
    @State var selected = 0

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
            PageView(selected: $selected) { value in
                PageContent(value: value)
            }
            .environmentObject(state)
//            .padding(.horizontal, CGFloat(selected))
        }
    }
}

struct PageContent: View {
    var value: Int

    @EnvironmentObject var state: ViewState

    var body: some View {
        print("Body", value, state.offset)
        Self._printChanges()
        return VStack {
            Spacer()
            HStack {
                Spacer()
                Text("\(value + state.offset)")
                    .font(.largeTitle.bold())
                Spacer()
            }
            Spacer()
        }
        .background([Color.red, .blue, .green][abs((value + state.offset) % 3)])
    }
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
