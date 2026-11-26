import SwiftUI

struct SplashRootView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var showSplash = true
    @State private var splashID = UUID()
    @State private var backgroundEnteredAt: Date? = nil

    var body: some View {
        ZStack {
            HomeView()

            if showSplash {
                SplashScreenView()
                    .id(splashID)
                    .zIndex(1)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .milliseconds(950))

                        withAnimation(.easeOut(duration: 0.2)) {
                            showSplash = false
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in

            if newPhase == .background {
                backgroundEnteredAt = Date()
            }

            if newPhase == .active,
               let backgroundDate = backgroundEnteredAt {

                let elapsedTime = Date().timeIntervalSince(backgroundDate)

                backgroundEnteredAt = nil

                if elapsedTime >= 30 {
                    splashID = UUID()

                    withAnimation(.easeIn(duration: 0.2)) {
                        showSplash = true
                    }
                }
            }
        }
    }
}
