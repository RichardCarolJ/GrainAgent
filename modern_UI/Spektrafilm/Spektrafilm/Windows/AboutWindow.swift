//  AboutWindow.swift — who made this, under what licence, and where the
//  source is.
//
//  **Not a nicety.** Two of the three licences the bundle carries require
//  something visible, and one of them names this screen: CC BY-SA 4.0, on the
//  film and paper profiles, says the attribution must survive "whether the LUT
//  is shipped inside a .cube header, an ICC profile field, an app's About
//  screen, a paid plugin … the form can vary; the information cannot
//  disappear." The GPL requires the licence text and an offer of the
//  corresponding source. So: the credit is on the front, the full texts are
//  one click away, and both are read out of the bundle rather than retyped
//  here — a licence text that drifts from the file beside it is worse than
//  none (HANDOFF-DISTRIBUTION §2.3).

import AppKit
import SwiftUI

struct AboutWindow: View {
    @State private var showing: Licence?
    @State private var showingAcknowledgements = false

    /// One licence text in the bundle. `body` is read lazily: five files, of
    /// which the GPL alone is 35 kB, and the panel usually shows none of them.
    struct Licence: Identifiable, Hashable {
        let id: String       // the file name
        let title: String
        var url: URL? { AboutWindow.licenceDirectory?.appending(path: id) }
        var body: String {
            (url.flatMap { try? String(contentsOf: $0, encoding: .utf8) })
                ?? "\(id) is missing from this build. Run Tools/bundle-licenses.sh."
        }
    }

