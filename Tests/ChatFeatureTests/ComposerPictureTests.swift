import Foundation
import ImageIO
import Models
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import ChatFeature

/// Pictures as Photos and the camera hand them over, and a way to read a prepared one back.
enum PictureFixture {
    /// A flat picture, `width` × `height` pixels: opaque, or with its lower half transparent; PNG or JPEG.
    static func data(width: Int, height: Int, opaque: Bool = true, png: Bool = false) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let draw: (UIGraphicsImageRendererContext) -> Void = { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: opaque ? size.height : size.height / 2))
        }
        return png ? renderer.pngData(actions: draw) : renderer.jpegData(withCompressionQuality: 1, actions: draw)
    }

    /// A JPEG stored `width` × `height` whose EXIF orientation (6) says to show it turned a quarter clockwise — how an
    /// iPhone stores a portrait photo.
    static func rotatedJPEG(width: Int, height: Int) -> Data {
        let image = UIImage(data: data(width: width, height: height))!.cgImage!
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// The pixel size and type of a prepared picture, read back from its data URL.
    static func decoded(_ picture: ComposerPicture) -> (width: Int, height: Int, type: String)? {
        guard let base64 = picture.dataURL.split(separator: ",", maxSplits: 1).last,
            let data = Data(base64Encoded: String(base64)),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            let type = CGImageSourceGetType(source)
        else { return nil }
        return (width, height, type as String)
    }

    /// A picture already prepared; `n` tells them apart by their data URL.
    static func picture(_ n: Int = 0) -> ComposerPicture {
        ComposerPicture(mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,\(n)", pixelWidth: 1, pixelHeight: 1)
    }
}

@Suite("A picked picture, prepared for the wire")
struct ComposerPictureTests {
    @Test("a 12 MP photo comes out 2048 px on its longest side, as JPEG")
    func aLargePhotoIsCapped() throws {
        let picture = try ComposerPicture.prepare(PictureFixture.data(width: 4032, height: 3024))
        let out = try #require(PictureFixture.decoded(picture))
        #expect(out.width == 2048 && out.height == 1536)
        #expect(out.type == UTType.jpeg.identifier)
        #expect(picture.mimeType == "image/jpeg")
        #expect(picture.dataURL.hasPrefix("data:image/jpeg;base64,"))
        #expect(picture.pixelWidth == 2048 && picture.pixelHeight == 1536)
    }

    @Test("a portrait photo is capped on its height")
    func aPortraitPhotoIsCappedOnItsHeight() throws {
        let out = try #require(PictureFixture.decoded(try ComposerPicture.prepare(PictureFixture.data(width: 3024, height: 4032))))
        #expect(out.width == 1536 && out.height == 2048)
    }

    @Test("a photo stored turned, with its EXIF orientation, comes out upright")
    func aPhotoStoredTurnedComesOutUpright() throws {
        let out = try #require(PictureFixture.decoded(try ComposerPicture.prepare(PictureFixture.rotatedJPEG(width: 400, height: 300))))
        #expect(out.width == 300 && out.height == 400)
    }

    @Test("a small picture keeps its size")
    func aSmallPictureKeepsItsSize() throws {
        let out = try #require(PictureFixture.decoded(try ComposerPicture.prepare(PictureFixture.data(width: 800, height: 600))))
        #expect(out.width == 800 && out.height == 600)
    }

    @Test("a picture with transparency stays PNG")
    func transparencyStaysPNG() throws {
        let picture = try ComposerPicture.prepare(PictureFixture.data(width: 300, height: 200, opaque: false, png: true))
        let out = try #require(PictureFixture.decoded(picture))
        #expect(picture.mimeType == "image/png")
        #expect(picture.dataURL.hasPrefix("data:image/png;base64,"))
        #expect(out.type == UTType.png.identifier)
        #expect(out.width == 300 && out.height == 200)
    }

    @Test("an opaque PNG, such as a screenshot, becomes JPEG")
    func anOpaquePNGBecomesJPEG() throws {
        let picture = try ComposerPicture.prepare(PictureFixture.data(width: 300, height: 200, png: true))
        #expect(picture.mimeType == "image/jpeg")
    }

    @Test("what is not a picture is refused")
    func notAPicture() {
        #expect(throws: ComposerPicture.PrepareError.undecodable) {
            try ComposerPicture.prepare(Data("not a picture".utf8))
        }
    }
}

