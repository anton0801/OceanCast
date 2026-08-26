import SwiftUI
import UIKit

#Preview {
    NotificationOfferView()
        .environment(NotificationService())
        .environment(AppFlow())
}

struct NotificationOfferView: View {
    @Environment(NotificationService.self) private var notifications
    @Environment(AppFlow.self) private var flow
    @State private var isWorking = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                OceanBackground()
                
                Image("custom screeen")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .opacity(0.85)
                
                if geo.size.width < geo.size.height {
                    screenInfo
                } else {
                    screenInfoSecond
                }
            }
        }
        .ignoresSafeArea()
    }
    
    private var screenInfo: some View {
        VStack(spacing: 22) {
            Spacer()
            
            VStack(spacing: 10) {
                Text("АLLОW NОTIFICATIОNS ABOUT\nBОNUSЕS АND PRОMОS")
                    .font(OceanFont.display(22))
                    .foregroundColor(.white)
                Text("Stаy tunеd with bеst оffеrs from\nоur cаsinо")
                    .font(OceanFont.caption(15))
                    .foregroundColor(.white.opacity(0.9))
            }
            .multilineTextAlignment(.center)
            
            VStack(spacing: 6) {
                CustomOceanButtonAccept {
                    Task { await accept() }
                }
                CustomOceanButtonSkip {
                    skip()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
    
    private var screenInfoSecond: some View {
        VStack(spacing: 12) {
            Spacer()
            
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 5) {
                    Text("АLLОW NОTIFICATIОNS ABOUT\nBОNUSЕS АND PRОMОS")
                        .font(OceanFont.display(22))
                        .foregroundColor(.white)
                    Text("Stаy tunеd with bеst оffеrs from оur cаsinо")
                        .font(OceanFont.caption(17))
                        .foregroundColor(.white.opacity(0.9))
                }
                .multilineTextAlignment(.leading)
                
                Spacer()
                
                VStack(spacing: 6) {
                    CustomOceanButtonAccept {
                        Task { await accept() }
                    }
                    CustomOceanButtonSkip {
                        skip()
                    }
                }
                Spacer()
            }
            .padding(.bottom, 24)
            
        }
    }

    private func accept() async {
        isWorking = true
        let u = await notifications.requestPermission()
        NotificationOffer.markSettled()
        if u {
            UIApplication.shared.registerForRemoteNotifications()
        }
        isWorking = false
        flow.advanceToAccepted()
    }

    private func skip() {
        NotificationOffer.registerSkip()
        flow.advanceToAccepted()
    }
}

struct CustomOceanButtonAccept: View {

    var action: () -> Void
    
    var buttonWidth: CGFloat = 300
    var buttonHeight: CGFloat = 60
    
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image("custom button img")
                .resizable()
                .frame(width: buttonWidth, height: buttonHeight)
        }
    }
}

struct CustomOceanButtonSkip: View {
    
    var action: () -> Void
    
    var buttonWidth: CGFloat = 280
    var buttonHeight: CGFloat = 35

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image("custom button image 2")
                .resizable()
                .frame(width: buttonWidth, height: buttonHeight)
        }
    }
}
