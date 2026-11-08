import SwiftUI

struct ProMaterials: View {
    @Bindable var store: WorkspaceStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var films: [Stock] {
        store.catalog.filmsForPicker.filter { store.search.isEmpty || ($0.name + (FilmGuide.entries[$0.id]?.subjects ?? "")).localizedCaseInsensitiveContains(store.search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text(G("胶片与相纸")).fontWeight(.semibold); Spacer(); Text(G("\(store.catalog.films.count) 款胶片")).font(.system(size: 10)).foregroundStyle(.secondary) }.padding(14)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(G("搜索胶片或题材"), text: $store.search).textFieldStyle(.plain)
                    }.font(.system(size: 12)).padding(8).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9)).padding(.horizontal, 12)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(films) { film in
                                    Button { ProNumberControl.endEditing(); store.chooseFilm(film) } label: {
                                        HStack(spacing: 5) {
                                            Text(film.name).lineLimit(1)
                                            Spacer(minLength: 0)
                                            if store.session.params.filmStock == film.id { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
                                        }.font(.system(size: 12)).padding(.horizontal, 9).padding(.vertical, 6)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).background(store.session.params.filmStock == film.id ? Color.accentColor.opacity(0.20) : .clear, in: .rect(cornerRadius: 8))
                                        .overlay { RoundedRectangle(cornerRadius:8).strokeBorder(store.session.params.filmStock == film.id ? Color.accentColor.opacity(0.65) : .clear,lineWidth:1).allowsHitTesting(false) }.id(film.id)
                                }
                            }.padding(.horizontal, 8)
                        }.frame(height: 174).padding(.vertical, 8)
                            .onAppear { proxy.scrollTo(store.session.params.filmStock, anchor: .center) }
                    }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Divider().opacity(0.45)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(store.film?.name ?? G("选择胶片")).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(store.film?.isPositive == true ? G("彩色反转片") : store.film?.isMonochrome == true ? G("黑白负片") : store.film?.isCine == true ? G("电影负片") : G("彩色负片")).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(store.guide?.character ?? "").font(.system(size: 12))
                        Text(store.guide?.subjects ?? "").font(.system(size: 11)).foregroundStyle(.secondary)
                        ProDetail(G("胶片介绍与使用提示")) {
                            Text(store.film?.isPositive == true ? G("反转片本身形成正像，使用胶片扫描路径，无需相纸印相。") : store.film?.isMonochrome == true ? G("黑白胶片搭配兼容的银盐相纸。物理画幅会影响颗粒尺度。") : G("通过相纸印相形成正常成片。胶片曝光作用于显影前；成片曝光作用于最终扫描结果。"))
                            Text(G("题材为选片建议；胶片型号中的感光度不会改变照片的拍摄 ISO。"))
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(14)
                    Divider().opacity(0.45)
                    ProSection(G("相纸与成像"), open: true) {
                        ProImagingPath(store: store)
                        Picker(G("成像方式"), selection: $store.route) {
                            Text(G("相纸印相 · 正常成片")).tag("print").disabled(store.session.filmIsPositive)
                            Text(store.session.filmIsPositive ? G("扫描 · 反转片正像") : G("扫描 · 保留负片")).tag("scan")
                            Text(G("DI · 数字中间片")).tag("di").disabled(store.session.filmIsPositive)
                        }.labelsHidden().disabled(store.session.noFilm)
                        Picker(G("相纸"), selection: Binding(get: { store.session.params.printStock }, set: { store.session.selectPrintStock($0) })) {
                            ForEach(store.catalog.papers) { paper in Text(paper.name).tag(paper.id).disabled(!store.catalog.canPrint(film: store.session.params.filmStock, on: paper.id)) }
                        }.labelsHidden().disabled(store.route != "print" || store.session.noFilm)
                        Text(store.route == "scan" && !store.session.filmIsPositive ? G("当前保留负像；选择相纸印相可得到正常成片。") : store.session.filmIsPositive ? G("反转片直接扫描形成正像，不需要相纸。") : G("点击“显影”可自动匹配曝光与相纸滤色。"))
                            .font(.system(size:11)).foregroundStyle(.secondary)
                        Button(store.session.filmIsPositive ? G("使用反转片扫描") : G("匹配预设相纸并印相"), action: store.matchPaper).disabled(store.session.noFilm)
                        ProDetail(G("成像选项")) {
                            Toggle(G("不应用胶片模拟"), isOn: Binding(get: { store.session.noFilm },set: { store.session.noFilm = $0 })).disabled(store.session.pair != nil)
                            Toggle(G("印相效果"), isOn: store.param(\.printEffects)).disabled(store.route != "print")
                            if store.route == "di" {
                                Toggle(G("蓝色补偿"), isOn: Binding(get: { store.session.diBlueCompensation },set: { store.session.diBlueCompensation = $0 }))
                            }
                            Text(G("显影：按当前测光方式重新求解曝光与滤色。成片调整在显影之后作用。")).font(.system(size:11)).foregroundStyle(.secondary)
                        }
                    }
                    EnlargerSection(session:store.session).disabled(store.route != "print" || store.session.noFilm)
                    FilmEdgeSection(session:store.session)
                    ProFinishing(store:store)
                    if store.session.pair != nil { PairSection(session:store.session) }
                }
            }.scrollIndicators(.automatic)
        }.frame(minWidth:0,maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).modifier(ProGlass()).disabled(store.running)
    }
}

struct ProInspector: View {
    @Bindable var store: WorkspaceStore
    @AppStorage(Session.decoupleEffectsKey) private var decoupleEffects = false
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(G("调整")).fontWeight(.semibold); Spacer()
                Text(store.currentIndex.map { G("仅第 \($0+1) 张") } ?? G("装入照片后调整")).font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(14)
            ScrollView {
                VStack(spacing:0) {
                    CameraSection(session:store.session)
                    HStack {
                        Button { store.session.wbPickerActive.toggle() } label: { Label(G("中性色"),systemImage:"eyedropper") }
                            .disabled(!store.session.shotIsRAW)
                        Menu(G("输入白平衡")) {
                            ForEach(DecodeSettings.WhiteBalance.allCases.filter { $0 != .custom }, id: \.self) { wb in
                                Button(wb.localizedTitle) { store.session.setWhiteBalance(wb) }
                            }
                        }.disabled(!store.session.shotIsRAW)
                    }.font(.system(size:11)).padding(12)
                    FilmFormatSection(session:store.session)
                    Toggle(G("独立调节效果强度"),isOn:$decoupleEffects).font(.system(size:11)).padding(13)
                    HStack { Text(G("成片调整")).fontWeight(.semibold); Spacer(); Toggle(G("启用成片调色"),isOn:store.adjustment(\.enabled)).labelsHidden().toggleStyle(.switch).controlSize(.mini) }.padding(14)
                    Group {
                        ExposureSection(session:store.session)
                        WhiteBalanceSection(session:store.session)
                        CurveSection(session:store.session)
                        ColorBalanceSection(session:store.session)
                    }.disabled(!store.session.layerAdjustments.enabled)
                    if FeatureFlags.toneMask { ToneMaskSection(session:store.session) }
                    if FeatureFlags.masks { MasksSection(session:store.session) }
                    LatitudeSection(session:store.session)
                    ScenePlacementSection(session:store.session)
                    CropSection(session:store.session)
                }
            }
        }.frame(minWidth:0,maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).modifier(ProGlass()).disabled(store.running || store.session.selection == nil)
    }
}
