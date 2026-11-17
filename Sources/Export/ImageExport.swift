import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageExport {
    public struct Format: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let extensionName: String
    }
    public static var formats: [Format] {
        let supported = CGImageDestinationCopyTypeIdentifiers() as! [String]
        let preferred = ["public.png", "public.jpeg", "public.heic", "public.tiff", "org.webmproject.webp", "public.avif"]
        return preferred.filter(supported.contains).compactMap { id in
            guard let type = UTType(id), let ext = type.preferredFilenameExtension else { return nil }
            return Format(id: id, name: ext.uppercased(), extensionName: ext)
        } + [Format(id: "com.adobe.pdf", name: "PDF", extensionName: "pdf")]
    }
    public static func encode(_ image: CGImage, type: String = "public.png", quality: Double = 1) throws -> Data {
        let data = NSMutableData()
        if type == "com.adobe.pdf" {
            var rect = CGRect(x:0,y:0,width:image.width,height:image.height)
            guard let consumer = CGDataConsumer(data:data),let context = CGContext(consumer:consumer,mediaBox:&rect,nil) else { throw ExportError.encodingFailed }
            context.beginPDFPage(nil); context.draw(image,in:rect); context.endPDFPage(); context.closePDF()
            return data as Data
        }
        guard let destination = CGImageDestinationCreateWithData(data, type as CFString, 1, nil) else { throw ExportError.unsupportedFormat }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: max(0,min(1,quality))] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return data as Data
    }
    public static func write(_ image: CGImage, to destination: URL, type: String = "public.png", quality: Double = 1, overwrite: Bool = false) throws {
        let data = try encode(image, type:type, quality:quality)
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try data.write(to:destination,options:overwrite ? .atomic : .withoutOverwriting)
    }
    public static func filename(date: Date = Date(), source: String = "Screenshot", extensionName: String = "png") -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        let safe = byteLimited(source.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator:"-"), limit: 180)
        return "\(safe.isEmpty ? "Screenshot" : String(safe)) \(formatter.string(from:date)).\(extensionName)"
    }
    public static func transformed(_ image: CGImage, factor: Double = 1, sRGB: Bool = false) throws -> CGImage {
        guard factor.isFinite, factor > 0 else { throw ExportError.encodingFailed }
        guard factor != 1 || sRGB else { return image }
        let scaledWidth = (Double(image.width) * factor).rounded(), scaledHeight = (Double(image.height) * factor).rounded()
        guard scaledWidth.isFinite, scaledHeight.isFinite, scaledWidth <= 32768, scaledHeight <= 32768 else { throw ExportError.encodingFailed }
        let width=max(1,Int(scaledWidth)),height=max(1,Int(scaledHeight))
        guard width<=32768,height<=32768,width*height<=160_000_000 else { throw ExportError.encodingFailed }
        let colorSpace = sRGB || image.colorSpace?.model != .rgb ? CGColorSpace(name:CGColorSpace.sRGB)! : (image.colorSpace ?? CGColorSpaceCreateDeviceRGB())
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:colorSpace,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExportError.encodingFailed }
        context.interpolationQuality = .high;context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        guard let result=context.makeImage() else {throw ExportError.encodingFailed};return result
    }
    public static func templateFilename(_ template: String, date: Date, app: String, window: String, counter: Int, width: Int, height: Int, extensionName: String) -> String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyy-MM-dd"
        let day=formatter.string(from:date);formatter.dateFormat="HH.mm.ss"
        var output = ""
        let replacements=["date":day,"time":formatter.string(from:date),"app":app,"window":window,"counter":String(counter),"size":"\(width)x\(height)"]
        // Parse only the template, never token-shaped text inside an app/window title.
        var cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let value = replacements[String(template[template.index(after: cursor)..<end])] {
                output += value; cursor = template.index(after: end)
            } else { output.append(template[cursor]); cursor = template.index(after: cursor) }
        }
        output=output.components(separatedBy:CharacterSet(charactersIn:"/:\\").union(.controlCharacters)).joined(separator:"-").trimmingCharacters(in:.whitespacesAndNewlines)
        while output.hasPrefix(".") {output.removeFirst()}
        let stem = byteLimited(output.isEmpty ? "Screenshot" : output, limit: 180)
        return (stem.isEmpty ? "Screenshot" : stem)+"."+extensionName
    }
    private static func byteLimited(_ text: String, limit: Int) -> String {
        var result = "", count = 0
        for character in text {
            let bytes = String(character).utf8.count
            guard count + bytes <= limit else { break }
            result.append(character); count += bytes
        }
        return result
    }
    public static func writeUnique(_ data: Data, to destination: URL) throws -> URL {
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        for number in 0..<10000 {
            let target = number == 0 ? destination : destination.deletingLastPathComponent().appendingPathComponent(destination.deletingPathExtension().lastPathComponent+" (\(number))."+destination.pathExtension)
            do {try data.write(to:target,options:.withoutOverwriting);return target}
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {continue}
        }
        throw ExportError.encodingFailed
    }
    /// Reserves a common free basename for both files. Existing projects are never replaced.
    public static func writePair(image:Data,project:Data,to destination:URL)throws->URL {
        let folder=destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        for number in 0..<10000 {
            let stem=destination.deletingPathExtension().lastPathComponent+(number == 0 ? "":" (\(number))")
            let target=folder.appendingPathComponent(stem).appendingPathExtension(destination.pathExtension)
            let sidecar=folder.appendingPathComponent(stem).appendingPathExtension("supershot")
            if FileManager.default.fileExists(atPath:sidecar.path){continue}
            do {try image.write(to:target,options:.withoutOverwriting)}
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {continue}
            do {try project.write(to:sidecar,options:.withoutOverwriting);return target}
            catch {
                try? FileManager.default.removeItem(at:target)
                let nsError=error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteFileExistsError {continue}
                throw error
            }
        }
        throw ExportError.encodingFailed
    }
    public enum ExportError: LocalizedError {
        case unsupportedFormat, encodingFailed
        public var errorDescription: String? { self == .unsupportedFormat ? "This image format is not supported on your Mac." : "The image could not be encoded." }
    }
}
