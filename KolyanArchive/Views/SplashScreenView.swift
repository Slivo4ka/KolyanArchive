
import SwiftUI

struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.88
    @State private var isVisible = true

    var body: some View {
        ZStack {
            if isVisible {
                Image("SplashScreen")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .scaleEffect(scale)
                    .transition(.opacity)
                    .onAppear {
                        withAnimation(.easeOut(duration: 1.25)) {
                            scale = 1.04
                        }
                    }
            }
        }
        .background(Color.black)
    }
}

struct SplashRootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            HomeView()

            if showSplash {
                SplashScreenView()
                    .zIndex(1)
                    .task {
                        try? await Task.sleep(for: .seconds(1.5))

                        withAnimation(.easeOut(duration: 0.35)) {
                            showSplash = false
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }
}
