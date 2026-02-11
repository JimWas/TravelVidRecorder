import SwiftUI

struct FakeCallingView: View {
    let contactName: String
    @State private var isMuted = false
    @State private var isSpeaker = false

    var body: some View {
        ZStack {
            // Background gradient with blur effect
            LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.22, blue: 0.20),
                    Color(red: 0.12, green: 0.12, blue: 0.12),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                // Top info section
                VStack(spacing: 16) {
                    // Status
                    Text("Calling...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    // Contact name/number
                    Text(contactName)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)

                    // Info icon
                    Image(systemName: "info.circle")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                // Control buttons grid
                VStack(spacing: 30) {
                    // Row 1
                    HStack(spacing: 60) {
                        CallButton(
                            icon: isMuted ? "mic.slash.fill" : "mic.fill",
                            label: "mute",
                            isActive: isMuted
                        ) {
                            isMuted.toggle()
                        }

                        CallButton(
                            icon: "circle.grid.3x3.fill",
                            label: "keypad",
                            isActive: false
                        ) {}

                        CallButton(
                            icon: isSpeaker ? "speaker.wave.3.fill" : "speaker.fill",
                            label: "audio",
                            isActive: isSpeaker
                        ) {
                            isSpeaker.toggle()
                        }
                    }

                    // Row 2
                    HStack(spacing: 60) {
                        CallButton(
                            icon: "plus",
                            label: "add call",
                            isActive: false
                        ) {}

                        CallButton(
                            icon: "video.fill",
                            label: "FaceTime",
                            isActive: false
                        ) {}

                        CallButton(
                            icon: "person.fill",
                            label: "contacts",
                            isActive: false
                        ) {}
                    }
                }
                .padding(.bottom, 40)

                // End call button
                VStack {
                    ZStack {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.23, blue: 0.19))
                            .frame(width: 75, height: 75)

                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 50)
            }
        }
    }
}

struct CallButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.white : Color.white.opacity(0.15))
                        .frame(width: 68, height: 68)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(isActive ? .black : .white)
                }
            }
            .buttonStyle(PlainButtonStyle())

            Text(label)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.white)
                .textCase(.none)
        }
    }
}
