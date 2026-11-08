import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GrainAgentWorkspace: View {
    @Bindable var store: WorkspaceStore
    @AppStorage("grainagent.workspace.professional") private var professional = true
    @State private var simpleController: SimpleCameraController?
    @State private var morph = WorkspaceMorphCoordinator()
    var body: some View {
        Group {
            if professional { ProfessionalWorkspace(store:store,professional:Binding(get:{ professional },set:{ requestMode($0) })) }
            else if let simpleController { SimpleCameraWorkspace(controller:simpleController) }
            else { ProgressView(G("打开简单模式…")).frame(maxWidth:.infinity,maxHeight:.infinity) }
        }
        .background(ProWindowBackground())
        .background(ProWindowHook(store:store).frame(width:0,height:0))
        .ignoresSafeArea()
        .textSelection(.disabled)
        .environment(\.locale, Locale(identifier: Localization.shared.resolved.localeIdentifier))
        .preferredColorScheme(professional ? store.appearance.scheme : .dark)
        .onAppear {
            if !professional { commitMode(false,resize:true) }
            store.windowPresentation = { frame in
                morph.start(to:store.professional,store:store,simple:simpleController,targetFrame:frame) {}
            }
        }
        .onChange(of:professional) { _,value in
            if store.professional != value { commitMode(value,resize:true) }
        }
        .onChange(of:store.session.sidecar) { _,_ in store.proofRevision &+= 1 }
        .onChange(of:store.session.showExport) { _,wanted in
            guard wanted else { return }; store.session.showExport = false
            if professional { store.showOutput() } else { _ = SimpleCameraController.command("settings") }
        }
    }
    private func requestMode(_ value: Bool) {
        guard value != professional, !store.running, !store.restoringWindow, !store.transitioningFullscreen, !WorkspaceMorphCoordinator.active else { return }
        ProNumberControl.endEditing()
        if simpleController == nil { simpleController = SimpleCameraController(session:store.session,workspace:store) }
        simpleController?.professionalTransition = { requestMode(true) }
        let previewMotion = UserDefaults.standard.bool(forKey:"grainagent.modeMorph.preview")
        if !previewMotion { commitMode(value,resize:true); return }
        morph.start(to:value,store:store,simple:simpleController) { commitMode(value,resize:false) }
    }
    private func commitMode(_ value: Bool, resize: Bool) {
        store.session.flushSave()
        if !value && simpleController == nil { simpleController = SimpleCameraController(session:store.session,workspace:store) }
        simpleController?.professionalTransition = { requestMode(true) }
        if !value {
            simpleController?.professionalProtect(store.professionallyEdited)
            simpleController?.professionalAdoptOutput(store.recipe)
        } else {
            if let simpleController, let recipe = try? simpleController.professionalOutputRecipe(validateFolder: false) { store.recipe = recipe }
            store.session.tool = .select; store.notice = ""
        }
        store.switchMode(value,resize:resize)
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { professional = value }
    }
}

