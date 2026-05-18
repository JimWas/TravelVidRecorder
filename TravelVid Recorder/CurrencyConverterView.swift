import SwiftUI

struct CurrencyConverterView: View {
    @Binding var amountText: String
    @Binding var base: CurrencyConverterBase
    let isPreview: Bool

    private let usdToVndRate: Double = 25_400

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.16, blue: 0.13),
                    Color(red: 0.05, green: 0.11, blue: 0.10),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: isPreview ? 14 : 18) {
                header
                amountCard
                resultCard
                rateCard
                Spacer(minLength: isPreview ? 0 : 24)
            }
            .padding(isPreview ? 16 : 20)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Currency")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.7))
                Text("Converter")
                    .font(.system(size: isPreview ? 24 : 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Spacer()

            if !isPreview {
                Button {
                    swapDirection()
                } label: {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(red: 0.36, green: 0.92, blue: 0.65))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You Send")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.65))

            HStack(alignment: .bottom, spacing: 12) {
                Text(sourceCurrency.symbol)
                    .font(.system(size: isPreview ? 26 : 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                if isPreview {
                    Text(formattedSourceAmount)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer()

                currencyBadge(sourceCurrency.code)
            }
        }
        .padding(isPreview ? 16 : 18)
        .background(cardBackground)
    }

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("They Receive")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.65))

            HStack(alignment: .bottom, spacing: 12) {
                Text(targetCurrency.symbol)
                    .font(.system(size: isPreview ? 26 : 32, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.36, green: 0.92, blue: 0.65))

                Text(formattedConvertedAmount)
                    .font(.system(size: isPreview ? 30 : 36, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.36, green: 0.92, blue: 0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer()

                currencyBadge(targetCurrency.code)
            }
        }
        .padding(isPreview ? 16 : 18)
        .background(cardBackground)
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Rate")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                if !isPreview {
                    Text("Offline")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.yellow)
                }
            }

            Text(rateSummary)
                .font(.system(size: isPreview ? 16 : 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            if !isPreview {
                Text("Reference estimate for quick travel budgeting.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .padding(isPreview ? 14 : 16)
        .background(cardBackground)
    }

    private func currencyBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private var parsedAmount: Double {
        let normalized = amountText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized) ?? 0
    }

    private var sourceCurrency: CurrencyPresentation {
        switch base {
        case .usdToVnd:
            return CurrencyPresentation(code: "USD", symbol: "$")
        case .vndToUsd:
            return CurrencyPresentation(code: "VND", symbol: "d")
        }
    }

    private var targetCurrency: CurrencyPresentation {
        switch base {
        case .usdToVnd:
            return CurrencyPresentation(code: "VND", symbol: "d")
        case .vndToUsd:
            return CurrencyPresentation(code: "USD", symbol: "$")
        }
    }

    private var convertedAmount: Double {
        switch base {
        case .usdToVnd:
            return parsedAmount * usdToVndRate
        case .vndToUsd:
            guard usdToVndRate != 0 else { return 0 }
            return parsedAmount / usdToVndRate
        }
    }

    private var formattedSourceAmount: String {
        format(value: parsedAmount, currency: sourceCurrency.code)
    }

    private var formattedConvertedAmount: String {
        format(value: convertedAmount, currency: targetCurrency.code)
    }

    private var rateSummary: String {
        switch base {
        case .usdToVnd:
            return "1 USD = \(format(value: usdToVndRate, currency: "VND"))"
        case .vndToUsd:
            return "1 VND = \(format(value: 1 / usdToVndRate, currency: "USD"))"
        }
    }

    private func format(value: Double, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency == "USD" ? 2 : 0
        formatter.minimumFractionDigits = currency == "USD" ? 2 : 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func swapDirection() {
        base = base == .usdToVnd ? .vndToUsd : .usdToVnd
    }
}

private struct CurrencyPresentation {
    let code: String
    let symbol: String
}
