import AppKit
import SwiftUI
import WebKit
import QuartzCore

/// Core Graphics on older systems asserts on invalid rounded-rectangle inputs.
/// Keep animation endpoints exact: the quintic can round above 1 by a few ulps,
/// making sin(q * pi) and the remaining material width slightly negative.
enum WorkspaceMorphGeometry {
    static func unit(_ value: Double) -> Double {
        value.isNaN ? 0 : max(0, min(1, value))
    }
    static func ease(_ value: Double) -> CGFloat {
        let x = unit(value)
        return CGFloat(unit(x*x*x*(x*(x*6-15)+10)))
    }
    static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite &&
        rect.origin.x.isFinite && rect.origin.y.isFinite &&
        rect.size.width.isFinite && rect.size.height.isFinite &&
        rect.size.width > 0 && rect.size.height > 0 &&
        rect.maxX.isFinite && rect.maxY.isFinite
    }
    static func cornerRadius(_ radius: CGFloat, in rect: CGRect) -> CGFloat {
        guard valid(rect), radius.isFinite else { return 0 }
        return max(0, min(radius, min(rect.width, rect.height) / 2))
    }
    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        guard valid(rect) else { return path }
        let radius = cornerRadius(radius, in: rect)
        if radius == 0 { path.addRect(rect) }
        else { path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius) }
        return path
    }
}

/// Keeps one real editor alive. Only presentation snapshots move; there is no
/// second Session, renderer, export queue, or alternate processing pipeline.
@MainActor final class WorkspaceMorphSurface: NSView {
    override var isFlipped: Bool { true }
    private(set) var editor: NSView!
    var staging = false
    func install(_ editor: NSView) {
        self.editor = editor
        wantsLayer = true; layer?.masksToBounds = true
        addSubview(editor); editor.frame = bounds
    }
    override func layout() {
        super.layout()
        if !staging, editor.frame != bounds { editor.frame = bounds }
        for view in subviews where view !== editor && view.frame != bounds { view.frame = bounds }
    }
}