    /// The standalone app carries the exact source archive used to build it.
    /// Public links are enabled only after the owner publishes that release.
    static var sourceArchive: URL? {
        Bundle(for: BundleToken.self).url(forResource: "CorrespondingSource", withExtension: "zip")
    }
    static var sourceURL: String {
        let url = licenceDirectory?.appending(path: "GrainAgent-Source-Location.txt")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    static let applicationUpstreamURL = "https://github.com/JamesQiu2005/SpektraLab"
    static let upstreamURL = "https://github.com/andreavolpato/spektrafilm"
    static var sourceLabel: String { L("Source code for this version", zh: "本版本完整源代码") }

    static let licences = [
        Licence(id: "GrainAgent-NOTICE.txt", title: "GrainAgent · 来源、修改与致谢"),
        Licence(id: "SpektraLab-GPL-3.0.txt", title: "GNU GPL v3 — 应用与引擎"),
        Licence(id: "Profiles-and-LUTs-CC-BY-SA-4.0.txt", title: "CC BY-SA 4.0 — 胶片／相纸数据与印相 LUT"),
        Licence(id: "Profiles-and-LUTs-CHANGELOG.txt", title: "本版本对数据与 LUT 的修改"),
        Licence(id: "metal-cpp-Apache-2.0.txt", title: "Apache 2.0 — metal-cpp"),
    ]

    /// `Bundle(for:)`, not `Bundle.main`, for `EngineClient`'s reason: the
    /// unit-test target is standalone, so `Bundle.main` is Xcode's test agent
    /// and every lookup misses.
    static var licenceDirectory: URL? {
        Bundle(for: BundleToken.self).url(forResource: "Licenses", withExtension: nil,
                                          subdirectory: "Resources")
    }
    private final class BundleToken {}

    private static var version: String {
        let info = Bundle(for: BundleToken.self).infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return L("Version \(short) · Build \(build)", zh: "版本 \(short) · 构建 \(build)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    productStory
                    HStack(spacing: 18) {
                        Button(L("What's new", zh: "本版更新")) {
                            showing = Licence(id: "GrainAgent-Release-Notes.txt", title: "GrainAgent 1.0.1")
                        }
                        if let source = AboutWindow.sourceArchive {
                            Button(AboutWindow.sourceLabel) { NSWorkspace.shared.activateFileViewerSelecting([source]) }
                        }
                    }
                    .buttonStyle(.link).font(Theme.Font.sublabel)
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Built on SpektraLab — Hanze Qiu and contributors; spektrafilm — Andrea Volpato.",
                               zh: "基于 SpektraLab（Hanze Qiu 与贡献者）及 spektrafilm（Andrea Volpato）。"))
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                        DisclosureGroup(isExpanded: $showingAcknowledgements) {
                            VStack(alignment: .leading, spacing: 18) {
                                credits
                                licenceList
                            }
                            .padding(.top, 12)
                        } label: {
                            Text(L("Open-source acknowledgements & licences", zh: "开源致谢与许可证"))
                                .font(Theme.Font.sublabel)
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 600)
        .background(Theme.card)
        .sheet(item: $showing) { licence in
            LicenceSheet(licence: licence) { showing = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppIdentity.name).font(.system(size: 28, weight: .semibold, design: .serif)).italic()
                Text(AboutWindow.version).font(Theme.Font.sublabel).foregroundStyle(.secondary)
                Text(L("Film colour. A considered workflow.", zh: "胶片色彩，顺手成片。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    private var productStory: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L("Design & maintenance", zh: "设计与维护"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                Text(AppIdentity.maintainer).font(.system(size: 23, weight: .semibold))
            }
            Text(L("A film and print editor for macOS, with a carefully designed interface and a shared workflow from individual edits to batch output.",
                   zh: "为 macOS 打造的胶片与相纸模拟软件。从逐张调整到批量输出，让胶片摄影的色彩体验融入日常修图。"))
                .font(Theme.Font.sublabel).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                feature("camera.aperture", L("Two ways to create", zh: "两种工作方式"),
                        L("A tactile camera interface and a detailed professional workspace.", zh: "复古相机式简单模式，以及细致灵活的专业工作区。"))
                feature("square.stack.3d.up", L("Individual edits, shared output", zh: "逐张编辑，批量成片"),
                        L("Remember each photo's settings and export a batch with one recipe.", zh: "每张照片独立记住参数，整批共用输出设置。"))
                feature("internaldrive", L("Your photos stay local", zh: "本地处理，继续创作"),
                        L("Process on your Mac and resume your previous workspace.", zh: "照片在 Mac 上处理，再次打开即可接着上次的工作。"))
            }
            Text("© 2026 \(AppIdentity.maintainer) · GrainAgent")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
        }
    }
    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Theme.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.groupHeader)
                Text(detail).font(Theme.Font.sublabel).foregroundStyle(.secondary)
            }
        }
    }
    private var credits: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(G("基于 SpektraLab 1.3.5")).font(Theme.Font.groupHeader)
                Text(L("Hanze Qiu and contributors — native application, C++/Metal engine port and photo workflow.", zh: "Hanze Qiu 与贡献者：原生应用、C++／Metal 引擎移植及照片处理流程。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                link("SpektraLab", AboutWindow.applicationUpstreamURL)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("spektrafilm · Andrea Volpato").font(Theme.Font.groupHeader)
                Text(L("Film and print model, original film/paper profiles and derived print LUTs. Profiles and LUTs: CC BY-SA 4.0.", zh: "胶片与相纸模拟模型、原始胶片／相纸数据及衍生打印 LUT。数据与 LUT：CC BY-SA 4.0。"))
                    .font(Theme.Font.sublabel).foregroundStyle(.secondary)
                link("spektrafilm", AboutWindow.upstreamURL)
            }
            Text(L("Independent modified version; not an official release of either upstream project. Application code: GPL-3.0-or-later, without warranty.", zh: "独立修改版，非上述上游项目的官方发行版。应用代码采用 GPL-3.0-or-later，不提供担保。"))
                .font(Theme.Font.caption).foregroundStyle(.secondary)
            if AboutWindow.sourceArchive == nil, AppIdentity.publicReleaseChannel {
                link(AboutWindow.sourceLabel, AboutWindow.sourceURL)
            } else if AboutWindow.sourceArchive == nil {
                Text(L("Source is supplied with the distribution package.", zh: "完整源代码随发行包提供。"))
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var licenceList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Licences", zh: "许可证")).font(Theme.Font.groupHeader).foregroundStyle(Theme.text)
            ForEach(AboutWindow.licences) { licence in
                Button { showing = licence } label: {
                    HStack(spacing: 6) {
                        Text(G(licence.title)).font(Theme.Font.listItem).foregroundStyle(Theme.text)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 9))
                            .foregroundStyle(Theme.dim)
                    }
                    .frame(height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if let dir = AboutWindow.licenceDirectory {
                Button(L("Show the licence files in Finder", zh: "在 Finder 中查看许可证文件")) {
                    NSWorkspace.shared.activateFileViewerSelecting([dir])
                }
                .buttonStyle(.link).font(Theme.Font.caption)
            } else {
                // Said rather than hidden: a build with no licence texts is a
                // build that should not have been made.
                Text("This build carries no licence texts. Run Tools/bundle-licenses.sh and rebuild.")
                    .font(Theme.Font.caption).foregroundStyle(Theme.accent)
            }
        }
    }

    private func link(_ label: String, _ url: String) -> some View {
        Button(label) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }
            .buttonStyle(.link).font(Theme.Font.sublabel)
    }
}

/// One licence, in full, selectable and scrollable.
///
/// Rendered in the app rather than handed to TextEdit: a signed, notarised
/// bundle's resources are read-only and opening them in another app is one
/// more thing that can fail on a stranger's machine, when the obligation is
/// simply that the text be *available*.
private struct LicenceSheet: View {
    let licence: AboutWindow.Licence
    let dismiss: () -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(G(licence.title)).font(.system(size: 13, weight: .semibold))
            ScrollView {
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 4))
            HStack {
                if let url = licence.url {
                    Button(G("在访达中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link).font(Theme.Font.caption)
                }
                Spacer()
                Button(G("完成"), action: dismiss).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 640, height: 520)
        .task { text = licence.body }
    }
}
