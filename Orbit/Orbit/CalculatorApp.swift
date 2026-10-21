import SwiftUI

/// The calculator's logic, kept separate from the buttons.
@MainActor
final class CalculatorEngine: ObservableObject {
    @Published private(set) var display = "0"
    @Published private(set) var pendingOperator: String?

    private var accumulator: Double?
    private var typing = false
    private var lastOperator: String?
    private var lastOperand: Double?

    var clearTitle: String { typing && display != "0" ? "C" : "AC" }

    private var value: Double { Double(display.replacingOccurrences(of: ",", with: "")) ?? 0 }

    func press(_ key: String) {
        switch key {
        case "0"..."9":
            if typing {
                if display == "0" { display = key }
                else if display.filter(\.isNumber).count < 15 { display += key }
            } else {
                display = key
                typing = true
            }
        case ".":
            if !typing { display = "0."; typing = true }
            else if !display.contains(".") { display += "." }
        case "AC":
            display = "0"; accumulator = nil; pendingOperator = nil
            typing = false; lastOperator = nil; lastOperand = nil
        case "C":
            display = "0"; typing = false
        case "±":
            if display.hasPrefix("-") { display.removeFirst() }
            else if display != "0" { display = "-" + display }
        case "%":
            show(value / 100)
            typing = false
        case "+", "−", "×", "÷":
            if typing || accumulator == nil {
                if let acc = accumulator, let op = pendingOperator, typing {
                    let result = apply(acc, op, value)
                    show(result)
                    accumulator = result
                } else {
                    accumulator = value
                }
            }
            pendingOperator = key
            typing = false
        case "=":
            if let acc = accumulator, let op = pendingOperator {
                let operand = typing ? value : acc
                let result = apply(acc, op, operand)
                lastOperator = op
                lastOperand = operand
                show(result)
                accumulator = nil
                pendingOperator = nil
            } else if let op = lastOperator, let operand = lastOperand {
                show(apply(value, op, operand))
            }
            typing = false
        case "⌫":
            guard typing else { return }
            display.removeLast()
            if display.isEmpty || display == "-" { display = "0" }
        default:
            break
        }
    }

    private func apply(_ a: Double, _ op: String, _ b: Double) -> Double {
        switch op {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return b == 0 ? .nan : a / b
        default: return b
        }
    }

    private func show(_ number: Double) {
        guard number.isFinite else { display = "Error"; return }
        if number == number.rounded(), abs(number) < 1e15 {
            display = String(Int64(number))
        } else {
            display = String(format: "%.10g", number)
        }
    }
}

struct CalculatorApp: View {
    @StateObject private var engine = CalculatorEngine()
    @FocusState private var focused: Bool

    private let rows: [[String]] = [
        ["AC", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "="],
    ]

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 10)
            Text(engine.display)
                .font(.system(size: 56, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 8)
                .textSelection(.enabled)

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                ForEach(rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                                .gridCellColumns(key == "0" ? 2 : 1)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Calculator")
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in
            let map: [String: String] = ["*": "×", "x": "×", "/": "÷", "-": "−", "+": "+",
                                         "=": "=", "%": "%", ".": ".", ",": "."]
            let ch = press.characters
            if press.key == .return { engine.press("="); return .handled }
            if press.key == .delete || press.key == .deleteForward { engine.press("⌫"); return .handled }
            if press.key == .escape { engine.press("AC"); return .handled }
            if ch.count == 1, let c = ch.first, c.isNumber { engine.press(ch); return .handled }
            if let mapped = map[ch] { engine.press(mapped); return .handled }
            return .ignored
        }
    }

    private func keyButton(_ key: String) -> some View {
        let isOperator = ["÷", "×", "−", "+", "="].contains(key)
        let isFunction = ["AC", "±", "%"].contains(key)
        let selected = engine.pendingOperator == key
        let label = key == "AC" ? engine.clearTitle : key
        return Button {
            engine.press(label)
        } label: {
            Text(label)
                .font(.system(size: 26, weight: isOperator ? .medium : .regular))
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .background(
                    Capsule().fill(
                        isOperator ? (selected ? Theme.text : Theme.accent)
                            : (isFunction ? Color(hex: 0x3A3D46) : Theme.chip)
                    )
                )
                .foregroundStyle(isOperator ? (selected ? Theme.accent : Theme.background) : Theme.text)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
