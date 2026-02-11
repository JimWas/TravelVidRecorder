import SwiftUI

struct CalculatorView: View {
    @StateObject private var calculator = CalculatorEngine()

    private let buttonSpacing: CGFloat = 12

    private let buttons: [[CalculatorButton]] = [
        [.clear, .plusMinus, .percent, .divide],
        [.seven, .eight, .nine, .multiply],
        [.four, .five, .six, .subtract],
        [.one, .two, .three, .add],
        [.zero, .decimal, .equals]
    ]

    var body: some View {
        GeometryReader { geometry in
            let buttonWidth = (geometry.size.width - 5 * buttonSpacing) / 4
            let buttonHeight = buttonWidth

            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()

                VStack(spacing: buttonSpacing) {
                    Spacer()

                    // Display
                    HStack {
                        Spacer()
                        Text(calculator.displayValue)
                            .font(.system(size: displayFontSize(for: calculator.displayValue), weight: .light, design: .default))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 8)

                    // Buttons
                    ForEach(buttons.indices, id: \.self) { rowIndex in
                        HStack(spacing: buttonSpacing) {
                            ForEach(buttons[rowIndex], id: \.self) { button in
                                CalculatorButtonView(
                                    button: button,
                                    width: button == .zero ? buttonWidth * 2 + buttonSpacing : buttonWidth,
                                    height: buttonHeight,
                                    isHighlighted: calculator.currentOperation == button.operation && button.isOperation
                                ) {
                                    calculator.handleButton(button)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, buttonSpacing)
                .padding(.bottom, geometry.safeAreaInsets.bottom + 20)
            }
        }
    }

    private func displayFontSize(for value: String) -> CGFloat {
        let length = value.count
        if length <= 6 {
            return 88
        } else if length <= 9 {
            return 64
        } else {
            return 48
        }
    }
}

// MARK: - Calculator Button Enum
enum CalculatorButton: String, Hashable {
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case decimal = "."
    case equals = "="
    case add = "+"
    case subtract = "-"
    case multiply = "×"
    case divide = "÷"
    case percent = "%"
    case plusMinus = "±"
    case clear = "AC"

    var backgroundColor: Color {
        switch self {
        case .clear, .plusMinus, .percent:
            return Color(white: 0.65)
        case .add, .subtract, .multiply, .divide, .equals:
            return Color.orange
        default:
            return Color(white: 0.2)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .clear, .plusMinus, .percent:
            return .black
        default:
            return .white
        }
    }

    var isOperation: Bool {
        switch self {
        case .add, .subtract, .multiply, .divide:
            return true
        default:
            return false
        }
    }

    var operation: Operation? {
        switch self {
        case .add: return .add
        case .subtract: return .subtract
        case .multiply: return .multiply
        case .divide: return .divide
        default: return nil
        }
    }
}

// MARK: - Calculator Button View
struct CalculatorButtonView: View {
    let button: CalculatorButton
    let width: CGFloat
    let height: CGFloat
    let isHighlighted: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(isHighlighted ? .white : button.backgroundColor)
                    .frame(width: width, height: height)
                    .scaleEffect(isPressed ? 0.95 : 1.0)

                Text(button.rawValue)
                    .font(.system(size: height * 0.4, weight: .medium, design: .default))
                    .foregroundColor(isHighlighted ? button.backgroundColor : button.foregroundColor)
            }
        }
        .buttonStyle(CalculatorButtonStyle(isPressed: $isPressed))
    }
}

struct CalculatorButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = newValue
                }
            }
    }
}

// MARK: - Operation Enum
enum Operation {
    case add, subtract, multiply, divide
}

// MARK: - Calculator Engine
class CalculatorEngine: ObservableObject {
    @Published var displayValue: String = "0"
    @Published var currentOperation: Operation?

    private var currentValue: Double = 0
    private var storedValue: Double = 0
    private var isEnteringNumber = false
    private var hasDecimal = false
    private var justPressedOperation = false
    private var justPressedEquals = false
    private var lastOperation: Operation?
    private var lastOperand: Double = 0

