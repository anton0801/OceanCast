import SwiftUI

struct NoConnectionView: View {
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                OceanBackground(tint: Ocean.coral)
                    .ignoresSafeArea()
                
                Color.black
                    .opacity(0.7)
                    .ignoresSafeArea()
                
                Image("loading screen bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .opacity(0.75)
                    .blur(radius: 3.4)
                
                VStack(spacing: 18) {
                    FloatDisc(symbol: "wifi.slash", tint: Ocean.coral, size: 78)
                    
                    Image("custom error block")
                        .resizable()
                        .frame(width: 230, height: 230)
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Ocean.foam.ignoresSafeArea())
            .contentShape(Rectangle())
            .onTapGesture { }
            .accessibilityAddTraits(.isModal)
        }
        .ignoresSafeArea()
        
    }
    
}

#Preview {
    NoConnectionView()
}
