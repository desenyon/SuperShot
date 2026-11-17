import Testing
import Foundation
import CoreGraphics
import Recognition
import Document
@testable import AI

struct LocalAITests {
    func image()->CGImage {let c=CGContext(data:nil,width:400,height:300,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!;c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:400,height:300));return c.makeImage()!}
    @Test func annotateTargetsRecognizedTextAndRejectsMissingLabels() async throws {
        let provider=LocalAIProvider(),image=image(),recognition=RecognitionResult(text:[TextRegion(text:"Save",rect:CGRect(x:200,y:150,width:80,height:30))])
        let output=try await provider.perform(.annotate("point an arrow at the Save button"),image:image,recognition:recognition)
        guard case .layers(let layers)=output else {Issue.record("Expected annotation layers");return}
        #expect(layers.first?.points.last == CGPoint(x:240,y:165))
        await #expect(throws:AIError.self){try await provider.perform(.annotate("No such label"),image:image,recognition:recognition)}
    }
    @Test func csvQuotesCommasAndQuotesWithoutInventingValues() async throws {
        let recognition=RecognitionResult(text:[TextRegion(text:"Name",rect:CGRect(x:10,y:10,width:60,height:20)),TextRegion(text:"A, B",rect:CGRect(x:120,y:10,width:60,height:20)),TextRegion(text:"Say \"hello\"",rect:CGRect(x:10,y:40,width:90,height:20))])
        let result=try await LocalAIProvider().perform(.csv,image:image(),recognition:recognition)
        guard case .text(let text)=result else{Issue.record("Expected CSV text");return}
        #expect(text == "\"Name\",\"A, B\"\n\"Say \"\"hello\"\"\"")
    }
    @Test func patchEraseRejectsAnEntireImageSelection() {
        #expect(throws:AIError.self){try HealingFill.patch(image:image(),region:CGRect(x:0,y:0,width:400,height:300))}
    }
}
