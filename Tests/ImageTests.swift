import AppKit
import ImageIO

@main
struct ImageTests {
    static var checks = 0
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAILED: \(message)") }
        checks += 1
    }
    static func pixel(_ image: NSImage, x: Int, y: Int) -> [UInt8] {
        let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let context = CGContext(data: nil, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                                bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self) + (y * bitmap.width + x) * 4, count: 4))
    }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TypingPet-image-tests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("TYPINGPET_DATA_DIR", root.appendingPathComponent("data").path, 1)
        defer { PetImageLoader.clearCache(); try? FileManager.default.removeItem(at: root) }
        let apng = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAACGFjVEwAAAAFAAAAAEGtT2AAAAAaZmNUTAAAAAAAAAAEAAAABAAAAAAAAAAAAAEAZAAAFTvlywAAABJJREFUeJxj+M/A8B8ZM5AuAAA8QB/h4IF3tAAAABpmY1RMAAAAAQAAAAEAAAABAAAAAQAAAAEAAgBkAgCRKvAIAAAAEWZkQVQAAAACeJxjYPjP8B8ABAEB/2Ln6ZwAAAAaZmNUTAAAAAMAAAABAAAAAQAAAAIAAAACAAMAZAABrOck2QAAABFmZEFUAAAABHicY2Bg+P8fAAMCAf8Nue5hAAAAGmZjVEwAAAAFAAAAAQAAAAEAAAAAAAAAAAAEAGQBAFLiI4wAAAAPZmRBVAAAAAZ4nGNgAAIAAAUAAf/5Xd8AAAAaZmNUTAAAAAcAAAABAAAAAQAAAAIAAAACAAUAZAABI/tw6gAAABFmZEFUAAAACHicY/j/n6EBAAd+An9kGLSdAAAAAElFTkSuQmCC")!
        let poster = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAACGFjVEwAAAACAAAAAPONk3AAAAAPSURBVHicY/iPBhhIFwAAeDw/wVjuKagAAAAaZmNUTAAAAAAAAAAEAAAABAAAAAAAAAAAAAIAZAAAUpufGwAAABZmZEFUAAAAAXicY/jPwPAfGTOQLgAAPEAf4XJUpWMAAAAaZmNUTAAAAAIAAAAEAAAABAAAAAAAAAAAAAMAZAAAgm1lQgAAABVmZEFUAAAAA3icY2Bg+P8fFZMsAAAcYB/htBjLqAAAAABJRU5ErkJggg==")!
        let gif = Data(base64Encoded: "R0lGODlhBAAEAIEAAP8AAAAAAAAAAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQEAQAAACwAAAAABAAEAAAICQABCBxIsCCAgAAh+QQNAwACACwBAAEAAQABAIH/AAAAgAAAAAAAAAAIBAADBAQAIfkECQcAAgAsAQABAAIAAgCB/wAAAAD/AAAAAAAACAcAAQgQECAgACH5BAQLAAAALAAAAAAEAAQAgf8AAP//AAAAAAAAAAgJAAMAGEiwoMGAADs=")!
        func imported(_ bytes: Data, _ name: String) throws -> (String, PetAnimation) {
            let source = root.appendingPathComponent(name)
            try bytes.write(to: source)
            let result = try PetImageLoader.validateAndImport(source)
            expect(result != name, "UUID import filename")
            expect(URL(fileURLWithPath: result).pathExtension == source.pathExtension, "original extension preserved")
            expect(try! Data(contentsOf: PetFiles.images.appendingPathComponent(result)) == bytes, "original image bytes preserved")
            return (result, PetImageLoader.load(result)!)
        }
        let (animationName, animation) = try imported(apng, "delta.APnG")
        expect(animation.frames.count == 5, "APNG frame count")
        for (index, duration) in [0.01, 0.02, 0.03, 0.04, 0.05].enumerated() {
            expect(abs(animation.durations[index] - duration) < 0.00001, "APNG unclamped duration \(index)")
        }
        expect(abs(animation.totalDuration - 0.15) < 0.00001, "sum of actual frame durations")
        expect(animation.size == NSSize(width: 4, height: 4), "full canvas size")
        expect(pixel(animation.frames[1], x: 1, y: 1) == [0, 255, 0, 255], "APNG source patch")
        expect(pixel(animation.frames[2], x: 1, y: 1) == [255, 0, 0, 255], "APNG previous disposal")
        expect(pixel(animation.frames[3], x: 0, y: 0)[3] == 0, "APNG transparent source replacement")
        expect(pixel(animation.frames[4], x: 0, y: 0)[3] == 0, "APNG background disposal")
        expect(pixel(animation.frames[4], x: 2, y: 2) == [128, 128, 127, 255], "APNG over alpha blending")
        let (posterName, posterAnimation) = try imported(poster, "poster.png")
        expect(posterAnimation.frames.count == 2, "excluded poster is not a playback frame")
        expect(pixel(posterAnimation.frames[0], x: 0, y: 0) == [255, 0, 0, 255], "excluded-poster first frame")
        expect(pixel(posterAnimation.frames[1], x: 0, y: 0) == [0, 0, 255, 255], "excluded-poster second frame")
        expect(abs(posterAnimation.durations[0] - 0.02) < 0.00001, "excluded-poster timing")
        expect(pixel(PetImageLoader.thumbnail(posterName)!, x: 0, y: 0) == [255, 0, 0, 255], "poster thumbnail uses first displayed frame")
        let (_, gifAnimation) = try imported(gif, "delta.gif")
        expect(gifAnimation.frames.count == 4, "GIF frame count")
        for (index, duration) in [0.01, 0.03, 0.07, 0.11].enumerated() {
            expect(abs(gifAnimation.durations[index] - duration) < 0.00001, "GIF unclamped duration \(index)")
        }
        expect(pixel(gifAnimation.frames[2], x: 1, y: 1) == [255, 0, 0, 255], "GIF previous disposal")
        expect(pixel(gifAnimation.frames[3], x: 2, y: 2) == [255, 0, 0, 255], "GIF background disposal")
        let (_, staticImage) = try imported(png(width: 512, height: 256), "static.png")
        expect(staticImage.frames.count == 1, "static image")
        let thumbnail = PetImageLoader.thumbnail(animationName)!
        expect(max(thumbnail.size.width, thumbnail.size.height) <= 160, "bounded thumbnail")
        PetImageLoader.clearCache()
        expect(PetImageLoader.load(animationName)?.frames.count == 5, "reload animation after clearing cache")
        expect(PetImageLoader.load("../outside.png") == nil, "reject traversal names")
        func rejected(_ bytes: Data, _ name: String, contains message: String) throws {
            let source = root.appendingPathComponent(name)
            try bytes.write(to: source)
            let before = try FileManager.default.contentsOfDirectory(atPath: PetFiles.images.path).count
            do {
                _ = try PetImageLoader.validateAndImport(source)
                fatalError("Accepted invalid fixture: \(name)")
            } catch { expect(error.localizedDescription.contains(message), "expected rejection for \(name): \(error)") }
            expect(try! FileManager.default.contentsOfDirectory(atPath: PetFiles.images.path).count == before, "failed import writes no image")
        }
        try rejected(Data(), "empty.png", contains: "损坏")
        try rejected(Data(repeating: 0, count: 15 * 1024 * 1024 + 1), "large.png", contains: "15 MB")
        var broken = apng; broken[50] ^= 1
        try rejected(broken, "corrupt.png", contains: "损坏")
        try rejected(png(width: 4097, height: 1), "wide.png", contains: "4096")
        try rejected(repeatedAPNG(width: 2, height: 2, count: 301), "long.png", contains: "300")
        try rejected(repeatedAPNG(width: 1024, height: 1024, count: 40), "memory.png", contains: "128 MB")
        print("ImageTests: \(checks) checks passed (APNG/GIF pixels, disposal, blending, timing, poster exclusion, import integrity and resource limits).")
    }

    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }
    static func repeatedAPNG(width: Int, height: Int, count: Int) -> Data {
        let image = png(width: width, height: height)
        var header = Data(), compressed = Data(), offset = 8
        while offset < image.count {
            let length = Int(read32(image, offset)), type = read32(image, offset + 4)
            if type == 0x49484452 { header = Data(image[(offset + 8)..<(offset + 8 + length)]) }
            if type == 0x49444154 { compressed.append(image[(offset + 8)..<(offset + 8 + length)]) }
            offset += 12 + length
        }
        var output = Data([137, 80, 78, 71, 13, 10, 26, 10])
        chunk(0x49484452, header, into: &output)
        var control = Data(); write32(UInt32(count), into: &control); write32(0, into: &control)
        chunk(0x6163544C, control, into: &output)
        var sequence: UInt32 = 0
        for index in 0..<count {
            var frame = Data()
            for value in [sequence, UInt32(width), UInt32(height), 0, 0] { write32(value, into: &frame) }
            frame.append(contentsOf: [0, 1, 0, 60, 0, 0]); sequence += 1
            chunk(0x6663544C, frame, into: &output)
            if index == 0 { chunk(0x49444154, compressed, into: &output) }
            else {
                var frameData = Data(); write32(sequence, into: &frameData); sequence += 1
                frameData.append(compressed); chunk(0x66644154, frameData, into: &output)
            }
        }
        chunk(0x49454E44, Data(), into: &output)
        return output
    }
    static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
    static func write32(_ value: UInt32, into data: inout Data) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    static func chunk(_ type: UInt32, _ payload: Data, into output: inout Data) {
        write32(UInt32(payload.count), into: &output)
        let start = output.count; write32(type, into: &output); output.append(payload)
        var crc: UInt32 = 0xFFFFFFFF
        for byte in output[start...] {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB88320) }
        }
        write32(crc ^ 0xFFFFFFFF, into: &output)
    }
}