struct ProfessionalWorkspace: View {
    @Bindable var store: WorkspaceStore
    @Binding var professional: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTarget = false
    var body: some View {
        GeometryReader { geometry in
            // Ordinary resizing reallocates real space; only a display smaller
            // than the minimum workspace scales the whole design uniformly.
            let scale = min(1, geometry.size.width / ProfessionalWindowBounds.designMinimum.width,
                            geometry.size.height / ProfessionalWindowBounds.designMinimum.height)
            let width = geometry.size.width / max(0.01, scale)
            ProGlassContainer(spacing:6) {
                VStack(spacing:8) {
                    header.background(WorkspaceMorphProbe("header"))
                    HStack(spacing:10) {
                        if store.leftVisible { ProMaterials(store:store).frame(width:min(292,max(268,width*0.202))).background(WorkspaceMorphProbe("materials")) }
                        viewer.background(WorkspaceMorphProbe("preview"))
                        if store.rightVisible { ProInspector(store:store).frame(width:min(350,max(322,width*0.238))).background(WorkspaceMorphProbe("inspector")) }
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).padding(.horizontal,10)
                    if !store.session.filmstripCollapsed { ProLibrary(store:store).background(WorkspaceMorphProbe("library")).padding(.horizontal,10) }
                    ProOutputDock(store:store).background(WorkspaceMorphProbe("output")).padding(.horizontal,10)
                    HStack {
                        if store.session.working { ProgressView().controlSize(.mini) }
                        Text(G(store.status)).lineLimit(1).truncationMode(.middle).help(G(store.status))
                        Spacer(minLength:15)
                    }.font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,15).padding(.bottom,7)
                }
            }.frame(width:width,height:geometry.size.height / max(0.01,scale))
                .scaleEffect(scale,anchor:.topLeading)
                .transaction { if store.resizingWindow { $0.animation = nil; $0.disablesAnimations = true } }
        }.environment(\.professionalActions,store).font(.system(size:13)).controlSize(.small)
            .tint(ProPalette.accent(scheme)).accentColor(ProPalette.accent(scheme))
            .animation(reduceMotion ? nil : .smooth(duration:0.22),value:store.leftVisible)
            .animation(reduceMotion ? nil : .smooth(duration:0.22),value:store.rightVisible)
            .onDrop(of:[.fileURL],isTargeted:$dropTarget) { providers in
                guard !store.running else { return false }
                Task { @MainActor in
                    var urls:[URL] = []
                    for provider in providers {
                        if let data = try? await provider.loadItem(forTypeIdentifier:UTType.fileURL.identifier) as? Data, let url = URL(dataRepresentation:data,relativeTo:nil) { urls.append(url) }
                    }
                    store.importFiles(urls)
                }; return true
            }
    }
    private var header: some View {
        HStack(spacing:14) {
            HStack(alignment:.center,spacing:7) {
                Text("GrainAgent")
                    .font(.custom("Georgia-Italic",size:19)).tracking(-0.55)
                    .foregroundStyle(Color.primary.opacity(scheme == .dark ? 0.90 : 0.78))
                Text("PRO")
                    .font(.system(size:7.5,weight:.medium)).tracking(0.9)
                    .foregroundStyle(scheme == .dark ? Color(red:0.92,green:0.78,blue:0.58) : Color(red:0.45,green:0.30,blue:0.16))
                    .padding(.leading,5).padding(.trailing,4).frame(height:14)
                    .background {
                        RoundedRectangle(cornerRadius:3).fill(LinearGradient(colors:scheme == .dark
                            ? [Color(red:0.48,green:0.37,blue:0.24).opacity(0.48),Color(red:0.29,green:0.24,blue:0.18).opacity(0.34),Color(red:0.41,green:0.30,blue:0.19).opacity(0.38)]
                            : [Color(red:0.96,green:0.90,blue:0.79).opacity(0.85),Color(red:0.87,green:0.78,blue:0.64).opacity(0.45),Color(red:0.94,green:0.87,blue:0.74).opacity(0.65)],
                            startPoint:.topLeading,endPoint:.bottomTrailing))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius:3).strokeBorder(LinearGradient(colors:[
                            Color(red:0.94,green:0.83,blue:0.66).opacity(scheme == .dark ? 0.60 : 0.85),
                            Color(red:0.61,green:0.44,blue:0.25).opacity(0.42)],startPoint:.top,endPoint:.bottom),lineWidth:0.5)
                    }
            }.fixedSize(horizontal:true,vertical:false)
                .accessibilityElement(children:.ignore).accessibilityLabel(G("GrainAgent 专业模式"))
                .padding(.leading,86)
            Spacer(minLength:12)
            HStack(spacing:7) {
                Button(action:store.choosePhotos) { Label(G("装入照片"),systemImage:"square.and.arrow.down") }.disabled(store.running)
                Divider().frame(height:16)
                Button(action:store.undo) { Image(systemName:"arrow.uturn.backward") }.disabled(store.undoStack.isEmpty || store.running).help(G("撤销上一次照片修改（⌘Z）")).accessibilityLabel(G("撤销"))
                Button(action:store.redo) { Image(systemName:"arrow.uturn.forward") }.disabled(store.redoStack.isEmpty || store.running).help(G("恢复刚刚撤销的修改（⇧⌘Z）")).accessibilityLabel(G("重做"))
                Divider().frame(height:16)
                Button { ProNumberControl.endEditing(); store.notice = ""; store.session.solveNow() } label: { Label(G("显影"),systemImage:"wand.and.stars") }
                    .disabled(store.running || !store.session.canSolve).help(G("根据当前胶片与相纸重新计算自动曝光和印相滤色；手动黄／品红滤色偏移将归零。此操作不输出文件。"))
            }.buttonStyle(.borderless).padding(.horizontal,12).padding(.vertical,9).grainGlass()
            Spacer(minLength:12)
            HStack(spacing:9) {
                Button { ProNumberControl.endEditing(); store.leftVisible.toggle() } label: { Image(systemName:"sidebar.left") }.help(G("胶片栏"))
                Button { ProNumberControl.endEditing(); store.rightVisible.toggle() } label: { Image(systemName:"sidebar.right") }.help(G("调整栏"))
                Menu {
                    ForEach(ProAppearance.allCases) { appearance in
                        Button { ProNumberControl.endEditing(); store.appearance = appearance } label: {
                            Label(G(appearance.rawValue),systemImage:store.appearance == appearance ? "checkmark" : appearance.symbol)
                        }
                    }
                } label: { Image(systemName:store.appearance.symbol).frame(width:18) }
                    .menuStyle(.borderlessButton).fixedSize().help(G("外观：") + G(store.appearance.rawValue))
                Picker(G("模式"),selection:Binding(get:{ professional },set:{ ProNumberControl.endEditing(); professional = $0 })) { Text(G("简单")).tag(false); Text(G("专业")).tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width:145).modifier(ProActionTint()).disabled(store.running)
            }.buttonStyle(.borderless)
        }.padding(.trailing,16).frame(height:59).background(WindowDragHandle())
            .overlay(alignment:.topLeading) {
                Button(action:store.resetWindowToDefault) {
                    Image(systemName:"rectangle.arrowtriangle.2.inward")
                        .font(.system(size:9,weight:.medium)).foregroundStyle(.secondary)
                        .frame(width:36,height:17).contentShape(RoundedRectangle(cornerRadius:5))
                }.buttonStyle(.plain).grainGlass(in:RoundedRectangle(cornerRadius:5),interactive:true)
                    .help(G("恢复专业模式默认窗口大小（⌘0）"))
                    .accessibilityLabel(G("恢复默认窗口比例"))
                    .padding(.leading,24).padding(.top,35)
            }
    }
    private var viewer: some View {
        VStack(spacing:0) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:3) {
                    Text(store.session.selection?.lastPathComponent ?? G("未装入照片")).font(.system(size:12,weight:.medium)).lineLimit(1).truncationMode(.middle)
                    Text(store.session.selection == nil ? "RAW · JPEG · TIFF · PNG · HEIF" : "\(Int(store.session.printPixelSize.width)) × \(Int(store.session.printPixelSize.height)) · \((store.currentIndex ?? 0)+1) / \(store.session.frames.count)")
                        .font(.system(size:10)).foregroundStyle(.secondary)
                }
                Spacer(minLength:8)
                Text(store.session.showingOriginal ? G("原图") : store.proof ? G("输出打样") : store.session.previewSoft ? G("更新中") : store.session.noFilm ? G("原图调色") : G("成片"))
                    .font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,7).padding(.vertical,4).background(.quaternary.opacity(0.4),in:Capsule())
            }.padding(14)
            ProCanvas(store:store).background(WorkspaceMorphProbe("canvas")).padding(.horizontal,12).padding(.bottom,12)
                .overlay { if dropTarget { RoundedRectangle(cornerRadius:8).stroke(Color.accentColor,lineWidth:2).allowsHitTesting(false) } }
            HStack(spacing:7) {
                Button {
                    store.proof = false; store.session.comparing = false; store.session.toggledOriginal(!store.session.showingOriginal)
                } label: { Text(store.session.showingOriginal ? G("返回成片") : G("原图")).modifier(ProControlFace(selected:store.session.showingOriginal)) }
                    .foregroundStyle(store.session.showingOriginal ? Color.accentColor : Color.primary).disabled(store.session.filmEdgeShowsFilm)
                Button {
                    store.proof = false; store.session.toggledOriginal(false); store.session.comparing.toggle()
                } label: { Label(G("对照"),systemImage:"rectangle.split.2x1").modifier(ProControlFace(selected:store.session.comparing)) }.disabled(!store.session.canCompare)
                Button {
                    store.proof = false; store.session.comparing = false; store.session.toggledOriginal(false)
                    if store.session.pair != nil { store.session.togglePairPlacing() }
                    else { store.session.tool = store.session.tool == .crop ? .select : .crop; store.rightVisible = true; UserDefaults.standard.set(true,forKey:Session.uiKey+"section.crop") }
                } label: { Label(store.session.pair == nil ? G("裁剪") : G("放置"),systemImage:"crop").modifier(ProControlFace(selected:store.session.tool == .crop || store.session.pairPlacing)) }
                Spacer(minLength:8)
                Picker(G("缩放"),selection:Binding(get:{ store.session.isFit },set:{ if $0 { store.session.zoomToFit() } else { store.session.zoomTo(fraction:1) } })) {
                    Text(G("适应")).tag(true); Text(store.session.isFit ? "100%" : "\(store.session.zoomPercent)%").tag(false)
                }.pickerStyle(.segmented).labelsHidden().frame(width:112).modifier(ProActionTint()).disabled(store.session.zoomLocked || store.proof)
                Menu {
                    ForEach([50,100,200,400],id:\.self) { zoom in Button("\(zoom)%") { store.session.zoomTo(fraction:CGFloat(zoom)/100) }.disabled(store.session.zoomLocked || store.proof) }
                    Divider(); Toggle(G("显示导航缩略图"),isOn:$store.navigatorVisible)
                } label: { Image(systemName:"magnifyingglass") }.menuStyle(.borderlessButton).fixedSize()
            }.buttonStyle(.borderless).padding(.horizontal,13).padding(.vertical,9).grainGlass().padding(.horizontal,14).disabled(store.running || store.session.selection == nil)
            if store.session.tool == .crop {
                HStack { Text(G("拖动裁剪框 · ⌘ 拖动拉直")).font(.system(size:11)).foregroundStyle(.secondary); Spacer(); Button(G("取消")) { store.session.cancelCrop() }; Button(G("完成")) { store.session.commitCrop() } }.padding(.horizontal,15).padding(.top,8).disabled(store.running)
            }
            Text(store.proof ? G("按当前输出尺寸与色域打样") : store.session.pair != nil ? G("半格参数分别保存") : store.session.showingOriginal ? G("按住空格查看原图") : G("每张照片独立保存参数 · 输出设置整批共用"))
                .font(.system(size:10)).foregroundStyle(.secondary).padding(.vertical,7)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(scheme == .dark ? Color(white:0.105) : Color(white:0.84),in:.rect(cornerRadius:14))
    }
}