struct WorkspaceMorphProbe: NSViewRepresentable {
    let name: String
    init(_ name: String) { self.name = name }
    func makeNSView(context: Context) -> WorkspaceMorphAnchor { WorkspaceMorphAnchor(name:name) }
    func updateNSView(_ view: WorkspaceMorphAnchor, context: Context) {}
}
@MainActor final class WorkspaceMorphAnchor: NSView {
    let name: String
    init(name: String) { self.name = name; super.init(frame:.zero) }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor final class WorkspaceMorphCoordinator {
    static private(set) var active = false
    static private(set) var resizing = false
    private var task: Task<Void,Never>?
    func start(to professional: Bool, store: WorkspaceStore,
               simple: SimpleCameraController?, targetFrame: CGRect? = nil,
               commit: @escaping @MainActor () -> Void) {
        guard !Self.active, let window = store.window,
              let surface = window.contentView as? WorkspaceMorphSurface else { return }
        if let targetFrame, professional == store.professional {
            resize(window:window,surface:surface,to:targetFrame,store:store,simple:simple)
            return
        }
        // Shift-click offers a slow presentation of the same motion, useful
        // when reviewing the transition without adding another UI control.
        let sourceProfessional = store.professional
        let duration = NSEvent.modifierFlags.contains(.shift) ? 2.8 : targetFrame == nil ? 0.72 : 0.52
        Self.active = true
        task = Task { @MainActor in
            let oldFrame = window.frame
            let fullScreen = window.styleMask.contains(.fullScreen)
            let cover = WorkspaceMorphView(frame:surface.bounds)
            let keyGuard = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.scrollWheel]) { event in
                // Keep native Close and Quit available; editing cannot change
                // the frame being carried between the two interfaces.
                if event.modifierFlags.contains(.command), ["q","w"].contains(event.charactersIgnoringModifiers ?? "") { return event }
                return event.window === window ? nil : event
            }
            defer {
                cover.removeFromSuperview()
                surface.staging = false; surface.editor.isHidden = false
                surface.editor.frame = surface.bounds
                surface.needsLayout = true; surface.layoutSubtreeIfNeeded()
                // Do not restore the source mode's limits: the simple maximum
                // would squeeze the professional destination after its morph.
                store.restoreWindow(keepCurrent:true)
                if let keyGuard { NSEvent.removeMonitor(keyGuard) }
                Self.active = false; self.task = nil
                store.rememberWindowFrame()
            }
            guard let source = await WorkspaceMorphSnapshot.capture(surface.editor,professional:sourceProfessional,store:store,simple:simple) else {
                commit()
                if let targetFrame { window.setFrame(targetFrame,display:true) }
                else { store.restoreWindow() }
                return
            }
            cover.source = source
            surface.addSubview(cover,positioned:.above,relativeTo:surface.editor)
            cover.needsDisplay = true; cover.displayIfNeeded()
            surface.staging = true
            window.contentMinSize = CGSize(width:1,height:1)
            window.contentMaxSize = CGSize(width:10000,height:10000)
            commit()
            let finalFrame = targetFrame ?? store.modeWindowFrame()
            surface.editor.frame = CGRect(origin:.zero,size:window.contentRect(forFrameRect:finalFrame).size)
            // Let SwiftUI mount the destination and WebKit finish its first
            // layout under the source cover. Neither window nor photo flashes.
            for _ in 0..<80 {
                try? await Task.sleep(for:.milliseconds(16))
                surface.editor.layoutSubtreeIfNeeded()
                if professional || simple?.morphReady == true { break }
            }
            try? await Task.sleep(for:.milliseconds(34))
            surface.editor.layoutSubtreeIfNeeded()
            if sourceProfessional && !professional {
                for _ in 0..<80 {
                    surface.editor.layoutSubtreeIfNeeded()
                    if await simple?.prepareMorphLayout() == true { break }
                    try? await Task.sleep(for:.milliseconds(16))
                }
            }
            let reusePhoto = sourceProfessional && !professional && source.photo != nil
            guard let target = await WorkspaceMorphSnapshot.capture(surface.editor,professional:professional,store:store,simple:simple,geometryOnlyPhoto:reusePhoto) else {
                window.setFrame(finalFrame,display:true); return
            }
            cover.target = target; cover.toProfessional = professional
            // The snapshots own presentation while moving. The live glass
            // interface must not composite behind them on every window resize.
            // Unhide and draw it explicitly before removing the final cover.
            surface.editor.isHidden = true
            CATransaction.flush()
            await WorkspaceDisplayAnimation.run(in:cover,duration:1.0/30.0) { _ in }
            Log.shared.info(.app,"workspace morph geometry",[
                .init("direction",sourceProfessional ? "professional-to-\(professional ? "professional" : "simple")" : "simple-to-\(professional ? "professional" : "simple")"),
                .init("source_canvas",NSStringFromRect(source.canvasRect ?? .zero)),
                .init("target_canvas",NSStringFromRect(target.canvasRect ?? .zero)),
                .init("source_photo",NSStringFromRect(source.photoRect ?? .zero)),
                .init("target_photo",NSStringFromRect(target.photoRect ?? .zero))])
            await WorkspaceDisplayAnimation.run(in:cover,duration:duration,preferHighRefresh:sourceProfessional && !professional) { t in
                let p = WorkspaceMorphView.ease(t)
                if !fullScreen { window.setFrame(WorkspaceMorphView.mix(oldFrame,finalFrame,p),display:false) }
                cover.frame = surface.bounds; cover.progress = t
            }
            if !fullScreen { window.setFrame(finalFrame,display:true) }
            surface.editor.frame = surface.bounds; surface.editor.isHidden = false
            surface.editor.layoutSubtreeIfNeeded()
            await WorkspaceMorphSnapshot.prepareLiveCanvas(in: surface.editor)
            CATransaction.flush()
            // Give the compositor a display turn after GPU completion. A
            // drawable's presented callback may never arrive while covered.
            await WorkspaceDisplayAnimation.run(in:cover,duration:1.0/30.0) { _ in }
        }
    }

    /// A ratio reset retains the same interface. Keep its complete live layer
    /// tree, including native glass and the camera's continuous metal deck.
    /// The mode-change snapshot pieces deliberately omit inter-panel space
    /// and cacheDisplay cannot capture every SwiftUI glass surface.
    private func resize(window:NSWindow, surface:WorkspaceMorphSurface, to target:CGRect,
                        store:WorkspaceStore, simple:SimpleCameraController?) {
        Self.active = true; Self.resizing = true
        task = Task { @MainActor in
            let duration = NSEvent.modifierFlags.contains(.shift) ? 2.8 : 0.52
            store.resizingWindow = true
            let guardEvents = NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.scrollWheel,.leftMouseDown]) { event in
                if event.modifierFlags.contains(.command), ["q","w"].contains(event.charactersIgnoringModifiers ?? "") { return event }
                return event.window === window ? nil : event
            }
            defer {
                Self.resizing = false
                store.session.viewportChanged()
                store.resizingWindow = false
                if let guardEvents { NSEvent.removeMonitor(guardEvents) }
                Self.active = false; self.task = nil
                store.rememberWindowFrame()
            }
            // AppKit owns the frame animation and its display transactions.
            // Repeated setFrame calls from a separate display link force the
            // hosting view and WindowServer to resize independently each tick.
            await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(controlPoints:0.76,0,0.24,1)
                    window.animator().setFrame(target,display:false)
                } completionHandler: { continuation.resume() }
            }
            window.setFrame(target,display:true)
            surface.layoutSubtreeIfNeeded()
            if !store.professional { _ = await simple?.prepareMorphLayout() }
            await WorkspaceMorphSnapshot.prepareLiveCanvas(in:surface.editor)
        }
    }
}

