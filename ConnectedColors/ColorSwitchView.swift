import ComposableArchitecture
import SwiftUI

let singletonUUID = UUID()

struct ColorSwitchState: Equatable {
    var connectedPeers: [String] = []
    var currentColor: NamedColor?
}

enum ColorSwitchAction: Equatable {
    case send(NamedColor)
    case onAppear
    case client(PeerClient.Action)
}

struct ColorSwitchEnvironment {
    var client: PeerClient
}

extension ColorSwitchEnvironment {
    static let live = ColorSwitchEnvironment(client: .live)
}

let colorSwitchReducer = Reducer<ColorSwitchState, ColorSwitchAction, ColorSwitchEnvironment> { state, action, env in
    switch action {
    case .send(let newColor):
        state.currentColor = newColor
        return env.client.send(singletonUUID, newColor).fireAndForget()
    case .onAppear:
        return env.client.create(singletonUUID).map {
            .client($0)
        }
    case .client(.updatePeers(let peers)):
        state.connectedPeers = peers
        return .none
    case .client(.updateColor(let newColor)):
        state.currentColor = newColor
        return .none
    }
}


struct ColorSwitchView: View {
    //    @StateObject var colorSession = ColorMultipeerSession()
    let store: Store<ColorSwitchState, ColorSwitchAction>
    
    var body: some View {
        WithViewStore(self.store) { viewStore in
            VStack(alignment: .leading) {
                Text("Connected Devices:")
                    .bold()
                Text(String(describing: viewStore.connectedPeers))
                
                Divider()
                
                HStack {
                    ForEach(NamedColor.allCases, id: \.self) { color in
                        Button(color.rawValue) {
                            viewStore.send(.send(color))
                        }
                        .padding()
                    }
                }
                Spacer()
            }
            .padding()
            .background((viewStore.currentColor?.color ?? .clear).ignoresSafeArea())
            .onAppear {
                viewStore.send(.onAppear)
            }
        }
        
    }
}

extension NamedColor {
    var color: Color {
        switch self {
        case .red:
            return .red
        case .green:
            return .green
        case .yellow:
            return .yellow
        }
    }
}

extension ColorSwitchEnvironment {
    static var preview = ColorSwitchEnvironment(client: .preview)
}
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ColorSwitchView(
            store: Store(
                initialState: ColorSwitchState(),
                reducer: colorSwitchReducer,
                environment: .preview
            )
            
        )
    }
}

