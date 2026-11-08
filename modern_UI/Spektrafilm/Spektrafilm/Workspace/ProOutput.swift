import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProOutputDock: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var outputFocused: Bool
    @FocusState private var subfolderFocused: Bool
    @State private var draggedToken: NameToken?
    private func field<C:View>(_ title:String,width:CGFloat? = nil,@ViewBuilder content:()->C) -> some View {
        VStack(alignment:.leading,spacing:4) { Text(title).font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85).help(title); content().frame(maxWidth:.infinity,alignment:.leading).frame(height:25) }.frame(width:width,alignment:.leading)
    }
    private var compactLabels: Bool { Localization.shared.resolved == .simplifiedChinese }
    private var quality: Binding<Double> { Binding(get:{ store.recipe.quality*100 },set:{ store.recipe.quality = $0.clamped(to:1...100)/100 }) }
    private var longEdge: Binding<Double> { Binding(get:{ Double(store.recipe.outputSize.edge ?? 3000) },set:{ store.recipe.outputSize = .clamped(Int($0)) }) }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:11) {
                settingsRow.disabled(store.running)
                VStack(alignment:.leading,spacing:4) {
                    HStack(spacing:9) {
                        Menu(G("配方")) {
                            ForEach(store.recipes.recipes) { recipe in Button(recipe.name) { ProNumberControl.endEditing(); store.recipe = recipe } }
                            Divider()
                            Button(G("保存当前配方"), action:store.saveRecipe)
                            Button(G("复制为新配方")) { store.recipes.duplicate(store.recipe); if let recipe = store.recipes.selected { store.recipe = recipe }; store.advancedOutput = true }
                            Button(G("删除当前配方")) { store.recipes.remove(store.recipe); if let recipe = store.recipes.selected { store.recipe = recipe } }.disabled(store.recipes.recipes.count <= 1)
                        }.menuStyle(.borderlessButton).fixedSize().disabled(store.running)
                        Toggle(G("打样"),isOn:$store.proof).toggleStyle(.switch).controlSize(.mini).fixedSize().modifier(ProActionTint())
                            .help(G("预览所选输出色域与尺寸的效果")).disabled(store.running || store.session.selection == nil || !store.recipe.format.takesColorSpace)
                            .onChange(of:store.proof) { _,on in if on { store.session.comparing = false; store.session.toggledOriginal(false); store.session.commitCrop() } }
                        Spacer(minLength:0)
                        Button { ProNumberControl.endEditing(); store.advancedOutput.toggle() } label: { HStack(spacing:3) { Text(G("更多")); Image(systemName:store.advancedOutput ? "chevron.up" : "chevron.down").font(.system(size:9)) } }.buttonStyle(.borderless)
                    }.font(.system(size:11))
                    Button { if store.running { store.stopOutput() } else { store.runOutput() } } label: {
                        Label(store.running ? G("停止") : G("输出 \(store.targets.count) 张"),systemImage:store.running ? "stop.fill" : "square.and.arrow.up").frame(maxWidth:.infinity)
                    }.modifier(ProProminentButton()).controlSize(.regular).frame(height:25).modifier(ProActionTint()).focused($outputFocused)
                        .disabled(!store.running && (store.targets.isEmpty || !store.session.serviceReady))
                }.frame(width:compactLabels ? 196 : 224)
            }.font(.system(size:12))
            if store.advancedOutput {
                Divider().opacity(0.5)
                ScrollView {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:18,alignment:.leading),count:4),alignment:.leading,spacing:12) {
                        field(G("子文件夹")) { TextField(G("留空则不建子文件夹"),text:$store.recipe.subfolder).textFieldStyle(.roundedBorder).focused($subfolderFocused) }
                        field(G("文件命名 · 勾选并拖动排序")) {
                            HStack(spacing:3) {
                                ForEach(store.recipe.naming.chips) { token in
                                    Button(name(token)) { store.recipe.naming.toggle(token) }.buttonStyle(.borderless)
                                        .font(.system(size:10)).padding(.horizontal,5).padding(.vertical,4)
                                        .background(store.recipe.naming.isOn(token) ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),in:.rect(cornerRadius:4))
                                        .onDrag { draggedToken = token; return NSItemProvider(object:token.rawValue as NSString) }
                                        .onDrop(of:[.text],isTargeted:nil) { _ in guard let from = draggedToken else { return false }; store.recipe.naming.move(from,before:token); draggedToken = nil; return true }
                                }
                            }
                        }
                        field(G("同名文件")) { Picker(G("同名文件"),selection:$store.recipe.existing) { Text(G("自动编号")).tag(ExistingFilePolicy.addSuffix); Text(G("跳过")).tag(ExistingFilePolicy.skip); Text(G("覆盖")).tag(ExistingFilePolicy.overwrite) }.labelsHidden() }
                        field(G("完成后打开方式")) {
                            Menu(store.recipe.openWith?.name ?? (store.revealAfterExport ? G("在访达中显示") : G("不自动打开"))) {
                                Button(G("不自动打开")) { store.recipe.openWith = nil; store.revealAfterExport = false }
                                Button(G("在访达中显示")) { store.recipe.openWith = nil; store.revealAfterExport = true }
                                Divider(); Button(G("选择应用…"),action:chooseApplication)
                            }.menuStyle(.borderlessButton)
                        }
                        field(G("最长边 · px")) { ProNumberField(title:G("最长边"),value:longEdge,range:Double(OutputSize.bounds.lowerBound)...Double(OutputSize.bounds.upperBound),step:1,digits:0).disabled(store.recipe.outputSize.isOriginal || store.recipe.format == .di) }
                        field(G("名称分隔符")) { TextField(G("分隔符"),text:$store.recipe.naming.separator).textFieldStyle(.roundedBorder) }
                        field(G("当前配方名称")) { TextField(G("配方名称"),text:$store.recipe.name).textFieldStyle(.roundedBorder) }
                        Toggle(G("TIFF 嵌入预览页"),isOn:$store.recipe.embedsPreview).disabled(!store.recipe.format.carriesPreviewPage)
                    }.font(.system(size:11)).disabled(store.running)
                    HStack {
                        Text(G("文件名：")+store.recipe.naming.stem(store.nameContext)+"."+store.recipe.format.ext).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(store.recipe.format == .di ? G("DI 输出为 Cineon 文件") : G("保持照片比例，不放大原图")).font(.system(size:10)).foregroundStyle(.secondary)
                    }.padding(.top,7)
                }.frame(height:112)
            }
            if !store.queue.isEmpty {
                HStack(spacing:12) {
                    Text(store.running ? G("正在输出") : G("输出记录")).font(.system(size:11))
                    ProgressView(value:Double(store.completed),total:Double(max(1,store.queue.count))).progressViewStyle(.linear)
                    Text("\(store.completed) / \(store.queue.count)").monospacedDigit().font(.system(size:11))
                    Button(store.queueVisible ? G("收起清单") : G("输出清单")) { store.queueVisible.toggle() }.buttonStyle(.borderless)
                    Button(G("查看文件")) { NSWorkspace.shared.activateFileViewerSelecting(store.written) }.buttonStyle(.borderless).disabled(store.written.isEmpty)
                }
            }
            if store.queueVisible {
                ScrollView {
                    LazyVStack(spacing:5) {
                        ForEach(store.queue) { item in HStack { Text(item.id.lastPathComponent).lineLimit(1).truncationMode(.middle); Spacer(); Text(G(item.state)).lineLimit(2).help(G(item.state)) }.font(.system(size:11)); Divider().opacity(0.4) }
                    }
                }.frame(maxHeight:70)
            }
        }.padding(.horizontal,14).padding(.vertical,11).modifier(ProGlass(radius:17))
            .animation(reduceMotion ? nil : .smooth(duration:0.22),value:store.advancedOutput)
            .animation(reduceMotion ? nil : .smooth(duration:0.22),value:store.queueVisible)
            .onChange(of:store.outputFocusRequest) { _,_ in outputFocused = true }
            .onChange(of:store.recipe.format) { _,format in if !format.takesColorSpace { store.proof = false } }
    }
    private var settingsRow: some View {
        Group {
            field(G("输出范围 · 整批共用"),width:compactLabels ? 114 : 142) { Picker(G("输出范围"),selection:$store.scope) { ForEach(["当前照片","所选照片","全部照片"],id:\.self) { Text(G($0)).tag($0) } }.labelsHidden() }
            field(G("保存位置")) {
                HStack(spacing:6) {
                    Image(systemName:"folder").foregroundStyle(.secondary)
                    Menu { Button(G("原照片旁")) { store.recipe.folder = .besideOriginal }; Button(G("选择文件夹…"),action:store.chooseFolder); Divider(); Button(G("更改子文件夹名…")) { ProNumberControl.endEditing(); store.advancedOutput = true; subfolderFocused = true } } label: { Text(store.folderLabel).lineLimit(1).truncationMode(.middle).frame(maxWidth:.infinity,alignment:.leading) }.menuStyle(.borderlessButton)
                    Button(action:store.chooseFolder) { Image(systemName:"folder.badge.plus") }.buttonStyle(.borderless).help(G("选择或新建文件夹"))
                }.padding(.horizontal,8).frame(height:25).background(.quaternary.opacity(0.4),in:.rect(cornerRadius:7))
                    .help(store.session.selection.map { store.recipe.directory(for:$0).path } ?? store.folderLabel)
            }
            field(G("格式"),width:compactLabels ? 98 : 114) {
                Picker(G("格式"),selection:$store.recipe.format) { Text(G("JPEG · 8 位")).tag(ExportFormat.jpeg); Text(G("PNG · 8 位")).tag(ExportFormat.png); Text(G("TIFF · 16 位")).tag(ExportFormat.tiff); Text("DI · Cineon").tag(ExportFormat.di) }.labelsHidden()
            }
            field(G("质量 %"),width:54) { ProNumberField(title:G("JPEG 质量"),value:quality,range:1...100,step:1,digits:0).disabled(!store.recipe.format.takesQuality) }.help(store.recipe.format.takesQuality ? G("JPEG 质量：1–100%") : G("当前格式不使用 JPEG 质量"))
            field(G("色域"),width:115) { Picker(G("色域"),selection:$store.recipe.colorSpace) { ForEach(ColorSpaceCatalog.all) { entry in Text(entry.name).tag(entry.space) } }.labelsHidden().disabled(!store.recipe.format.takesColorSpace) }
            field(G("尺寸"),width:compactLabels ? 106 : 132) {
                Picker(G("尺寸"),selection:Binding(get:{ store.recipe.outputSize.isOriginal },set:{ store.recipe.outputSize = $0 ? .original : .longEdge(3000); if !$0 { store.advancedOutput = true } })) { Text(G("原始尺寸")).tag(true); Text(G("限制长边")).tag(false) }.labelsHidden().disabled(store.recipe.format == .di)
            }
        }
    }
    private func name(_ token:NameToken)->String { switch token { case .originalName:G("原名"); case .filmStock:G("胶片"); case .printStock:G("相纸"); case .date:G("日期") } }
    private func chooseApplication() {
        let panel = NSOpenPanel(); panel.title = G("输出后使用此应用打开"); panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath:"/Applications")
        if panel.runModal() == .OK,let url = panel.url { store.recipe.openWith = OpenWith(path:url.path); store.revealAfterExport = false }
    }
}
