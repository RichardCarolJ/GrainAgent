import SwiftUI
import AppKit

/// The image itself is the original Metal canvas, not an ImageIO stand-in.
struct ProCanvas: View {
    @Bindable var store: WorkspaceStore
    @State private var proofImage: SoftProof?
    @State private var proving = false
    var body: some View {
        GeometryReader { geo in
            ZStack {
                MetalCanvasView(host:store.session)
                if store.session.tool == .crop { CropOverlay(session:store.session) }
                else if FeatureFlags.masks && store.session.selectedMask != nil { MaskOverlay(session:store.session) }
                if store.session.pair != nil { PairOverlay(session:store.session) }
                ProfessionalCompareOverlay(session:store.session)
                if store.proof {
                    Rectangle().fill(Color(nsColor:.windowBackgroundColor))
                    if let proofImage {
                        Image(decorative:proofImage.displayImage,scale:1).resizable().scaledToFit()
                    }
                    if proving { ProgressView(G("生成输出打样…")).padding(12).grainGlass() }
                }
                if store.session.selection == nil {
                    VStack(spacing:12) {
                        Image(systemName:"photo.badge.plus").font(.system(size:34,weight:.ultraLight))
                        Text(G("拖入照片")).font(.system(size:20,weight:.medium))
                        Text(G("或使用顶部的“装入照片”")).font(.system(size:12)).foregroundStyle(.secondary)
                    }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
                }
            }
            .modifier(PairDrop(session:store.session))
            .overlay(alignment:.bottomTrailing) {
                if store.navigatorVisible, !store.session.isFit, store.session.selection != nil, !store.proof {
                    ProfessionalNavigator(session:store.session).frame(width:156,height:114).padding(8)
                }
            }
            .overlay(alignment:.topTrailing) {
                if store.session.selection != nil, !store.proof {
                    HistogramPlot(bins:store.session.histogram,channels:[.rgb],showGrid:false,showGround:false)
                        .frame(width:130,height:40).padding(6).background(.black.opacity(0.25),in:.rect(cornerRadius:6)).padding(7).allowsHitTesting(false)
                }
            }
            .overlay {
                if let why = store.session.serviceBlocked {
                    VStack(spacing:8) { Text(G("暂时无法处理照片")).fontWeight(.semibold); Text(G(why)).font(.system(size:12)); Button(G("重试")) { store.session.restartService() } }
                        .padding(20).frame(maxWidth:360).grainGlass()
                }
            }
            .overlay(alignment:.bottomLeading) {
                if let warning = store.session.memoryWarning {
                    VStack(alignment:.leading,spacing:6) {
                        Text(warning).font(.system(size:11))
                        HStack { Button(G("仍然处理")) { store.session.overrideMemoryWarning() }; Button(G("取消")) { store.session.dismissMemoryWarning() } }
                    }.padding(10).frame(maxWidth:360).grainGlass().padding(8)
                }
            }
            .clipped()
            .task(id:"\(store.proof)-\(store.proofRevision)-\(store.recipe.hashValue)-\(store.session.selection?.absoluteString ?? "")") {
                proofImage = nil
                guard store.proof, !store.running, store.session.selection != nil else { return }
                proving = true
                defer { proving = false }
                do { try await Task.sleep(for:.milliseconds(300)) } catch { return }
                guard let sid = await store.session.ensureDeveloped() else { return }
                do { try await store.session.professionalPrepareExport(sessionID:sid) } catch { return }
                let result = await store.session.softProofForDisplay(recipe:store.recipe,paneSize:geo.size)
                guard !Task.isCancelled else { return }
                proofImage = result
                if result == nil { store.notice = store.session.lastError ?? G("当前照片无法生成输出打样") }
            }
        }.allowsHitTesting(!store.running)
    }
}

