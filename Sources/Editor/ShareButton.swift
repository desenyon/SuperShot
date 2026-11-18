import AppKit
import SwiftUI
import Render
import DesignSystem

struct ShareButton:NSViewRepresentable {
    let model:EditorModel
    func makeNSView(context:Context)->ShareControl{ShareControl(model:model)}
    func updateNSView(_ button:ShareControl,context:Context){button.isEnabled = !model.busy}
}
@MainActor final class ShareControl:NSButton {
    let model:EditorModel
    private var picker:NSSharingServicePicker?
    init(model:EditorModel){
        self.model=model;super.init(frame:.zero);image=Icons.image("square.and.arrow.up", size: 16);isBordered=false;target=self;action=#selector(share);toolTip="Share image"
    }
    required init?(coder:NSCoder){fatalError()}
    @objc private func share(){
        guard !model.busy else{return};model.busy=true
        let snapshot=model.document,multiplier=model.outputMultiplier
        Task {
            defer{model.busy=false}
            do {
                let image=try await Task.detached(priority:.userInitiated){try DocumentRenderer.render(snapshot,scale:multiplier)}.value
                let picker=NSSharingServicePicker(items:[NSImage(cgImage:image,size:.zero)]);self.picker=picker
                picker.show(relativeTo:bounds,of:self,preferredEdge:.minY)
            } catch {model.message=error.localizedDescription}
        }
    }
}
