import SwiftUI

struct SplashView: View {
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OceanBackground()
                
                Image("loading screen bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .opacity(0.1)
                    .blur(radius: 9.4)
                
                VStack(spacing: 20) {
                    FloatDisc(symbol: "drop.fill", tint: Ocean.blue, size: 84)
                        .scaleEffect(breathe ? 1.05 : 0.95)
                        .animation(OceanMotion.drift, value: breathe)
                    Text("Ocean Cast")
                        .font(OceanFont.display(28))
                        .foregroundStyle(Ocean.ink)
                    Text("Load app content…")
                        .font(OceanFont.body(15))
                        .foregroundStyle(Ocean.inkSoft)
                    ProgressView().tint(Ocean.blue).padding(.top, 4)
                }
                .padding(24)
            }
            .onAppear { breathe = true }
        }
        .ignoresSafeArea()
        
    }
}

#Preview {
    SplashView()
}