struct ProfessionalCompareOverlay: View {
    @Bindable var session: Session
    @State private var grabOffset: CGFloat?
    var body: some View {
        GeometryReader { geo in
            let v = session.viewportSnapshot
            let w = v.image.width * v.scale
            let imageRect = CGRect(x:v.offset.x,y:v.offset.y,width:w,height:v.image.height*v.scale)
            let visible = imageRect.intersection(CGRect(origin:.zero,size:geo.size))
            if session.comparing && session.canCompare && w > 1 && !visible.isNull && !visible.isEmpty {
                let x = v.offset.x + session.comparePosition*w
                let gripX = x.clamped(to:min(22,geo.size.width/2)...max(22,geo.size.width-22))
                let middle = visible.midY.clamped(to:15...max(15,geo.size.height-15))
                ZStack(alignment:.topLeading) {
                    Path { p in p.move(to:CGPoint(x:x,y:visible.minY)); p.addLine(to:CGPoint(x:x,y:visible.maxY)) }
                        .stroke(.white.opacity(0.9),lineWidth:1).shadow(color:.black.opacity(0.6),radius:1).allowsHitTesting(false)
                    Color.clear.frame(width:18,height:visible.height).contentShape(Rectangle()).position(x:x,y:visible.midY)
                        .gesture(drag(width:w,offset:v.offset.x,gripX:x))
                    HStack(spacing:5) {
                        Image(systemName:"chevron.left"); Capsule().frame(width:2,height:13); Image(systemName:"chevron.right")
                    }.font(.system(size:10,weight:.semibold)).foregroundStyle(.white)
                        .frame(width:44,height:30).background(.black.opacity(0.65),in:Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.7),lineWidth:1))
                        .contentShape(Capsule()).position(x:gripX,y:middle)
                        .gesture(drag(width:w,offset:v.offset.x,gripX:gripX))
                        .accessibilityLabel(G("原图与成片对照分隔线"))
                        .accessibilityValue("\(Int(session.comparePosition*100))%")
                        .accessibilityAdjustableAction { direction in session.comparePosition += direction == .increment ? 0.05 : -0.05 }
                    if x-visible.minX > 56 { label(G("原图")).position(x:visible.minX+28,y:visible.minY+17) }
                    if visible.maxX-x > 56 { label(G("成片")).position(x:visible.maxX-28,y:visible.minY+17) }
                }.coordinateSpace(name:"nativeComparison")
            }
        }
    }
    private func label(_ s: String) -> some View {
        Text(s).font(.system(size:10,weight:.medium)).foregroundStyle(.white).padding(.horizontal,7).padding(.vertical,4).background(.black.opacity(0.5),in:Capsule()).allowsHitTesting(false)
    }
    private func drag(width:CGFloat,offset:CGFloat,gripX:CGFloat) -> some Gesture {
        DragGesture(minimumDistance:0,coordinateSpace:.named("nativeComparison"))
            .onChanged { g in
                if grabOffset == nil { grabOffset = g.startLocation.x - gripX }
                session.comparePosition = Double((g.location.x - (grabOffset ?? 0) - offset)/width).clamped(to:0...1)
            }.onEnded { _ in grabOffset = nil }
    }
}

struct ProfessionalNavigator: View {
    @Bindable var session: Session
    @State private var image: CGImage?
    @State private var dragOrigin: CGPoint?
    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width:geo.size.width-12,height:geo.size.height-12)
            let ratio = image.map { min(size.width/CGFloat($0.width),size.height/CGFloat($0.height)) } ?? 1
            let pic = CGRect(x:6+(size.width-CGFloat(image?.width ?? 0)*ratio)/2,y:6+(size.height-CGFloat(image?.height ?? 0)*ratio)/2,width:CGFloat(image?.width ?? 0)*ratio,height:CGFloat(image?.height ?? 0)*ratio)
            let v = session.viewportSnapshot
            let w = v.image.width*v.scale, h = v.image.height*v.scale
            let centre = CGPoint(x:(v.viewport.width/2-v.offset.x)/max(1,w),y:(v.viewport.height/2-v.offset.y)/max(1,h))
            let seen = CGRect(x:pic.minX-v.offset.x/max(1,w)*pic.width,y:pic.minY-v.offset.y/max(1,h)*pic.height,width:v.viewport.width/max(1,w)*pic.width,height:v.viewport.height/max(1,h)*pic.height).intersection(pic)
            ZStack {
                RoundedRectangle(cornerRadius:9).fill(.black.opacity(0.72))
                if let image {
                    Image(decorative:image,scale:1).resizable().frame(width:pic.width,height:pic.height).position(x:pic.midX,y:pic.midY)
                    Path { p in p.addRect(pic); if !seen.isNull { p.addRect(seen) } }.fill(.black.opacity(0.4),style:FillStyle(eoFill:true))
                    if !seen.isNull { Rectangle().path(in:seen).stroke(.white,lineWidth:1) }
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { g in
                    guard pic.width > 0,pic.height > 0 else { return }
                    if dragOrigin == nil { dragOrigin = seen.contains(g.startLocation) ? centre : CGPoint(x:(g.startLocation.x-pic.minX)/pic.width,y:(g.startLocation.y-pic.minY)/pic.height) }
                    if let origin = dragOrigin { session.centreView(onNormalised:CGPoint(x:origin.x+g.translation.width/pic.width,y:origin.y+g.translation.height/pic.height)) }
                }.onEnded { _ in dragOrigin = nil })
        }.task(id:session.selection) { await load() }
            .onChange(of:session.canvasGeometry) { _,_ in Task { await load() } }
            .onReceive(NotificationCenter.default.publisher(for:.thumbnailUpdated)) { n in if n.object as? URL == session.selection { Task { await load() } } }
    }
    private func load() async {
        guard let url = session.selection else { image = nil; return }
        let raw = await ThumbnailCache.shared.thumbnail(for:url,maxPixel:640)
        guard session.selection == url else { return }
        image = raw.flatMap { ThumbnailFraming.frame($0,by:session.tool == .crop ? .default : session.canvasGeometry) }
    }
}
