import SwiftUI
import AppKit

// Keep the same controls and layout on macOS 15. Only the material depends
// on OS availability; imaging and workspace state do not take another path.
extension View {
    func grainGlass() -> some View { grainGlass(in: Capsule()) }

    @ViewBuilder func grainGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

struct ProGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    @ViewBuilder var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

struct ProProminentButton: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct ProGlass: ViewModifier {
    var radius: CGFloat = 18
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.grainGlass(in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius:radius).strokeBorder(scheme == .dark ? .white.opacity(0.12) : .black.opacity(0.16),lineWidth:0.75).allowsHitTesting(false) }
    }
}

struct ProControlFace: ViewModifier {
    var selected = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal,7).padding(.vertical,4)
            .background(selected ? ProPalette.action(scheme) : (scheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.80)),in:.rect(cornerRadius:6))
            .overlay { RoundedRectangle(cornerRadius:6).strokeBorder(selected ? ProPalette.action(scheme) : (scheme == .dark ? Color.white.opacity(0.23) : Color.black.opacity(0.36)),lineWidth:0.75).allowsHitTesting(false) }
            .opacity(enabled ? 1 : 0.58)
    }
}

struct ProWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ProWindowHook: NSViewRepresentable {
    let store: WorkspaceStore
    func makeNSView(context: Context) -> NSView { Hook(store: store) }
    func updateNSView(_ view: NSView, context: Context) {}
    private final class Hook: NSView {
        let store: WorkspaceStore
        init(store: WorkspaceStore) { self.store = store; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { Task { @MainActor in self.store.attachWindow(window) } }
        }
    }
}

struct ProSection<Content: View>: View {
    let title: String
    var detail: String = ""
    @State private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: () -> Content
    init(_ title: String, detail: String = "", open: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.detail = detail; self.content = content
        _expanded = State(initialValue: open)
    }
    var body: some View {
        VStack(spacing: 0) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 11, content: content)
                    .padding(.top, 12).padding(.bottom, 3)
            } label: {
                HStack { Text(title).fontWeight(.semibold); Spacer(minLength: 6); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
                    .padding(.vertical, 3)
            }.font(.system(size: 13)).padding(13)
            Divider().opacity(0.45)
        }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: expanded)
            .onChange(of: expanded) { _, _ in ProNumberControl.endEditing() }
    }
}

struct ProDetail<Content: View>: View {
    let title: String
    @State var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) { self.title = title; self.content = content }
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) { VStack(alignment: .leading, spacing: 10, content: content).padding(.top, 8) } label: {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: expanded)
            .onChange(of: expanded) { _, _ in ProNumberControl.endEditing() }
    }
}


/// Native sections keep their actual bindings and dependency rules; only the
/// section shell is replaced by the accepted professional disclosure layout.
private struct ProfessionalActionsKey: EnvironmentKey {
    static let defaultValue: WorkspaceStore? = nil
}
extension EnvironmentValues {
    var professionalActions: WorkspaceStore? {
        get { self[ProfessionalActionsKey.self] }
        set { self[ProfessionalActionsKey.self] = newValue }
    }
}

struct ProfessionalSectionShell<Content: View>: View {
    @Environment(\.professionalActions) private var actions
    let title: String, key: String
    @Binding var expanded: Bool
    var action: SectionAction?, menu: (() -> AnyView)?, note: String?
    var toggle: Binding<Bool>?, toggleHelp: String
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var caption: String {
        ["camera":G("输入校正"), "filmFormat":G("胶片效果与物理画幅"), "exposure2":G("成片曝光与色彩"), "wb2":G("成片白平衡"), "scenePlacement":G("场景映射")][key] ?? title
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button { ProNumberControl.endEditing(); expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold))
                        Text(caption).font(.system(size: 13, weight: .semibold)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Spacer(minLength: 3)
                if let toggle { Toggle(caption, isOn: toggle).labelsHidden().toggleStyle(.switch).controlSize(.mini).help(toggleHelp) }
                if let action {
                    Button {
                        ProNumberControl.endEditing()
                        if let actions { actions.resetSection(action.help, action.perform) }
                        else { action.perform() }
                    } label: { Image(systemName: action.systemImage) }
                        .buttonStyle(.borderless).disabled(!action.enabled)
                        .accessibilityLabel(action.help)
                        .help(action.enabled ? action.help + G("；可以撤销") : G("已经是默认值"))
                }
                if let menu { Menu { menu() } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help(caption + G("的更多操作")).accessibilityLabel(caption + G("的更多操作")) }
            }.padding(.horizontal,13).padding(.vertical,14)
            if let note, !note.isEmpty { Text(note).font(.system(size:10)).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,15).padding(.bottom,7) }
            if expanded { content().padding(.bottom,13).transition(.opacity.combined(with:.move(edge:.top))) }
            Divider().opacity(0.45)
        }.animation(reduceMotion ? nil : .smooth(duration:0.22), value: expanded)
    }
}

enum ProfessionalNativePalette {
    static var active: Bool { UserDefaults.standard.bool(forKey:"grainagent.workspace.professional") }
    static var sliderTrack: Color { color(dark:0x737C77,light:0x687886,original:Theme.ground) }
    static var controlBorder: Color { color(dark:0x737C77,light:0x687580,original:.clear) }
    static func color(dark: UInt32, light: UInt32, original: Color) -> Color {
        let fallback = NSColor(original)
        return Color(nsColor: NSColor(name: nil) { appearance in
            guard UserDefaults.standard.bool(forKey: "grainagent.workspace.professional") else { return fallback }
            let hex = appearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha:1)
        })
    }
}

struct ProfessionalValueSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>, step: Double = 1, unit = "", axis = ProSliderAxis.neutral
    var body: some View {
        VStack(spacing:6) {
            HStack {
                Text(title).font(.system(size:12)); Spacer()
                ProNumberField(title:title,value:$value,range:range,step:step,digits:step >= 1 ? 0 : 2).frame(width:78,height:24)
                if !unit.isEmpty { Text(unit).font(.system(size:10)).foregroundStyle(.secondary) }
            }
            ProSemanticSlider(title:title,value:$value,range:range,step:step,axis:axis).frame(height:20)
        }
    }
}