/// One display-synchronised clock for both mode changes and ratio resets.
/// Unlike a sleeping task, it follows the refresh rate of the current screen.
@MainActor private final class WorkspaceDisplayAnimation: NSObject {
    private var link: CADisplayLink?
    private var continuation: CheckedContinuation<Void,Never>?
    private var update: ((Double) -> Void)?
    private var began = 0.0, duration = 1.0
    private var lastTick = 0.0, maxInterval = 0.0, maxUpdate = 0.0
    private var frames = 0
    private var finished = false
    static func run(in view: NSView, duration: Double, preferHighRefresh: Bool = false, update: @escaping @MainActor (Double) -> Void) async {
        let animation = WorkspaceDisplayAnimation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !animation.finished else { continuation.resume(); return }
                animation.continuation = continuation
                animation.duration = duration; animation.began = CACurrentMediaTime()
                animation.update = update; update(0)
                let link = view.displayLink(target:animation,selector:#selector(tick(_:)))
                if preferHighRefresh {
                    let rate = Float(view.window?.screen?.maximumFramesPerSecond ?? 60)
                    link.preferredFrameRateRange = CAFrameRateRange(minimum:min(60,rate),maximum:rate,preferred:rate)
                }
                animation.link = link
                link.add(to:.main,forMode:.common)
            }
        } onCancel: { Task { @MainActor in animation.finish() } }
    }
    @objc private func tick(_ link: CADisplayLink) {
        let started = CACurrentMediaTime()
        if lastTick > 0 { maxInterval = max(maxInterval,started-lastTick) }
        lastTick = started; frames += 1
        let t = min(1,max(0,(link.targetTimestamp-began)/duration))
        update?(t)
        maxUpdate = max(maxUpdate,CACurrentMediaTime()-started)
        if t >= 1 { finish() }
    }
    private func finish() {
        guard !finished else { return }; finished = true
        link?.invalidate(); link = nil; update = nil
        if duration > 0.1 {
            Log.shared.info(.app,"workspace animation",[.init("frames",frames),
                .init("duration_ms",duration*1000),.init("max_interval_ms",maxInterval*1000),
                .init("max_update_ms",maxUpdate*1000)])
        }
        continuation?.resume(); continuation = nil
    }
}

@MainActor private struct WorkspaceMorphSnapshot {
    var image: NSImage
    var chrome: NSImage
    var size: CGSize
    var regions: [String:CGRect]
    var photo: NSImage?
    var photoRect: CGRect?
    var canvasRect: CGRect?
    var professional: Bool
    var dark: Bool

