import SwiftUI

extension EnvironmentValues {
    /// The app's shared GPS source (ADR-027). `nil` in previews: maps show no puck.
    @Entry var locationProvider: (any LocationProvider)?
}