@Suite("The composer's pictures, at most ten")
struct ComposerAttachmentsTests {
    @Test("ten fit; the rest are turned away, in pick order")
    func tenFit() {
        var attachments = ComposerAttachments()
        let picked = (0..<12).map(PictureFixture.picture)
        #expect(attachments.append(picked) == 2)
        #expect(attachments.pictures == Array(picked.prefix(10)))
        #expect(attachments.isFull)
        #expect(attachments.room == 0)
    }

    @Test("the room left is what the photo picker may still add")
    func room() {
        var attachments = ComposerAttachments()
        #expect(attachments.isEmpty && attachments.room == 10)
        attachments.append((0..<3).map(PictureFixture.picture))
        #expect(attachments.room == 7)
        #expect(!attachments.isFull && !attachments.isEmpty)
    }

    @Test("removing one makes room for one")
    func removing() {
        var attachments = ComposerAttachments()
        let picked = (0..<10).map(PictureFixture.picture)
        attachments.append(picked)
        attachments.remove(picked[3].id)
        #expect(attachments.pictures.count == 9)
        #expect(!attachments.pictures.contains(picked[3]))
        #expect(attachments.append([PictureFixture.picture(99)]) == 0)
        #expect(attachments.isFull)
    }

    @Test("removeAll empties it")
    func removeAll() {
        var attachments = ComposerAttachments()
        attachments.append([PictureFixture.picture()])
        attachments.removeAll()
        #expect(attachments.isEmpty)
    }
}

@Suite("A question's content, as the desktop builds it")
struct ComposerContentTests {
    let first = ComposerPicture(mimeType: "image/jpeg", dataURL: "data:image/jpeg;base64,AAA", pixelWidth: 1, pixelHeight: 1)
    let second = ComposerPicture(mimeType: "image/png", dataURL: "data:image/png;base64,BBB", pixelWidth: 1, pixelHeight: 1)

    private func image(_ picture: ComposerPicture) -> JSONValue {
        .object(["type": .string("image"), "mimeType": .string(picture.mimeType), "data": .string(picture.dataURL)])
    }

    @Test("text alone is a plain string, as before")
    func textAlone() {
        #expect(ComposerContent.content(text: "hi", pictures: []) == .string("hi"))
    }

    @Test("pictures alone are image blocks, with no empty text block")
    func picturesAlone() {
        #expect(ComposerContent.content(text: "", pictures: [first, second]) == .array([image(first), image(second)]))
    }

    @Test("text and pictures: the text block first, then the pictures in order")
    func textAndPictures() {
        let content = ComposerContent.content(text: "Which is warmer?", pictures: [first, second])
        #expect(content == .array([.object(["type": .string("text"), "text": .string("Which is warmer?")]), image(first), image(second)]))
    }

    @Test("blank text with a picture adds no text block")
    func blankText() {
        #expect(ComposerContent.content(text: "  \n", pictures: [first]) == .array([image(first)]))
    }

    @Test("the message reads back as the transcript shows it")
    func readsBack() {
        let message = ChatMessage.userMessage(
            id: "u1", content: ComposerContent.content(text: "look", pictures: [first]), timestampMs: 0)
        #expect(message.contentBlocks == [.text("look"), .image(mimeType: "image/jpeg", dataURL: first.dataURL)])
        #expect(UserImages.dataURLs(of: message) == [first.dataURL])
    }
}
