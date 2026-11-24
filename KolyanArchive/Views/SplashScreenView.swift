
import SwiftUI

struct SplashScreenView: View {
    @State private var scale: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            Image("SplashScreen")
                .resizable()
                .scaledToFill()
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .clipped()
                .scaleEffect(scale, anchor: .center)
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height
                )
                .background(Color.black)
                .ignoresSafeArea()
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .milliseconds(200))

                        withAnimation(.easeInOut(duration: 0.6)) {
                            scale = 1.22
                        }
                    }
                }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}


struct SplashRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSplash = true
    @State private var splashID = UUID()

    var body: some View {
        ZStack {
            HomeView()

            if showSplash {
                SplashScreenView()
                    .id(splashID)
                    .zIndex(1)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .milliseconds(1400))

                        withAnimation(.easeOut(duration: 0.3)) {
                            showSplash = false
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && !showSplash {
                splashID = UUID()
                showSplash = true
            }
        }
    }
}

