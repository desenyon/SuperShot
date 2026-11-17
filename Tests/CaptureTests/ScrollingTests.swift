import Testing
import CoreGraphics
import Foundation
@testable import Capture

struct ScrollingTests {
    func fixture() -> CGImage {
        let width=180,height=1200
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<height {
            for x in stride(from:0,to:width,by:9) {
                let seed=(y*173+x*97+(y/23)*443)%997
                c.setFillColor(CGColor(red:Double(seed%239)/239,green:Double((seed*7)%251)/251,blue:Double((seed*13)%241)/241,alpha:1));c.fill(CGRect(x:x,y:y,width:9,height:1))
            }
        }
        return c.makeImage()!
    }
    @Test func stitchesKnownVerticalOverlapWithoutRepeatingPixels() throws {
        let full=fixture(),first=full.cropping(to:CGRect(x:0,y:0,width:180,height:600))!,second=full.cropping(to:CGRect(x:0,y:180,width:180,height:600))!
        #expect(try VerticalStitcher.verticalShift(previous:first,next:second) == 180)
        var stitcher=VerticalStitcher(first:first)
        #expect(try stitcher.append(second))
        #expect(stitcher.image.height == 780)
        let expected=full.cropping(to:CGRect(x:0,y:0,width:180,height:780))!
        func pixels(_ image:CGImage)->Data {
            let c=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            return Data(bytes:c.data!,count:image.width*image.height*4)
        }
        #expect(pixels(stitcher.image) == pixels(expected))
    }
    @Test func stationaryFrameIsNotDuplicated() throws {
        let image=fixture();var stitcher=VerticalStitcher(first:image)
        #expect(try !stitcher.append(image));#expect(stitcher.frameCount == 1)
    }
    @Test func mismatchedSizesFailExplicitly() throws {
        let image=fixture(),cropped=image.cropping(to:CGRect(x:0,y:0,width:90,height:600))!
        #expect(throws:StitchError.self){try VerticalStitcher.verticalShift(previous:image,next:cropped)}
    }
}

extension ScrollingTests {
    @Test func retinaStitchRefinesAnOddPixelOffset() throws {
        let c=CGContext(data:nil,width:180,height:2600,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in stride(from:0,to:2600,by:7) {
            let seed=(y*173)%997
            c.setFillColor(CGColor(red:Double(seed%239)/239,green:Double((seed*7)%251)/251,blue:Double((seed*13)%241)/241,alpha:1));c.fill(CGRect(x:0,y:y,width:180,height:7))
        }
        let full=c.makeImage()!,a=full.cropping(to:CGRect(x:0,y:0,width:180,height:1600))!,b=full.cropping(to:CGRect(x:0,y:241,width:180,height:1600))!
        #expect(try VerticalStitcher.verticalShift(previous:a,next:b) == 241)
    }
}
