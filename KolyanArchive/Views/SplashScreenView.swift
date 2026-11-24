
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
                        try? await Task.sleep(for: .milliseconds(500))

                        withAnimation(.easeInOut(duration: 0.8)) {
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
    @State private var showSplash = true

    var body: some View {
        ZStack {
            HomeView()

            if showSplash {
                SplashScreenView()
                    .zIndex(1)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(for: .milliseconds(1900))

                        withAnimation(.easeOut(duration: 0.3)) {
                            showSplash = false
                        }
                    }
            }
        }
        .preferredColorScheme(.dark)
    }
}
