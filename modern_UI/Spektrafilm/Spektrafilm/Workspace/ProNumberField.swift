import AppKit
import SwiftUI

/// One native edit/commit contract for every numeric input. Text is a draft
/// until Return, Tab or focus loss; stepping commits that draft first.
struct ProNumberField: NSViewRepresentable {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var digits = 2
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> ProNumberControl {
        let control = ProNumberControl()
        control.changed = { context.coordinator.parent.value = $0 }
        configure(control)
        return control
    }
    func updateNSView(_ view: ProNumberControl, context: Context) {
        context.coordinator.parent = self
        configure(view)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProNumberControl, context: Context) -> CGSize? {
        CGSize(width: max(54, proposal.width ?? 76), height: 25)
    }
    private func configure(_ view: ProNumberControl) {
        view.configure(title: title, value: value, range: range, step: step, digits: digits, enabled: enabled)
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator {
        var parent: ProNumberField
        init(_ parent: ProNumberField) { self.parent = parent }
    }
}

@MainActor final class ProNumberControl: NSView, NSTextFieldDelegate {
    static weak var activeEditor: ProNumberControl?
    private var editing = false
    private let field = ProEditingTextField()
    private let stepper = NSStepper()
    private let formatter = NumberFormatter()
    private let qualityFormatter = ProQualityFormatter()
    private var value = 0.0
    private var range = 0.0...100.0
    private var step = 1.0
    private var integerOnly = false
    var changed: ((Double) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.owner = self
        field.delegate = self
        field.alignment = .right
        field.bezelStyle = .roundedBezel
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.controlSize = .small
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stepper.controlSize = .small
        stepper.valueWraps = false
        stepper.autorepeat = true
        stepper.target = self
        stepper.action = #selector(stepped)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        addSubview(field); addSubview(stepper)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: NSSize { NSSize(width: 76, height: 25) }
    override func layout() {
        super.layout()
        let stepperSize = stepper.intrinsicContentSize
        let stepperWidth = max(13, stepperSize.width)
        let fieldHeight: CGFloat = 22
        field.frame = NSRect(x:0,y:(bounds.height-fieldHeight)/2,
                             width:max(0,bounds.width-stepperWidth-2),height:fieldHeight)
        stepper.frame = NSRect(x:bounds.width-stepperWidth,y:(bounds.height-stepperSize.height)/2,
                               width:stepperWidth,height:stepperSize.height)
    }

    func configure(title: String, value: Double, range: ClosedRange<Double>, step: Double, digits: Int, enabled: Bool) {
        self.range = range; self.step = step
        formatter.locale = Locale(identifier: Localization.shared.resolved.localeIdentifier)
        formatter.maximumFractionDigits = digits
        integerOnly = digits == 0
        let isQuality = integerOnly && range == 1...100
        if isQuality {
            if field.formatter !== qualityFormatter { field.formatter = qualityFormatter }
        } else if field.formatter != nil { field.formatter = nil }
        field.setAccessibilityLabel(title)
        let increment = step == 1.0/3.0 ? "⅓" : String(format: "%g", step)
        field.toolTip = G("输入数值，回车或点别处提交；Esc 取消。上下箭头每次调整 \(increment)。")
        stepper.setAccessibilityLabel(title + G("增减"))
        stepper.minValue = range.lowerBound; stepper.maxValue = range.upperBound; stepper.increment = step
        if !enabled, field.currentEditor() != nil { window?.makeFirstResponder(nil) }
        field.isEnabled = enabled; stepper.isEnabled = enabled
        if !editing { self.value = value; display(value) }
    }
    private func display(_ value: Double) {
        field.stringValue = formatter.string(from: NSNumber(value: value)) ?? String(value)
        stepper.doubleValue = value
    }
    private func set(_ newValue: Double) {
        let bounded = min(range.upperBound, max(range.lowerBound, newValue))
        guard bounded.isFinite else { display(value); return }
        let previous = value
        value = bounded; display(bounded)
        if abs(previous - bounded) > 0.0000001 { changed?(bounded) }
    }
    private func commit() {
        let decimal = formatter.decimalSeparator ?? "."
        let text = (field.currentEditor()?.string ?? field.stringValue).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: decimal, with: ".")
        guard let number = Double(text), number.isFinite else { display(value); return }
        set(integerOnly ? number.rounded() : number)
    }
    static func endEditing() {
        guard let active = activeEditor else { return }
        activeEditor = nil
        active.commit()
        active.window?.makeFirstResponder(nil)
        active.editing = false
    }
    fileprivate func beganEditing() {
        editing = true; Self.activeEditor = self
        // The shared field editor must obey the same single-line contract as
        // its cell, even while a narrow numeric control is being resized.
        if let editor = field.currentEditor() as? NSTextView {
            editor.textContainer?.maximumNumberOfLines = 1
            editor.textContainer?.lineBreakMode = .byClipping
            editor.isVerticallyResizable = false
        }
    }
    func containsFieldPoint(_ point: NSPoint) -> Bool { field.bounds.contains(field.convert(point, from: nil)) }
    @objc private func stepped() {
        let delta = stepper.doubleValue - value
        Self.endEditing()
        guard abs(delta) > 0.0000001 else { return }
        set(value + (delta > 0 ? step : -step))
    }
    func controlTextDidBeginEditing(_ notification: Notification) { beganEditing() }
    func controlTextDidEndEditing(_ notification: Notification) {
        if Self.activeEditor === self { Self.activeEditor = nil }
        commit(); editing = false
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            window?.makeFirstResponder(nil); return true
        case #selector(NSResponder.cancelOperation(_:)):
            display(value); window?.makeFirstResponder(nil); return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            commit(); set(value + (selector == #selector(NSResponder.moveUp(_:)) ? step : -step))
            field.selectText(nil); return true
        default: return false
        }
    }
}

@MainActor private final class ProEditingTextField: NSTextField {
    weak var owner: ProNumberControl?
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { owner?.beganEditing() }
        return accepted
    }
}

/// Reject excess digits at the edit boundary, including paste. Empty input is
/// allowed while editing; commit restores/clamps to the existing 1…100 contract.
private final class ProQualityFormatter: NumberFormatter, @unchecked Sendable {
    override init() {
        super.init()
        numberStyle = .none
        allowsFloats = false
        usesGroupingSeparator = false
        maximumFractionDigits = 0
        isPartialStringValidationEnabled = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func isPartialStringValid(_ partialString: String,
        newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        partialString.count <= 3 && partialString.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }
}

/// NSButton and SwiftUI glass controls do not all resign a field editor. End
/// editing before dispatching an outside click, so a photo change cannot send
/// the previous photo's pending value to the next photo's binding.
@MainActor final class GrainAgentWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if let active = ProNumberControl.activeEditor, active.window === self,
               !active.containsFieldPoint(event.locationInWindow) {
                ProNumberControl.endEditing()
            } else if let editor = firstResponder as? NSTextView, editor.isFieldEditor,
                      let field = editor.delegate as? NSTextField,
                      !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
                // Also commit search, names and the original inspector's edit
                // fields before a button/slider/photo takes the next action.
                makeFirstResponder(nil)
            }
        }
        super.sendEvent(event)
    }
}
