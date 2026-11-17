import Testing
import Foundation
import CoreGraphics
import CoreText
import CoreImage
@testable import Recognition

struct RecognitionTests {
    @Test func fastRecognitionIncludesSmallTextOnLargeCaptures() async throws {
        let context = CGContext(data: nil, width: 1800, height: 1800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1800))
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 30, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
        context.textPosition = CGPoint(x: 80, y: 900)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "SuperShot ordinary interface text", attributes: attributes)), context)
        let result = try await RecognitionService().recognize(try #require(context.makeImage()))
        #expect(result.transcript.localizedCaseInsensitiveContains("SuperShot ordinary interface text"))
    }
    @Test func realVisionRecognizesTextAndQRCode() async throws {
        let c=CGContext(data:nil,width:1200,height:500,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:1200,height:500))
        let attrs:[NSAttributedString.Key:Any]=[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,44,nil),NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)]
        c.textPosition=CGPoint(x:40,y:380);CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:"SuperShot local recognition",attributes:attrs)),c)
        c.textPosition=CGPoint(x:40,y:300);CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:"hello@example.com",attributes:attrs)),c)
        let qr=CIFilter(name:"CIQRCodeGenerator",parameters:["inputMessage":Data("https://example.com/supershot".utf8),"inputCorrectionLevel":"M"])!.outputImage!
        let code=CIContext().createCGImage(qr.transformed(by:CGAffineTransform(scaleX:8,y:8)),from:qr.extent.applying(CGAffineTransform(scaleX:8,y:8)))!
        c.interpolationQuality = .none;c.draw(code,in:CGRect(x:850,y:40,width:280,height:280))
        let image=try #require(c.makeImage())
        let result=try await RecognitionService().recognize(image,accurate:true)
        #expect(result.transcript.contains("SuperShot"))
        #expect(result.transcript.contains("hello@example.com"))
        #expect(result.codes.contains{$0.payload == "https://example.com/supershot"})
        let text=try #require(result.text.first{$0.text.contains("SuperShot")})
        #expect(text.rect.midY < 200)
    }
    @Test func redactionFindsSensitiveTextAndFacesButNotOrdinaryWords() {
        let bounds=CGRect(x:10,y:20,width:200,height:30)
        let result=RecognitionResult(text:[TextRegion(text:"hello@example.com",rect:bounds),TextRegion(text:"Call +1 415 555 0123",rect:bounds),TextRegion(text:"sk_demo_12345678901234567890",rect:bounds),TextRegion(text:"A calm place to work",rect:bounds)],faces:[bounds])
        #expect(SensitiveContent.candidates(in:result).count == 4)
    }
}
