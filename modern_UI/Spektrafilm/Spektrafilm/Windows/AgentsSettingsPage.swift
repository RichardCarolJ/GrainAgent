//  AgentsSettingsPage.swift — Settings ▸ Agents (RFC-026 §6).
//
//  Three groups: the switch (off by default, and the only thing standing
//  between another program and the person's frames), the `spektralab`
//  command, and the lines that add the MCP server to an agent. Everything an
//  agent could be told to type is shown here with a Copy button, because a
//  configuration line retyped from a screenshot is how a path with a space in
//  it breaks.

import AppKit
import SwiftUI

struct AgentsSettingsPage: View {
    @AppStorage(AgentAccess.key) private var enabled = false
    @State private var install = AgentAccess.installState
    @State private var installError: String?
    @State private var copied: String?

    var body: some View {
        SettingsGroup(L(.setAgentsAccess)) {
            SettingsRows {
                VStack(alignment: .leading, spacing: 4) {
                    ToggleRow(label: L(.setAgentsToggle), isOn: $enabled)
                    caption(L(.setAgentsToggleCaption))
                }
            }
        }
        SettingsGroup(L(.setAgentsCommandLine)) {
            SettingsRows {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(statusText).font(Theme.Font.caption).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        if install != .absent {
                            action(L(.setAgentsUninstall)) { run(AgentAccess.uninstall) }
                        }
                        action(install == .absent ? L(.setAgentsInstall) : L(.setAgentsReinstall)) {
                            run(AgentAccess.install)
                        }
                    }
                    code(AgentAccess.installURL.path.replacingOccurrences(
                        of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    caption(L(.setAgentsInstallCaption))
                    if let installError { caption(installError).foregroundStyle(Theme.accent) }
                }
            }
        }
        SettingsGroup(L(.setAgentsMCP)) {
            SettingsRows {
                VStack(alignment: .leading, spacing: 6) {
                    snippet(L(.setAgentsClaudeCode), AgentAccess.claudeCodeCommand)
                    snippet(L(.setAgentsClaudeDesktop), AgentAccess.desktopConfig)
                    caption(L(.setAgentsMCPCaption))
                }
            }
        }
        SettingsGroup(L(.setAgentsTools)) {
            SettingsRows {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(AgentTools.all, id: \.name) { t in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(t.name).font(.system(size: 10.5 * scale, design: .monospaced))
                                .foregroundStyle(Theme.text)
                                .frame(width: 128 * scale, alignment: .leading)
                            Text(toolSummary(t)).font(Theme.Font.caption).foregroundStyle(Theme.dim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var scale: CGFloat { InterfaceScaleStore.shared.scale.factor }

    private var statusText: String {
        switch install {
        case .absent: L(.setAgentsNotInstalled)
        case .current: L(.setAgentsInstalled)
        case .other: L(.setAgentsInstalledOther)
        }
    }

    private func run(_ f: () throws -> Void) {
        do { try f(); installError = nil } catch { installError = "\(error)" }
        install = AgentAccess.installState
    }

    private func action(_ title: String, _ act: @escaping () -> Void) -> some View {
        Button(title, action: act)
            .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent)
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(Theme.Font.label).foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                action(copied == title ? L(.setAgentsCopied) : L(.setAgentsCopy)) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = title
                }
            }
            code(text)
        }
    }

    private func code(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9 * scale, design: .monospaced))
            .foregroundStyle(Theme.secondaryText)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Theme.plot, in: RoundedRectangle(cornerRadius: 4))
    }

    private func caption(_ text: String) -> Text {
        Text(text).font(Theme.Font.caption).foregroundStyle(Theme.dim)
    }

    private func toolSummary(_ tool: AgentTool) -> String {
        switch tool.name {
        case "get_schema": return G("列出可编辑字段的路径、类型、范围与含义。")
        case "list_stocks": return G("按标识列出胶片与相纸。")
        case "list_recipes": return G("按名称列出输出配方。")
        case "describe_image": return G("打开照片并读取尺寸、RAW 状态、白平衡、EXIF、胶片、相纸与处理状态。")
        case "get_edit": return G("读取当前照片的处理、调色、几何与解码参数。")
        case "edit_image": return G("使用 JSON 合并补丁修改指定参数；无效字段或超出范围的数值不会写入。")
        case "reset_edit": return G("恢复胶片、印相、调色与几何的默认值，保留解码设置。")
        case "process_image": return G("为所选胶片与相纸显影、测光并求解放大机滤色；会重置黄／洋红偏移。")
        case "measure_latitude": return G("测量胶片与相纸可容纳的场景范围、超出比例及建议调整档数。")
        case "place_scene": return G("通过引擎的匹配将高光与阴影纳入成像范围；两项为零时关闭。")
        case "preview_image": return G("返回小尺寸 sRGB JPEG 成片预览。")
        case "export_image": return G("按指定输出配方导出成片，并返回写入的文件。")
        default: return firstSentence(tool.summary)
        }
    }

    private func firstSentence(_ s: String) -> String {
        guard let r = s.range(of: ". ") else { return s }
        return String(s[..<r.lowerBound]) + "."
    }
}
