import SwiftUI

struct LEDBannerView: View {
    let text: String
    let useNasalization: Bool
    let speed: Double
    let isPreview: Bool

    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private let spacing: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let displayText = normalizedText

            ZStack {
                Color.black

                if textSize.width <= geo.size.width || isPreview {
                    bannerText(displayText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    HStack(spacing: spacing) {
                        bannerText(displayText)
                        bannerText(displayText)
                    }
                    .offset(x: offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipped()
                    .onAppear {
                        containerWidth = geo.size.width
                        startMarquee()
                    }
                    .onChange(of: textSize) {
                        containerWidth = geo.size.width
                        startMarquee()
                    }
                    .onChange(of: displayText) {
                        containerWidth = geo.size.width
                        startMarquee()
                    }
                }
            }
            .onAppear {
                containerWidth = geo.size.width
            }
        }
        .readSize { size in
            // Track container size for initial layout.
            containerWidth = size.width
        }
    }

    private func bannerText(_ value: String) -> some View {
        Text(value)
            .font(ledFont)
            .foregroundColor(.green)
            .shadow(color: .green.opacity(0.6), radius: 6, x: 0, y: 0)
            .shadow(color: .green.opacity(0.4), radius: 12, x: 0, y: 0)
            .lineLimit(1)
            .fixedSize()
            .readSize { size in
                textSize = size
            }
            .padding(.horizontal, 12)
    }

    private var ledFont: Font {
        let size: CGFloat = isPreview ? 48 : 64
        if useNasalization, UIFont(name: "Nasalization", size: size) != nil {
            return .custom("Nasalization", size: size)
        }
        return .system(size: size, weight: .bold, design: .monospaced)
    }

    private var normalizedText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "LED BANNER"
        }
        return trimmed.uppercased()
    }

    private func startMarquee() {
        let distance = textSize.width + spacing
        guard distance > 0 else { return }
        let pointsPerSecond = max(10, speed)
        let duration = Double(distance / pointsPerSecond)

        offset = 0
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -distance
        }
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension View {
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(SizePreferenceKey.self, perform: onChange)
    }
}