    static func capture(_ editor: NSView, professional: Bool, store: WorkspaceStore,
                        simple: SimpleCameraController?, geometryOnlyPhoto: Bool = false) async -> Self? {
        let size = editor.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }
        var regions: [String:CGRect] = [:]
        func walk(_ view: NSView) {
            if let anchor = view as? WorkspaceMorphAnchor {
                var rect = anchor.convert(anchor.bounds,to:editor)
                if !editor.isFlipped { rect.origin.y = size.height-rect.maxY }
                regions[anchor.name] = rect
            }
            for child in view.subviews { walk(child) }
        }
        walk(editor)
        var web: NSImage?
        if !professional, let view = simple?.webView {
            // These are live CSS boxes, not estimates tied to one resolution.
            let script = """
            (()=>{const out={},find=s=>{const e=document.querySelector(s);if(!e)return null;const r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}};
            for(const [k,s] of Object.entries({header:'.chrome',preview:'.viewfinder',canvas:'.photo',materials:'.roll-window',dial:'.film-drive',inspector:'.exposure-unit',effects:'.deck-effects',library:'.library-controls',output:'.export-controls',destination:'.destination-plate',tools:'.preview-toolbar'})){const r=find(s);if(r)out[k]=r}return out})()
            """
            if let raw = try? await view.evaluateJavaScript(script) as? [String:[String:Double]] {
                regions.removeAll()
                for (key,r) in raw { regions[key] = CGRect(x:r["x"] ?? 0,y:r["y"] ?? 0,width:r["width"] ?? 0,height:r["height"] ?? 0) }
                if let dial = regions.removeValue(forKey:"dial"), let film = regions["materials"] { regions["materials"] = dial.union(film) }
            }
            let configuration = WKSnapshotConfiguration()
            configuration.rect = view.bounds
            web = try? await view.takeSnapshot(configuration:configuration)
        }
        let base: NSImage
        if geometryOnlyPhoto, let web {
            // WebKit already supplied the complete camera chrome. There is no
            // need to recapture the hosting view or render the same photo again.
            base = web
        } else {
            guard let bitmap = editor.bitmapImageRepForCachingDisplay(in:editor.bounds) else { return nil }
            editor.effectiveAppearance.performAsCurrentDrawingAppearance {
                editor.cacheDisplay(in:editor.bounds,to:bitmap)
            }
            base = NSImage(size:size); base.addRepresentation(bitmap)
        }
        // The native canvas is inset from the camera's CSS aperture. Use its
        // actual bounds, so snapshot and live pixels meet at the same place.
        if let live = liveCanvas(in: editor), !live.isHiddenOrHasHiddenAncestor {
            var rect = live.convert(live.bounds, to: editor)
            if !editor.isFlipped { rect.origin.y = size.height - rect.maxY }
            regions["canvas"] = rect
            _ = await live.prepareTransitionFrame()
        }
        let canvas = regions["canvas"]
        let backingScale = editor.window?.backingScaleFactor ?? 2
        var rendered: NSImage?, photo: NSImage?, photoRect: CGRect?
        if geometryOnlyPhoto, store.session.selection != nil, let canvas {
            let picture = store.session.renderer.viewport.imageFrame
            if picture.width > 1, picture.height > 1 {
                photoRect = picture.offsetBy(dx:canvas.minX,dy:canvas.minY)
            }
        } else if store.session.selection != nil, (!professional || !store.proof), let canvas, canvas.width > 1, canvas.height > 1,
           let cg = store.session.renderer.renderOffscreen(size:canvas.size,backingScale:backingScale)?.makeCGImage() {
            rendered = NSImage(cgImage:cg,size:canvas.size)
            let v = store.session.renderer.viewport
            // Keep the whole photograph and its unclipped screen rectangle.
            // A crop of the visible area jumps when the other layout fits the
            // whole photo; the aperture, not the photo, owns that clipping.
            let picture = v.imageFrame
            if professional, picture.width > 1, picture.height > 1,
               CGRect(origin:.zero,size:canvas.size).insetBy(dx:-0.5,dy:-0.5).contains(picture),
               let pixels = cg.cropping(to:CGRect(x:picture.minX*backingScale,y:picture.minY*backingScale,
                                                 width:picture.width*backingScale,height:picture.height*backingScale)) {
                // Carry the pixels already visible in the professional canvas.
                // Re-fitting a second full-image render can change sampling at
                // the exact instant the photograph becomes a moving layer.
                photo = NSImage(cgImage:pixels,size:picture.size)
                photoRect = picture.offsetBy(dx:canvas.minX,dy:canvas.minY)
            } else if picture.width > 1, picture.height > 1 {
                let scale = min(1, 4096 / max(v.image.width, v.image.height))
                let pixels = CGSize(width: max(1, (v.image.width * scale).rounded()),
                                    height: max(1, (v.image.height * scale).rounded()))
                var full = v
                full.viewport = pixels; full.fit()
                if let whole = store.session.renderer.renderOffscreen(size: pixels, backingScale: 1,
                    viewportOverride: full)?.makeCGImage() {
                    photo = NSImage(cgImage: whole, size: v.image)
                    photoRect = picture.offsetBy(dx:canvas.minX,dy:canvas.minY)
                }
            }
        }
        // A WebKit snapshot preserves the camera textures; the original Metal
        // renderer supplies only the current display pixels, never a new edit.
        let image = NSImage(size:size,flipped:true) { rect in
            (web ?? base).draw(in:rect,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
            if let rendered, let canvas { rendered.draw(in:canvas,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil) }
            return true
        }
        // Force materialization now, before the underlying view is reconfigured.
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        // Pieces carry only the interface. Otherwise the stretched viewfinder
        // crop leaves duplicate strips of the old photo outside the moving
        // aperture, even though the main photo is drawn separately.
        let chrome = NSImage(size:size,flipped:true) { rect in
            (web ?? base).draw(in:rect,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
            if let canvas {
                NSColor(srgbRed: 0x5F/255.0, green: 0x5F/255.0, blue: 0x5F/255.0, alpha: 1).setFill()
                canvas.fill()
            }
            return true
        }
        guard let chromeCG = chrome.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        let dark = !professional || store.window?.effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua
        return Self(image:NSImage(cgImage:cg,size:size),chrome:NSImage(cgImage:chromeCG,size:size),size:size,regions:regions,photo:photo,photoRect:photoRect,canvasRect:canvas,professional:professional,dark:dark)
    }
    static func liveCanvas(in view: NSView) -> CanvasNSView? {
        if let canvas = view as? CanvasNSView { return canvas }
        for child in view.subviews { if let canvas = liveCanvas(in: child) { return canvas } }
        return nil
    }
    static func prepareLiveCanvas(in editor: NSView) async {
        for _ in 0..<8 {
            editor.layoutSubtreeIfNeeded()
            if let canvas = liveCanvas(in: editor), await canvas.prepareTransitionFrame() { return }
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
    func crop(_ rect: CGRect, interfaceOnly: Bool = false) -> NSImage? {
        guard let cg = (interfaceOnly ? chrome : image).cgImage(forProposedRect:nil,context:nil,hints:nil) else { return nil }
        let sx = CGFloat(cg.width)/size.width, sy = CGFloat(cg.height)/size.height
        guard let crop = cg.cropping(to:CGRect(x:rect.minX*sx,y:rect.minY*sy,width:rect.width*sx,height:rect.height*sy).integral) else { return nil }
        return NSImage(cgImage:crop,size:rect.size)
    }
}

/// Textures are uploaded once. Each refresh moves composited layers and masks;
/// it never resamples full-window screenshots in NSView.draw on the main thread.
@MainActor private final class WorkspaceMorphView: NSView {
    override var isFlipped: Bool { true }
    var source: WorkspaceMorphSnapshot?
    var target: WorkspaceMorphSnapshot? { didSet { preparePieces() } }
    var toProfessional = true
    var progress: Double = 0 { didSet { updateComposition() } }
    private struct Piece {
        let name: String, a: CGRect, b: CGRect
        let container: CALayer, before: CALayer, after: CALayer, afterImage: CALayer
        let cutout: CAShapeLayer, reveal: CAShapeLayer
        let beforeSize: CGSize?, afterSize: CGSize?
    }
    private var pieces: [Piece] = []
    private let scene = CALayer(), ground = CALayer(), leather = CALayer(), metal = CALayer()
    private let leatherMask = CAShapeLayer(), canvas = CALayer(), photograph = CALayer()
    private let beforeCanvas = CALayer(), afterCanvas = CALayer(), canvasReveal = CAShapeLayer()
    private var cameraFooterHeight: CGFloat = 0
    private var sameMode: Bool { source?.professional == target?.professional }
    private var reversingMode: Bool { source?.professional == true && target?.professional == false }
    private var motionSource: WorkspaceMorphSnapshot? { reversingMode ? target : source }
    private var motionTarget: WorkspaceMorphSnapshot? { reversingMode ? source : target }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func mouseDown(with event: NSEvent) {}
    override var acceptsFirstResponder: Bool { true }
    static func ease(_ t: Double) -> CGFloat { WorkspaceMorphGeometry.ease(t) }
    static func mix(_ a: CGRect,_ b: CGRect,_ t: CGFloat) -> CGRect {
        CGRect(x:a.minX+(b.minX-a.minX)*t,y:a.minY+(b.minY-a.minY)*t,width:a.width+(b.width-a.width)*t,height:a.height+(b.height-a.height)*t)
    }
    private func imageLayer(_ image: NSImage?, into layer: CALayer) {
        layer.contents = image?.cgImage(forProposedRect:nil,context:nil,hints:nil)
        layer.contentsGravity = .resize
        layer.minificationFilter = .trilinear; layer.magnificationFilter = .linear
    }
    private func tile(_ image: NSImage?, size: CGSize) -> CGImage? {
        guard let image else { return nil }
        let result = NSImage(size:size,flipped:true) { rect in
            NSColor(patternImage:image).setFill(); rect.fill(); return true
        }
        return result.cgImage(forProposedRect:nil,context:nil,hints:nil)
    }
    private func preparePieces() {
        guard let source = motionSource, let target = motionTarget else { return }
        wantsLayer = true
        if reversingMode { layerContentsRedrawPolicy = .never }
        guard let layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        scene.anchorPoint = .zero; scene.position = .zero; scene.masksToBounds = true
        layer.addSublayer(scene)
        for child in [ground,leather,metal] { scene.addSublayer(child) }
        leather.mask = leatherMask
        func regions(_ snapshot: WorkspaceMorphSnapshot) -> [String:CGRect] {
            var r = snapshot.regions
            if snapshot.professional {
                if let inspector = r["inspector"] {
                    let h = inspector.height*0.43
                    r["inspector"] = CGRect(x:inspector.minX,y:inspector.minY,width:inspector.width,height:h)
                    r["effects"] = CGRect(x:inspector.minX,y:inspector.minY+h,width:inspector.width,height:inspector.height-h)
                }
                if let output = r["output"] {
                    r["destination"] = CGRect(x:output.minX,y:output.minY,width:output.width*0.74,height:output.height)
                    r["output"] = CGRect(x:output.minX+output.width*0.74,y:output.minY,width:output.width*0.26,height:output.height)
                }
            }
            return r
        }
        let camera = source.professional ? target : source
        let extent = CGSize(width:max(source.size.width,target.size.width),height:max(source.size.height,target.size.height))
        if !sameMode || !source.professional {
            let top = camera.regions["header"]?.maxY ?? 65
            leather.contents = tile(camera.crop(CGRect(x:3,y:top+22,width:14,height:48)),size:extent)
            leather.frame = CGRect(origin:.zero,size:extent)
            let footerTop = ["library","effects","output"].compactMap { camera.regions[$0]?.minY }.min() ?? camera.size.height
            cameraFooterHeight = max(0,camera.size.height-footerTop+10)
            metal.contents = tile(camera.crop(CGRect(x:140,y:top-8,width:64,height:4)),size:CGSize(width:extent.width,height:max(1,cameraFooterHeight)))
        }
        let a = regions(source), b = regions(target)
        for name in ["preview","header","materials","inspector","effects","library","destination","output","tools"] {
            let ar = a[name], br = b[name]
            guard ar != nil || br != nil else { continue }
            let from = ar ?? CGRect(x:(br!.midX/target.size.width)*source.size.width,y:source.size.height-28,width:1,height:1)
            let to = br ?? CGRect(x:(ar!.midX/source.size.width)*target.size.width,y:target.size.height-28,width:1,height:1)
            let beforeImage = ar.flatMap { source.crop($0,interfaceOnly:true) }
            let afterImage = br.flatMap { target.crop($0,interfaceOnly:true) }
            let box = CALayer(), before = CALayer(), after = CALayer(), afterPixels = CALayer()
            let cutout = CAShapeLayer(), reveal = CAShapeLayer()
            cutout.fillRule = .evenOdd; cutout.fillColor = NSColor.black.cgColor
            reveal.fillColor = NSColor.black.cgColor
            box.mask = cutout; after.mask = reveal
            box.addSublayer(before); box.addSublayer(after); after.addSublayer(afterPixels)
            scene.addSublayer(box)
            imageLayer(beforeImage,into:before); imageLayer(afterImage,into:afterPixels)
            pieces.append(Piece(name:name,a:from,b:to,container:box,before:before,after:after,
                afterImage:afterPixels,cutout:cutout,reveal:reveal,beforeSize:beforeImage?.size,afterSize:afterImage?.size))
        }
        scene.addSublayer(canvas)
        canvas.masksToBounds = true
        canvas.backgroundColor = NSColor(srgbRed:0x5F/255.0,green:0x5F/255.0,blue:0x5F/255.0,alpha:1).cgColor
        canvas.addSublayer(beforeCanvas); canvas.addSublayer(afterCanvas); canvas.addSublayer(photograph)
        imageLayer(self.source?.photo,into:photograph)
        imageLayer(source.canvasRect.flatMap { source.crop($0) },into:beforeCanvas)
        imageLayer(target.canvasRect.flatMap { target.crop($0) },into:afterCanvas)
        afterCanvas.mask = canvasReveal; canvasReveal.fillColor = NSColor.black.cgColor
        CATransaction.commit()
        updateComposition()
    }
    override func draw(_ dirtyRect: NSRect) {
        // Only the waiting frame is drawn by AppKit; moving frames use layers.
        guard target == nil, let source else { return }
        source.image.draw(in:bounds,from:.zero,operation:.copy,fraction:1,respectFlipped:true,hints:nil)
    }
    private func fitted(_ image: CGSize?, in rect: CGRect, stretch: Bool) -> CGRect {
        guard !stretch, let image else { return rect }
        let scale = min(1,min(rect.width/max(1,image.width),rect.height/max(1,image.height)))
        return CGRect(x:rect.midX-image.width*scale/2,y:rect.midY-image.height*scale/2,width:image.width*scale,height:image.height*scale)
    }
    private func updateComposition() {
        guard let source = motionSource, let target = motionTarget else { return }
        // Use the accepted simple-to-professional choreography backwards,
        // including stagger, material boundary, panel waist and photo path.
        let progress = WorkspaceMorphGeometry.unit(reversingMode ? 1-self.progress : self.progress)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let p = Self.ease(progress)
        let size = CGSize(width:source.size.width+(target.size.width-source.size.width)*p,height:source.size.height+(target.size.height-source.size.height)*p)
        let stage = CGRect(origin:.zero,size:size)
        scene.bounds = stage
        scene.transform = CATransform3DMakeScale(bounds.width/max(1,size.width),bounds.height/max(1,size.height),1)
        let groundA = NSColor(white:source.dark ? 0.11 : 0.90,alpha:1)
        let groundB = NSColor(white:target.dark ? 0.11 : 0.90,alpha:1)
        let groundColor = groundA.blended(withFraction:p,of:groundB) ?? groundB
        ground.frame = stage; ground.backgroundColor = groundColor.cgColor
        leatherMask.frame = leather.bounds
        if sameMode {
            leatherMask.path = CGPath(rect:source.professional ? .zero : stage,transform:nil)
        } else if toProfessional || reversingMode {
            leatherMask.path = WorkspaceMorphGeometry.roundedRect(CGRect(x:0,y:0,width:stage.width*(1-p),height:stage.height),radius:28)
        } else { leatherMask.path = materialPath(stage,progress:p) }
        let footer = cameraFooterHeight*(sameMode ? (source.professional ? 0 : 1) : 1-p)
        metal.frame = CGRect(x:0,y:stage.height-footer,width:stage.width,height:footer)
        for piece in pieces {
            let delay:Double = sameMode ? 0 : piece.name == "header" ? 0 : piece.name == "preview" ? 0.02 : piece.name == "materials" ? 0.025 : 0.06
            let q = Self.ease((progress-delay)/(1-delay))
            var rect = Self.mix(piece.a,piece.b,q)
            if !sameMode, ["materials","inspector","effects"].contains(piece.name) {
                let waist = sin(q * .pi), centre = CGPoint(x:rect.midX,y:rect.midY)
                rect.size.width *= 1-waist*0.18
                rect.size.height *= 1-waist*(piece.name == "materials" ? 0.85 : 0.63)
                rect.origin = CGPoint(x:centre.x-rect.width/2,y:centre.y-rect.height/2)
                if piece.name == "materials" { rect.origin.y = max(62,rect.origin.y-waist*min(150,size.height*0.20)) }
            }
            let local = CGRect(origin:.zero,size:rect.size)
            let radius = WorkspaceMorphGeometry.cornerRadius(sameMode || piece.name == "header" ? 0 : sin(q * .pi)*18,in:local)
            piece.container.frame = rect; piece.container.backgroundColor = groundColor.cgColor
            piece.cutout.frame = local; piece.reveal.frame = local
            let clip = WorkspaceMorphGeometry.roundedRect(local,radius:radius)
            if piece.name == "preview", let a = source.canvasRect, let b = target.canvasRect {
                clip.addRect(Self.mix(a,b,q).offsetBy(dx:-rect.minX,dy:-rect.minY))
            }
            piece.cutout.path = clip
            let stretch = piece.name == "preview" || piece.name == "header"
            piece.before.frame = fitted(piece.beforeSize,in:local,stretch:stretch)
            // A window reset changes geometry, not material. Wiping between
            // two copies of the same panel duplicates labels as they reflow.
            piece.after.isHidden = sameMode
            piece.after.frame = local; piece.after.backgroundColor = groundB.cgColor
            piece.afterImage.frame = fitted(piece.afterSize,in:local,stretch:stretch)
            piece.reveal.path = materialPath(local,progress:Self.ease((progress-0.35)/0.30))
            piece.container.cornerRadius = radius
            piece.container.borderWidth = !sameMode && progress > 0.05 && progress < 0.96 && piece.name != "header" ? 0.8 : 0
            piece.container.borderColor = NSColor.white.withAlphaComponent(sin(CGFloat(progress) * .pi)*0.30).cgColor
        }
        if let ac = source.canvasRect, let bc = target.canvasRect {
            let q = Self.ease(sameMode ? progress : (progress-0.02)/0.98)
            let rect = Self.mix(ac,bc,q)
            canvas.frame = rect
            if self.source?.photo != nil, let a = source.photoRect, let b = target.photoRect {
                photograph.isHidden = false; beforeCanvas.isHidden = true; afterCanvas.isHidden = true
                photograph.frame = Self.mix(a,b,q).offsetBy(dx:-rect.minX,dy:-rect.minY)
            } else {
                photograph.isHidden = true; beforeCanvas.isHidden = false; afterCanvas.isHidden = false
                beforeCanvas.frame = CGRect(origin:.zero,size:rect.size); afterCanvas.frame = beforeCanvas.frame
                canvasReveal.frame = beforeCanvas.frame
                canvasReveal.path = materialPath(beforeCanvas.frame,progress:Self.ease((progress-0.35)/0.30))
            }
        }
    }
    private func materialPath(_ rect: CGRect,progress: CGFloat) -> CGPath {
        if progress >= 1 { return CGPath(rect:rect,transform:nil) }
        if progress <= 0 { return CGPath(rect:.zero,transform:nil) }
        let travel = rect.width+rect.height*0.32
        let forward = toProfessional || reversingMode
        let edge = forward ? rect.maxX-travel*progress : rect.minX+travel*progress
        let path = CGMutablePath()
        if forward {
            path.move(to:CGPoint(x:rect.maxX,y:rect.minY)); path.addLine(to:CGPoint(x:max(rect.minX,edge),y:rect.minY))
            path.addCurve(to:CGPoint(x:max(rect.minX,edge+rect.height*0.32),y:rect.maxY),control1:CGPoint(x:edge-rect.height*0.12,y:rect.midY),control2:CGPoint(x:edge+rect.height*0.44,y:rect.midY))
            path.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
        } else {
            path.move(to:rect.origin); path.addLine(to:CGPoint(x:min(rect.maxX,edge),y:rect.minY))
            path.addCurve(to:CGPoint(x:min(rect.maxX,edge-rect.height*0.32),y:rect.maxY),control1:CGPoint(x:edge+rect.height*0.12,y:rect.midY),control2:CGPoint(x:edge-rect.height*0.44,y:rect.midY))
            path.addLine(to:CGPoint(x:rect.minX,y:rect.maxY))
        }
        path.closeSubpath(); return path
    }
}
