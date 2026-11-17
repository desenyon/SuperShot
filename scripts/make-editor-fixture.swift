import Foundation
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
let w=1400,h=900
let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
func fill(_ rect:CGRect,_ r:CGFloat,_ g:CGFloat,_ b:CGFloat){c.setFillColor(CGColor(red:r,green:g,blue:b,alpha:1));c.fill(rect)}
func text(_ string:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:CGColor=CGColor(gray:0.14,alpha:1)){
 c.textPosition=CGPoint(x:x,y:y)
 let attrs:[NSAttributedString.Key:Any]=[NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("HelveticaNeue-Medium" as CFString,size,nil),NSAttributedString.Key(kCTForegroundColorAttributeName as String):color]
 CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string:string,attributes:attrs)),c)
}
fill(CGRect(x:0,y:0,width:w,height:h),0.96,0.95,0.92)
fill(CGRect(x:0,y:800,width:w,height:100),0.91,0.90,0.87)
text("FIELDNOTES",60,840,24);text("Workspace     Projects     Archive",760,840,22)
text("A clearer kind of work.",70,680,62)
text("Make room for the things that matter.",73,624,28,CGColor(gray:0.42,alpha:1))
fill(CGRect(x:70,y:270,width:820,height:280),1,1,1)
text("THIS WEEK",102,496,19,CGColor(gray:0.45,alpha:1))
text("Design review",102,432,30);text("Ready",690,432,24)
text("Prototype handoff",102,364,30);text("In progress",690,364,24)
text("Team notes",102,296,30);text("Done",690,296,24)
fill(CGRect(x:70,y:160,width:220,height:62),0.20,0.31,0.38);text("Save project",102,181,25,CGColor(gray:1,alpha:1))
text("hello@example.com",74,96,24,CGColor(gray:0.45,alpha:1))
text("A demonstration image for SuperShot",74,50,18,CGColor(gray:0.55,alpha:1))
let qr=CIFilter(name:"CIQRCodeGenerator",parameters:["inputMessage":Data("https://example.com/supershot".utf8),"inputCorrectionLevel":"M"])!.outputImage!
let transform=CGAffineTransform(scaleX:8,y:8),code=CIContext().createCGImage(qr.transformed(by:transform),from:qr.extent.applying(transform))!
fill(CGRect(x:1000,y:310,width:300,height:300),1,1,1);c.interpolationQuality = .none;c.draw(code,in:CGRect(x:1020,y:330,width:260,height:260))
text("A space to think.",1000,260,24)
let destination=CGImageDestinationCreateWithURL(URL(fileURLWithPath:CommandLine.arguments[1]) as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(destination,c.makeImage()!,nil);if !CGImageDestinationFinalize(destination){exit(1)}
