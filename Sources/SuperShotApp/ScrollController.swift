import AppKit
import SwiftUI
import Observation
import Capture
import DesignSystem
import ApplicationServices

@MainActor @Observable final class ScrollModel {
    var preview:CGImage
    var frames=1
    var message="Scroll slowly. The capture grows as you go."
    var stopped=false
    var autoScroll=false
    var finish:()->Void = {}
    var cancel:()->Void = {}
    init(image:CGImage){preview=image}
}
@MainActor final class ScrollController {
    private var panel:NSPanel?
    private var task:Task<Void,Never>?
    private var sessionID=UUID()
    private var model:ScrollModel?
    var isRunning:Bool {panel != nil}
    func start(first:CapturedImage,display:CGDirectDisplayID,area:CGRect,service:CaptureService,complete:@escaping(CapturedImage)->Void){
        guard panel == nil else{return}
        let token=UUID();sessionID=token
        let model=ScrollModel(image:first.image);self.model=model
        let accumulator=ScrollAccumulator(first:first.image)
        let panel=NSPanel(contentRect:CGRect(origin:.zero,size:CGSize(width:300,height:320)),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .floating;panel.isReleasedWhenClosed=false;panel.backgroundColor = .clear;panel.isOpaque=false;panel.isMovableByWindowBackground=true
        model.finish={ [weak self, weak model] in guard let model else{return};self?.stop();complete(CapturedImage(image:model.preview,scale:first.scale,source:"Scrolling capture")) }
        model.cancel={ [weak self] in self?.stop() }
        let host=NSHostingView(rootView:ScrollPanel(model:model));host.sizingOptions=[];panel.contentView=host;panel.setContentSize(CGSize(width:300,height:320))
        if let screen=NSScreen.underPointer {panel.setFrameOrigin(CGPoint(x:screen.visibleFrame.maxX-panel.frame.width-DS.xl,y:screen.visibleFrame.minY+DS.xl))}
        self.panel=panel;panel.orderFrontRegardless()
        task=Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for:.milliseconds(450))
                    let frame=try await service.screen(id:display)
                    guard !Task.isCancelled,let crop=frame.image.cropping(to:area) else{break}
                    let (image,count,changed)=try await accumulator.append(crop)
                    guard !Task.isCancelled else{break}
                    if changed{model.preview=image;model.frames=count;model.message="\(image.height) pixels captured"}
                    if model.autoScroll && AXIsProcessTrusted() {
                        let event=CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:-120,wheel2:0,wheel3:0)
                        let displayBounds=CGDisplayBounds(display)
                        event?.location=CGPoint(x:displayBounds.minX+area.midX/first.scale,y:displayBounds.minY+area.midY/first.scale)
                        event?.post(tap:.cghidEventTap)
                    }
                } catch is CancellationError {break}
                catch StitchError.insufficientOverlap {model.message="Scroll slowly; keep overlapping content visible."}
                catch {model.message=error.localizedDescription;model.stopped=true;break}
            }
            if self?.sessionID == token {self?.task=nil}
        }
    }
    private func stop(){task?.cancel();task=nil;panel?.close();panel=nil;model=nil}
}
struct ScrollPanel: View {
    @Bindable var model: ScrollModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: DS.md) {
            HStack(spacing: DS.sm) {
                Icon("scroll", size: DS.iconSize).foregroundStyle(.secondary)
                Text("Scrolling capture").font(DS.emphasis)
                Spacer()
                Text("\(model.preview.height) px").font(DS.mono).foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .opacity : .numericText())
            }
            ZStack {
                Image(decorative: model.preview, scale: 1).resizable().scaledToFit()
                    .id(model.frames).transition(DS.Motion.reveal(from: .bottom, reduceMotion: reduceMotion))
            }.animation(DS.Motion.gentle(reduceMotion), value: model.frames)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.card(scheme))
                .clipShape(RoundedRectangle(cornerRadius: DS.smallRadius, style: .continuous))
            Text(model.message).font(DS.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.sm) {
                Toggle("Auto-scroll", isOn: Binding(get: { model.autoScroll }, set: { enabled in
                    if enabled {
                        let granted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                        model.autoScroll = granted
                        if !granted { model.message = "Allow Accessibility for SuperShot, then turn on Auto-scroll." }
                    } else { model.autoScroll = false }
                })).toggleStyle(SwitchStyle(showsLabel: true)).disabled(model.stopped)
                Spacer()
            }
            Hairline()
            HStack {
                Button("Cancel", action: model.cancel).buttonStyle(QuietButtonStyle())
                Spacer()
                Button("Done", action: model.finish).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(DS.lg).modifier(GlassSurface()).padding(DS.sm)
    }
}