    func handleButton(_ button: CalculatorButton) {
        switch button {
        case .zero, .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
            enterDigit(button.rawValue)
        case .decimal:
            enterDecimal()
        case .clear:
            clear()
        case .plusMinus:
            toggleSign()
        case .percent:
            applyPercent()
        case .add, .subtract, .multiply, .divide:
            setOperation(button.operation!)
        case .equals:
            calculateResult()
        }
    }

    private func enterDigit(_ digit: String) {
        justPressedEquals = false

        if justPressedOperation || !isEnteringNumber {
            displayValue = digit
            isEnteringNumber = true
            justPressedOperation = false
            hasDecimal = false
        } else {
            if displayValue == "0" && digit == "0" {
                return
            }
            if displayValue == "0" {
                displayValue = digit
            } else if displayValue.replacingOccurrences(of: "-", with: "").count < 9 {
                displayValue += digit
            }
        }
        currentValue = Double(displayValue) ?? 0
    }

    private func enterDecimal() {
        justPressedEquals = false

        if justPressedOperation || !isEnteringNumber {
            displayValue = "0."
            isEnteringNumber = true
            hasDecimal = true
            justPressedOperation = false
        } else if !hasDecimal {
            displayValue += "."
            hasDecimal = true
        }
    }

    private func clear() {
        displayValue = "0"
        currentValue = 0
        storedValue = 0
        currentOperation = nil
        isEnteringNumber = false
        hasDecimal = false
        justPressedOperation = false
        justPressedEquals = false
        lastOperation = nil
        lastOperand = 0
    }

    private func toggleSign() {
        if displayValue == "0" { return }

        if displayValue.hasPrefix("-") {
            displayValue = String(displayValue.dropFirst())
        } else {
            displayValue = "-" + displayValue
        }
        currentValue = Double(displayValue) ?? 0
    }

    private func applyPercent() {
        currentValue = currentValue / 100
        updateDisplay(currentValue)
    }

    private func setOperation(_ operation: Operation) {
        justPressedEquals = false

        if isEnteringNumber && currentOperation != nil && !justPressedOperation {
            performCalculation()
        } else {
            storedValue = currentValue
        }

        currentOperation = operation
        justPressedOperation = true
        isEnteringNumber = false
    }

    private func calculateResult() {
        if justPressedEquals, let lastOp = lastOperation {
            currentValue = calculate(storedValue: currentValue, operation: lastOp, operand: lastOperand)
            updateDisplay(currentValue)
            return
        }

        if let operation = currentOperation {
            lastOperation = operation
            lastOperand = currentValue
            performCalculation()
        }

        currentOperation = nil
        justPressedOperation = false
        isEnteringNumber = false
        justPressedEquals = true
    }

    private func performCalculation() {
        guard let operation = currentOperation else { return }

        let result = calculate(storedValue: storedValue, operation: operation, operand: currentValue)
        updateDisplay(result)
        storedValue = result
        currentValue = result
    }

    private func calculate(storedValue: Double, operation: Operation, operand: Double) -> Double {
        switch operation {
        case .add:
            return storedValue + operand
        case .subtract:
            return storedValue - operand
        case .multiply:
            return storedValue * operand
        case .divide:
            if operand == 0 {
                return 0 // Prevent division by zero
            }
            return storedValue / operand
        }
    }

    private func updateDisplay(_ value: Double) {
        if value.isNaN || value.isInfinite {
            displayValue = "Error"
            return
        }

        // Check if it's a whole number
        if value.truncatingRemainder(dividingBy: 1) == 0 && abs(value) < 1e9 {
            displayValue = String(format: "%.0f", value)
        } else {
            // Format with up to 8 decimal places, removing trailing zeros
            let formatted = String(format: "%.8f", value)
            if formatted.contains(".") {
                var result = formatted
                while result.last == "0" {
                    result.removeLast()
                }
                if result.last == "." {
                    result.removeLast()
                }
                displayValue = result
            } else {
                displayValue = formatted
            }
        }

        // Limit display length
        if displayValue.count > 9 {
            if abs(value) >= 1e9 || abs(value) < 1e-6 {
                displayValue = String(format: "%.3e", value)
            } else {
                displayValue = String(displayValue.prefix(9))
            }
        }

        currentValue = value
    }
}

#Preview {
    CalculatorView()
}
