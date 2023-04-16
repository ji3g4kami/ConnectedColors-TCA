import ComposableArchitecture
import SwiftUI

@main
struct ConnectedColorsApp: App {
    var body: some Scene {
        WindowGroup {
            ColorSwitchView(store: Store(
                initialState: ColorSwitchState(),
                reducer: colorSwitchReducer,
                environment: ColorSwitchEnvironment(client: .live)
            ))
        }
    }
}
