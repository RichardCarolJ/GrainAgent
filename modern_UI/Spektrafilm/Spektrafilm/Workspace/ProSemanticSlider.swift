import AppKit
import SwiftUI

/// Track colour describes the parameter's direction, never a selected amount.
/// The cell keeps AppKit's knob, hit testing, focus ring and accessibility.
enum ProSliderAxis {
    case neutral, temperature, tint, cyanRed, magentaGreen, yellowBlue

    init(key: String) {
        switch key {
        case "temp", "postTemp": self = .temperature
        case "tint", "postTint": self = .tint
        case "cyan": self = .cyanRed
        case "green", "magenta": self = .magentaGreen
        case "blue", "yellow": self = .yellowBlue
        default: self = .neutral
        }
    }
    var guidance: String {
        switch self {
        case .neutral: return ""
        case .temperature: return "向左偏冷蓝，向右偏暖黄"
        case .tint: return "向左偏绿，向右偏洋红"
        case .cyanRed: return "向左偏青，向右偏红"
        case .magentaGreen: return "向左偏洋红，向右偏绿"
        case .yellowBlue: return "向左偏黄，向右偏蓝"
        }
    }
    func colours(dark: Bool) -> [NSColor] {
        let neutral = NSColor(white: dark ? 0.59 : 0.62, alpha: 1)
        func rgb(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        switch self {
        case .neutral: return [NSColor(white: dark ? 0.46 : 0.57, alpha: 1), NSColor(white: dark ? 0.68 : 0.42, alpha: 1)]
        case .temperature: return [rgb(0x4D94D7), neutral, rgb(0xD9B94F)]
        case .tint: return [rgb(0x61AA77), neutral, rgb(0xC96BA6)]
        case .cyanRed: return [rgb(0x49A9BA), neutral, rgb(0xCF7065)]
        case .magentaGreen: return [rgb(0xBA78AE), neutral, rgb(0x77AC7C)]
        case .yellowBlue: return [rgb(0xC2AC59), neutral, rgb(0x728FC3)]
        }
    }
}

struct ProSemanticSlider: NSViewRepresentable {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var axis: ProSliderAxis = .neutral
    var onEditingChanged: (Bool) -> Void = { _ in }
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> ProNativeSlider {
        let slider = ProNativeSlider(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        slider.changed = { context.coordinator.parent.value = $0 }
        slider.editingChanged = { context.coordinator.parent.onEditingChanged($0) }
        configure(slider)
        return slider
    }
    func updateNSView(_ slider: ProNativeSlider, context: Context) {
        context.coordinator.parent = self
        configure(slider)
    }
    private func configure(_ slider: ProNativeSlider) {
        slider.minValue = range.lowerBound; slider.maxValue = range.upperBound
        slider.increment = step; slider.altIncrementValue = step
        slider.doubleValue = value; slider.isEnabled = enabled
        slider.setAccessibilityLabel(title)
        slider.toolTip = axis.guidance.isEmpty ? title : title + ": " + G(axis.guidance)
        (slider.cell as? ProSliderCell)?.axis = axis
        slider.needsDisplay = true
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator {
        var parent: ProSemanticSlider
        init(_ parent: ProSemanticSlider) { self.parent = parent }
    }
}

@MainActor final class ProNativeSlider: NSSlider {
    var changed: ((Double) -> Void)?
    var editingChanged: ((Bool) -> Void)?
    var increment = 1.0
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        cell = ProSliderCell()
        sliderType = .linear; controlSize = .small; isContinuous = true
        target = self; action = #selector(slid)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func slid() {
        let quantized = min(maxValue, max(minValue, (doubleValue / increment).rounded() * increment))
        doubleValue = quantized
        changed?(quantized)
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        ProNumberControl.endEditing()
        editingChanged?(true)
        defer { editingChanged?(false) }
        super.mouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125: adjust(-increment)
        case 124, 126: adjust(increment)
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformIncrement() -> Bool { guard isEnabled else { return false }; adjust(increment); return true }
    override func accessibilityPerformDecrement() -> Bool { guard isEnabled else { return false }; adjust(-increment); return true }
    private func adjust(_ amount: Double) {
        guard isEnabled else { return }
        ProNumberControl.endEditing()
        editingChanged?(true)
        doubleValue = min(maxValue, max(minValue, doubleValue + amount))
        slid()
        editingChanged?(false)
    }
}

@MainActor final class ProSliderCell: NSSliderCell {
    var axis: ProSliderAxis = .neutral
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let dark = controlView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let track = NSRect(x: rect.minX, y: rect.midY - 2.5, width: rect.width, height: 5)
        let path = NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let colours = axis.colours(dark: dark).map { isEnabled ? $0 : $0.withAlphaComponent(0.35) }
        NSGradient(colors: colours)?.draw(in: track, angle: 0)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(isEnabled ? 0.14 : 0.06).setStroke()
        path.lineWidth = 0.5; path.stroke()
    }
}

enum ProPalette {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.87, green: 0.59, blue: 0.36) : Color(red: 0.65, green: 0.29, blue: 0.12)
    }
    static func action(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.65, green: 0.30, blue: 0.13) : Color(red: 0.70, green: 0.32, blue: 0.13)
    }
}

struct ProActionTint: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View { content.tint(ProPalette.action(scheme)) }
}
