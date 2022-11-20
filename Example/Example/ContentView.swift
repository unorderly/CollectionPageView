//
//  ContentView.swift
//  Example
//
//  Created by Leo Mehlig on 20.11.22.
//

import SwiftUI
import CollectionPageView

struct ContentView: View {
    @State var selected = 0
    var body: some View {
        VStack {
            HStack {
                Button("-20") {
                    self.selected = -20
                }
                Button("<", action: {
                    self.selected -= 1
                })
                Text("Selected: \(self.selected)")
                Button("Random") {
                    self.selected = (-100...100).randomElement() ?? 0
                }
                Button(">", action: {
                    self.selected += 1
                })
                
                Button("20") {
                    self.selected = 20
                }
            }
            PageView(selected: $selected) { value in
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(value)")
                            .font(.largeTitle.bold())
                        Spacer()
                    }
                    Spacer()
                }
                .background([Color.red, .blue, .green][abs(value % 3)])
            }
            .padding(.horizontal, CGFloat(selected))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