struct ProLibrary: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing:5) {
            HStack(spacing:10) {
                Text(G("照片")).fontWeight(.semibold)
                Text(G("\(store.session.frames.count) 张 · 已选 \(store.session.picked.count)")).foregroundStyle(.secondary)
                Button(G("全选")) { store.session.selectAllFrames() }.disabled(!store.session.canSelectAllFrames)
                Button { store.remove(store.session.selectedFrames) } label: { Image(systemName:"minus.circle") }.disabled(store.session.picked.isEmpty).help(G("从批次移除，不删除磁盘原图"))
                Button(G("半格")) { store.session.newPair(); store.leftVisible = true }.disabled(!store.session.canMakePair)
                Spacer()
                Button { store.copy() } label: { Label(G("复制参数"),systemImage:"doc.on.doc") }.disabled(!store.session.canCopySettings).help(G("复制当前照片的勾选参数；在旁边“参数范围”查看包含及保留项。"))
                Button { store.paste() } label: { Label(G("粘贴"),systemImage:"doc.on.clipboard") }.disabled(!store.session.canPasteSettings).help(G("粘贴复制时记录的参数分组；其他参数保留目标照片自己的值。"))
                Button { store.sync() } label: { Label(G("同步所选"),systemImage:"arrow.left.arrow.right") }.disabled(!store.session.canSyncSettings).help(G("按当前勾选范围，将当前照片参数同步到其他所选照片。"))
                Button { ProNumberControl.endEditing(); store.clipboardVisible.toggle() } label: { HStack(spacing:4) { Text(G("参数范围")); Image(systemName:store.clipboardVisible ? "chevron.up" : "chevron.down").font(.system(size:9)) } }.help(G("选择复制／同步的分组，并查看哪些参数会保留。"))
                Spacer(minLength:5)
                Button { store.step(-1) } label: { Image(systemName:"chevron.left") }.disabled(store.session.frames.count < 2)
                Text(store.currentIndex.map { "\($0+1) / \(store.session.frames.count)" } ?? "— / —").monospacedDigit().foregroundStyle(.secondary)
                Button { store.step(1) } label: { Image(systemName:"chevron.right") }.disabled(store.session.frames.count < 2)
            }.buttonStyle(.borderless).font(.system(size:11))
            if store.clipboardVisible {
                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:14) { ForEach(ClipboardGroup.offered) { group in Toggle(group.title,isOn:Binding(get:{ store.session.clipboardGroups.contains(group) },set:{ if $0 { store.session.clipboardGroups.insert(group) } else { store.session.clipboardGroups.remove(group) } })).toggleStyle(.checkbox) } }
                    Text(G("复制时记录勾选范围，粘贴沿用该范围；同步使用当前勾选范围。"))
                        .font(.system(size:10)).foregroundStyle(.secondary)
                    Label(G("各自保留：裁剪、日期、片边、镜头校正、成片调色。"), systemImage:"lock")
                        .font(.system(size:10)).foregroundStyle(.secondary)
                }.font(.system(size:11)).padding(.vertical,6)
            }
            if store.session.frames.isEmpty {
                HStack(spacing:8) { Image(systemName:"photo.on.rectangle.angled"); Text(G("装入照片后在这里切换、⌘ 多选和同步参数")) }.font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:.infinity).frame(height:20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing:9) {
                            ForEach(store.session.frames) { frame in
                                Button { store.select(frame.id,extend:(NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags).contains(.command)) } label: {
                                    VStack(spacing:4) {
                                        CropMaskedThumbnail(url:frame.id,geometry:store.session.thumbnailGeometry(for:frame.id)) { image in
                                            Group { if let image { Image(decorative:image,scale:1).resizable().scaledToFit() } else { Image(systemName:"photo") } }.frame(width:76,height:40)
                                        }
                                        Text(frame.id.lastPathComponent).font(.system(size:9)).lineLimit(1).truncationMode(.middle).frame(width:76)
                                    }.padding(4).background(store.session.isPicked(frame.id) ? Color.accentColor.opacity(0.15) : .clear,in:.rect(cornerRadius:9))
                                        .overlay { RoundedRectangle(cornerRadius:9).strokeBorder(store.session.selection == frame.id ? Color.accentColor : .clear,lineWidth:2) }
                                }.buttonStyle(.plain).id(frame.id)
                                    .overlay(alignment:.topTrailing) {
                                        Button { store.session.togglePick(frame.id) } label: {
                                            Image(systemName:store.session.isPicked(frame.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size:13,weight:.medium))
                                                .foregroundStyle(store.session.isPicked(frame.id) ? Color.accentColor : Color.secondary)
                                                .background(.regularMaterial,in:Circle())
                                        }.buttonStyle(.plain).padding(2)
                                            .accessibilityLabel((store.session.isPicked(frame.id) ? G("取消选择 ") : G("选择 "))+frame.id.lastPathComponent)
                                            .help(store.session.selection == frame.id ? G("当前预览照片保持选中；点击另一张可更换当前照片") : G("加入或移出所选照片，保留当前预览"))
                                            .disabled(store.session.selection == frame.id)
                                    }
                                    .contextMenu { ProPhotoContextMenu(store:store,url:frame.id) }
                                    .onDrag { store.session.draggedFrame = frame.id; return NSItemProvider(object:frame.id as NSURL) }
                                    .onDrop(of:[.fileURL],delegate:ProfessionalFrameDrop(session:store.session,target:frame.id))
                            }
                        }.padding(.vertical,3)
                    }.scrollIndicators(.hidden).frame(height:66)
                        .onChange(of:store.session.selection) { _,url in if let url { withAnimation(reduceMotion ? nil : .smooth(duration:0.2)) { proxy.scrollTo(url,anchor:.center) } } }
                }
            }
        }.padding(.horizontal,14).padding(.vertical,7).modifier(ProGlass(radius:17)).disabled(store.running)
            .animation(reduceMotion ? nil : .smooth(duration:0.22),value:store.clipboardVisible)
    }
}

struct ProfessionalFrameDrop: DropDelegate {
    let session: Session, target: URL
    func dropEntered(info: DropInfo) { if let source = session.draggedFrame { session.moveFrame(source,onto:target) } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: session.draggedFrame == nil ? .copy : .move) }
    func performDrop(info: DropInfo) -> Bool { guard session.draggedFrame != nil else { return false }; session.frameOrderChanged(); session.draggedFrame = nil; return true }
}
