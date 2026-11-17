import Foundation
import CoreGraphics
import ImageIO
let c=CGContext(data:nil,width:100,height:80,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
c.setFillColor(CGColor(red:0,green:1,blue:0,alpha:1));c.fill(CGRect(x:0,y:0,width:100,height:80))
c.setFillColor(CGColor(red:1,green:0,blue:0,alpha:1));c.fill(CGRect(x:10,y:40,width:80,height:30))
c.setFillColor(CGColor(red:0,green:0,blue:1,alpha:1));c.fill(CGRect(x:10,y:10,width:80,height:30))
c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:20,y:40,width:20,height:20))
let url=URL(fileURLWithPath:CommandLine.arguments[1])
let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
CGImageDestinationAddImage(destination,c.makeImage()!,nil)
if !CGImageDestinationFinalize(destination){exit(1)}
