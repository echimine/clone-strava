import SwiftUI

extension RootView {
    /// Debug builds only: the splash and celebration preview, reached from the Profile tab.
    static var animationsPreview: AnyView? {
        #if DEBUG
        AnyView(AnimationsPreviewView())
        #else
        nil
        #endif
    }
}
