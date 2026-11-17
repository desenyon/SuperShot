import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import Export
struct ExportTests {
    @Test func filenameCannotEscapeFolder() {
        let name = ImageExport.filename(source:"../Bad:Name/\n")
        #expect(!name.contains("/")); #expect(!name.contains(":")); #expect(!name.contains("\n")); #expect(name.hasSuffix(".png"))
    }
    @Test func automaticSaveNeverOverwritesExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let file=folder.appendingPathComponent("capture.png")
        let context=try #require(CGContext(data:nil,width:2,height:2,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let image=try #require(context.makeImage())
        try ImageExport.write(image,to:file)
        let original=try Data(contentsOf:file)
        #expect(throws:(any Error).self) { try ImageExport.write(image,to:file) }
        #expect(try Data(contentsOf:file) == original)
    }
    @Test func pngRoundTripKeepsDimensions() throws {
        let context = try #require(CGContext(data:nil,width:30,height:20,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let data = try ImageExport.encode(image)
        let source = try #require(CGImageSourceCreateWithData(data as CFData,nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source,0,nil))
        #expect(decoded.width == 30); #expect(decoded.height == 20)
    }
}

extension ExportTests {
    @Test func pairedExportsNeverReplaceAProjectAcrossFormats() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let png=folder.appendingPathComponent("capture.png"),jpeg=folder.appendingPathComponent("capture.jpg")
        let a=try ImageExport.writePair(image:Data([1]),project:Data([11]),to:png)
        let b=try ImageExport.writePair(image:Data([2]),project:Data([22]),to:jpeg)
        #expect(a.lastPathComponent == "capture.png")
        #expect(b.lastPathComponent == "capture (1).jpg")
        #expect(try Data(contentsOf:folder.appendingPathComponent("capture.supershot")) == Data([11]))
        #expect(try Data(contentsOf:folder.appendingPathComponent("capture (1).supershot")) == Data([22]))
    }
    @Test func pdfIsReadableAndRetinaResamplingHasExactDimensions() throws {
        let c=CGContext(data:nil,width:80,height:60,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image=c.makeImage()!,half=try ImageExport.transformed(image,factor:0.5,sRGB:true)
        #expect(half.width == 40 && half.height == 30)
        let pdf=try ImageExport.encode(half,type:"com.adobe.pdf")
        let doc=try #require(CGPDFDocument(CGDataProvider(data:pdf as CFData)!))
        #expect(doc.numberOfPages == 1)
        #expect(doc.page(at:1)?.getBoxRect(.mediaBox).size == CGSize(width:40,height:30))
    }
}

import AppKit

extension ExportTests {
    @Test @MainActor func clipboardRoundTripUsesAnIsolatedPasteboard() throws {
        let pasteboard = NSPasteboard(name: .init("SuperShotTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let writer = ClipboardWriter(pasteboard: pasteboard)
        let context = try #require(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let original = try ImageExport.encode(#require(context.makeImage()))
        #expect(try writer.write(original, type: "public.png", for: writer.begin()))
        let data = try #require(pasteboard.data(forType: .png))
        #expect(data == original)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 32 && image.height == 24)
    }
    @Test @MainActor func lateCopiesCannotReplaceNewerCopies() throws {
        let pasteboard = NSPasteboard(name: .init("SuperShotTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let writer = ClipboardWriter(pasteboard: pasteboard)
        let first = writer.begin(), second = writer.begin()
        #expect(try writer.write(Data([2]), type: "public.png", for: second))
        #expect(try !writer.write(Data([1]), type: "public.png", for: first))
        #expect(pasteboard.data(forType: .png) == Data([2]))
        let third = writer.begin()
        pasteboard.clearContents(); pasteboard.setString("Newer user copy", forType: .string)
        #expect(try !writer.write(Data([3]), type: "public.png", for: third))
        #expect(pasteboard.string(forType: .string) == "Newer user copy")
    }
    @Test @MainActor func invalidCopyDoesNotClearExistingClipboard() throws {
        let pasteboard = NSPasteboard(name: .init("SuperShotTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Keep me", forType: .string)
        let writer = ClipboardWriter(pasteboard: pasteboard), request = writer.begin()
        #expect(throws: ClipboardWriter.ClipboardError.self) { try writer.write(Data(), type: "public.png", for: request) }
        #expect(pasteboard.string(forType: .string) == "Keep me")
    }
}

extension ExportTests {
    @Test func unicodeFileNamesFitOnDiskAndTokensAreExpandedOnce() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let longTitle = String(repeating: "截图👩🏽‍💻", count: 100)
        for name in [ImageExport.filename(source: longTitle),
                     ImageExport.templateFilename("{window}", date: Date(), app: "App", window: longTitle, counter: 7, width: 10, height: 20, extensionName: "png")] {
            #expect(name.utf8.count < 255)
            let path = folder.appendingPathComponent(name)
            try Data([1, 2]).write(to: path)
            #expect(try Data(contentsOf: path) == Data([1, 2]))
        }
        let name = ImageExport.templateFilename("{app} {counter}", date: Date(), app: "Notes {counter}", window: "", counter: 7, width: 10, height: 20, extensionName: "png")
        #expect(name == "Notes {counter} 7.png")
    }
    @Test func invalidResamplingFactorsThrowInsteadOfTrapping() throws {
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        for factor in [Double.nan, .infinity, -.infinity, -1, 0, .greatestFiniteMagnitude] {
            #expect(throws: ImageExport.ExportError.self) { try ImageExport.transformed(image, factor: factor) }
        }
    }
}
