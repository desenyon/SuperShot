import Foundation
import CoreGraphics

public enum StitchError: LocalizedError {
    case differentSizes, insufficientOverlap, imageTooTall, allocationFailed
    public var errorDescription:String? {
        switch self {
        case .differentSizes:"The capture area changed size. Start a new scrolling capture."
        case .insufficientOverlap:"Keep some of the previous content visible and scroll more slowly."
        case .imageTooTall:"This capture reached the 32,000-pixel height limit. Finish and start another capture."
        case .allocationFailed:"There is not enough memory to extend this capture."
        }
    }
}
public struct VerticalStitcher: Sendable {
    public private(set) var image:CGImage
    private var previous:CGImage
    public private(set) var frameCount=1
    public init(first:CGImage){image=first;previous=first}
    public mutating func append(_ next:CGImage) throws -> Bool {
        guard previous.width == next.width,previous.height == next.height else{throw StitchError.differentSizes}
        let shift=try Self.verticalShift(previous:previous,next:next)
        guard shift > 0 else{return false}
        guard image.height+shift<=32000,image.width*(image.height+shift)<=100_000_000 else{throw StitchError.imageTooTall}
        guard let tail=next.cropping(to:CGRect(x:0,y:next.height-shift,width:next.width,height:shift)),
              let context=CGContext(data:nil,width:image.width,height:image.height+shift,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw StitchError.allocationFailed}
        context.draw(image,in:CGRect(x:0,y:shift,width:image.width,height:image.height))
        context.draw(tail,in:CGRect(x:0,y:0,width:tail.width,height:tail.height))
        guard let output=context.makeImage() else{throw StitchError.allocationFailed}
        image=output;previous=next;frameCount+=1;return true
    }
    public static func verticalShift(previous:CGImage,next:CGImage) throws -> Int {
        guard previous.width == next.width,previous.height == next.height else{throw StitchError.differentSizes}
        let width=64,height=min(800,previous.height),a=try luminance(previous,width:width,height:height),b=try luminance(next,width:width,height:height)
        let margin=max(4,height/12)
        func difference(_ shift:Int)->Double {
            var sum=0.0,count=0
            let last=height-shift-margin
            guard last>margin else{return .infinity}
            for y in stride(from:margin,to:last,by:3) {for x in stride(from:6,to:width-6,by:3) {sum += abs(a[(y+shift)*width+x]-b[y*width+x]);count+=1}}
            return sum/Double(max(1,count))
        }
        let stationary=difference(0)
        if stationary<0.004 && previous.height<=800{return 0}
        var best=(shift:0,error:Double.infinity)
        var scores:[(Int,Double)]=[]
        for shift in stride(from:2,through:max(2,height*3/4),by:2) {let score=difference(shift);scores.append((shift,score));if score<best.error{best=(shift,score)}}
        for shift in max(1,best.shift-2)...min(height*3/4,best.shift+2) {let score=difference(shift);if score<best.error{best=(shift,score)}}
        let alternative=scores.filter{abs($0.0-best.shift)>max(6,height/100)}.map(\.1).min() ?? 1
        if previous.height<=800 {
            guard best.error<0.035,best.error<stationary*0.65,alternative>best.error*1.15+0.001 else{throw StitchError.insufficientOverlap}
            return best.shift
        }
        let fullHeight=previous.height,fa=try luminance(previous,width:width,height:fullHeight),fb=try luminance(next,width:width,height:fullHeight)
        let fullMargin=max(4,fullHeight/12)
        func fineDifference(_ shift:Int)->Double {
            var sum=0.0,count=0
            for y in stride(from:fullMargin,to:fullHeight-shift-fullMargin,by:3) {for x in stride(from:6,to:width-6,by:3) {sum += abs(fa[(y+shift)*width+x]-fb[y*width+x]);count+=1}}
            return count>0 ? sum/Double(count):.infinity
        }
        let fullStationary=fineDifference(0)
        if fullStationary<0.004{return 0}
        let estimate=Int((Double(best.shift)*Double(fullHeight)/Double(height)).rounded()),radius=max(3,Int(ceil(Double(fullHeight)/Double(height)))*3)
        var refined=(shift:estimate,error:Double.infinity)
        for shift in max(1,estimate-radius)...min(fullHeight*3/4,estimate+radius) {let score=fineDifference(shift);if score<refined.error{refined=(shift,score)}}
        guard refined.error<0.035,refined.error<fullStationary*0.65,alternative>refined.error*1.15+0.001 else{throw StitchError.insufficientOverlap}
        return refined.shift
    }
    private static func luminance(_ image:CGImage,width:Int,height:Int)throws->[Double]{
        var bytes=[UInt8](repeating:0,count:width*height*4)
        let success=bytes.withUnsafeMutableBytes{buffer->Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
            context.interpolationQuality = .medium;context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard success else{throw StitchError.allocationFailed}
        return stride(from:0,to:bytes.count,by:4).map{(Double(bytes[$0])*0.2126+Double(bytes[$0+1])*0.7152+Double(bytes[$0+2])*0.0722)/255}
    }
}

public actor ScrollAccumulator {
    private var stitcher:VerticalStitcher
    public init(first:CGImage){stitcher=VerticalStitcher(first:first)}
    public func append(_ image:CGImage)throws->(CGImage,Int,Bool){let changed=try stitcher.append(image);return(stitcher.image,stitcher.frameCount,changed)}
}
