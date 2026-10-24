import AppKit
import ImageIO

struct PetAnimation {
    let frames: [NSImage]
    let durations: [TimeInterval]
    var size: NSSize { frames.first?.size ?? .zero }
    var totalDuration: TimeInterval { durations.reduce(0, +) }
}

enum PetImageError: LocalizedError {
    case unreadable, unsupported, corrupt, fileTooLarge, tooManyFrames, dimensions, memoryLimit
    var errorDescription: String? {
        switch self {
        case .unreadable: return "无法读取图片，请选择本机上的图片文件。"
        case .unsupported: return "不支持此图片格式，请使用 PNG、APNG、GIF、JPEG、WebP、BMP、TIFF 或 HEIC。"
        case .corrupt: return "图片不完整或已损坏，无法安全导入。"
        case .fileTooLarge: return "图片不能超过 15 MB。"
        case .tooManyFrames: return "动画不能超过 300 帧。"
        case .dimensions: return "图片宽高不能超过 4096 像素。"
        case .memoryLimit: return "图片解码后过大，请缩小尺寸或减少动画帧数（最多 128 MB）。"
        }
    }
}

enum PetImageLoader {
    private static let maximumFileBytes = 15 * 1024 * 1024
    private static let maximumFrames = 300
    private static let maximumDimension = 4096
    private static let maximumDecodedBytes = 128 * 1024 * 1024
    private static let cacheLimit = 128 * 1024 * 1024
    private static let lock = NSLock()
    private static var cache: [String: CacheEntry] = [:]
    private static var cacheBytes = 0
    private static var access: UInt64 = 0
    private static let thumbnails: NSCache<NSString, NSImage> = {
        let result = NSCache<NSString, NSImage>()
        result.countLimit = 64
        result.totalCostLimit = 8 * 1024 * 1024
        return result
    }()

    private struct CacheEntry {
        let animation: PetAnimation
        let cost: Int
        var access: UInt64
    }
    private struct Source {
        let image: CGImageSource
        let firstIndex: Int
        let frameCount: Int
        let width: Int
        let height: Int
        let animated: Bool
    }

    /// Decodes every frame before writing an immutable, uniquely named original file.
    static func validateAndImport(_ url: URL) throws -> String {
        let original = try read(url)
        let animation = try decode(original)
        let ext = url.pathExtension
        guard ext.count <= 12, ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            throw PetImageError.unsupported
        }
        let name = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        try PetFiles.prepare()
        let destination = PetFiles.images.appendingPathComponent(name)
        try original.write(to: destination, options: .atomic)
        remember(animation, key: destination.path)
        return name
    }

    static func load(_ name: String) -> PetAnimation? {
        guard let url = PetFiles.imageURL(name) else { return nil }
        if let animation = cached(url.path) { return animation }
        do {
            let animation = try decode(read(url))
            remember(animation, key: url.path)
            return animation
        } catch {
            PetFiles.log("图片读取失败（\(url.lastPathComponent)）：\(error.localizedDescription)")
            return nil
        }
    }

    /// Thumbnails decode only the first displayed frame, rather than an entire animation.
    static func thumbnail(_ name: String) -> NSImage? {
        guard let url = PetFiles.imageURL(name) else { return nil }
        if let image = thumbnails.object(forKey: url.path as NSString) { return image }
        do {
            let source = try prepare(read(url))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source.image, source.firstIndex, options as CFDictionary) else {
                return nil
            }
            let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            thumbnails.setObject(result, forKey: url.path as NSString, cost: image.width * image.height * 4)
            return result
        } catch { return nil }
    }

    static func clearCache() {
        lock.lock()
        cache.removeAll()
        cacheBytes = 0
        lock.unlock()
        thumbnails.removeAllObjects()
    }

    private static func cached(_ key: String) -> PetAnimation? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = cache[key] else { return nil }
        access &+= 1
        entry.access = access
        cache[key] = entry
        return entry.animation
    }

    private static func remember(_ animation: PetAnimation, key: String) {
        let cost = Int(animation.size.width) * Int(animation.size.height) * 4 * animation.frames.count
        guard cost <= cacheLimit else { return }
        lock.lock(); defer { lock.unlock() }
        if let previous = cache.removeValue(forKey: key) { cacheBytes -= previous.cost }
        while cacheBytes + cost > cacheLimit || cache.count >= 12 {
            guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
            cacheBytes -= oldest.value.cost
            cache.removeValue(forKey: oldest.key)
        }
        access &+= 1
        cache[key] = CacheEntry(animation: animation, cost: cost, access: access)
        cacheBytes += cost
    }

    private static func read(_ url: URL) throws -> Data {
        guard url.isFileURL else { throw PetImageError.unreadable }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw PetImageError.unreadable }
        guard (values.fileSize ?? 0) <= maximumFileBytes else { throw PetImageError.fileTooLarge }
        // Reading at most limit + 1 also bounds memory if the source changes during import.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileBytes + 1) ?? Data()
        guard data.count <= maximumFileBytes else { throw PetImageError.fileTooLarge }
        guard !data.isEmpty else { throw PetImageError.corrupt }
        return data
    }

    private static func prepare(_ original: Data) throws -> Source {
        let png = try normalizePNG(original)
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false, kCGImageSourceShouldAllowFloat: false]
        guard let image = CGImageSourceCreateWithData(png.data as CFData, options as CFDictionary),
              let type = CGImageSourceGetType(image) as String? else { throw PetImageError.unsupported }
        let supported = ["public.png", "com.compuserve.gif", "public.jpeg", "org.webmproject.webp", "public.webp", "com.microsoft.bmp", "public.tiff", "public.heic", "public.heif", "public.avif"]
        guard supported.contains(type) else { throw PetImageError.unsupported }
        guard CGImageSourceGetStatus(image) == .statusComplete else { throw PetImageError.corrupt }
        let count = CGImageSourceGetCount(image)
        guard count > png.firstIndex else { throw PetImageError.corrupt }
        guard count - png.firstIndex <= maximumFrames else { throw PetImageError.tooManyFrames }
        if let declared = png.declaredFrames, declared != count - png.firstIndex { throw PetImageError.corrupt }
        let animated = count - png.firstIndex > 1 && ["public.png", "com.compuserve.gif", "org.webmproject.webp", "public.webp"].contains(type)
        let frameCount = animated ? count - png.firstIndex : 1
        var width = 0, height = 0
        for index in png.firstIndex..<(png.firstIndex + frameCount) {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(image, index, nil) as? [CFString: Any],
                  let w = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let h = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { throw PetImageError.corrupt }
            try checkDimensions(w, h)
            width = max(width, w); height = max(height, h)
        }
        guard width * height * frameCount * 4 <= maximumDecodedBytes else { throw PetImageError.memoryLimit }
        return Source(image: image, firstIndex: png.firstIndex, frameCount: frameCount, width: width, height: height, animated: animated)
    }

    private static func decode(_ data: Data) throws -> PetAnimation {
        let source = try prepare(data)
        var frames: [NSImage] = [], durations: [TimeInterval] = []
        for index in source.firstIndex..<(source.firstIndex + source.frameCount) {
            let frame: NSImage = try autoreleasepool {
                let image: CGImage?
                if source.animated {
                    // ImageIO returns complete canvas frames, including GIF/APNG disposal and blending.
                    image = CGImageSourceCreateImageAtIndex(source.image, index, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                } else {
                    image = CGImageSourceCreateThumbnailAtIndex(source.image, index, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(source.width, source.height),
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary)
                }
                guard let image = image else { throw PetImageError.corrupt }
                try checkDimensions(image.width, image.height)
                guard image.width * image.height * source.frameCount * 4 <= maximumDecodedBytes else { throw PetImageError.memoryLimit }
                if source.animated && (image.width != source.width || image.height != source.height) { throw PetImageError.corrupt }
                // Materialize bounded 8-bit RGBA pixels so NSImage retains no lazy source decoder.
                guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PetImageError.memoryLimit }
                context.setBlendMode(.copy)
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                guard let bitmap = context.makeImage() else { throw PetImageError.corrupt }
                return NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
            }
            frames.append(frame)
            durations.append(source.animated ? frameDuration(source.image, index: index) : 0.1)
            CGImageSourceRemoveCacheAtIndex(source.image, index)
        }
        guard CGImageSourceGetStatus(source.image) == .statusComplete else { throw PetImageError.corrupt }
        return PetAnimation(frames: frames, durations: durations)
    }

    private static func frameDuration(_ source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        for dictionaryKey in [kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyWebPDictionary] {
            guard let values = properties[dictionaryKey] as? [String: Any] else { continue }
            // Preserve original sub-50 ms timing. ImageIO's clamped PNG/GIF value can be much slower.
            if let raw = (values["UnclampedDelayTime"] as? NSNumber)?.doubleValue, raw.isFinite {
                return raw > 0 ? raw : 1.0 / 60.0
            }
            if let clamped = (values["DelayTime"] as? NSNumber)?.doubleValue, clamped.isFinite, clamped > 0 { return clamped }
        }
        return 0.1
    }

    private static func checkDimensions(_ width: Int, _ height: Int) throws {
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension else { throw PetImageError.dimensions }
    }

    private struct PNGInput {
        let data: Data
        let firstIndex: Int
        let declaredFrames: Int?
    }
    private struct PNGChunk {
        let start: Int
        let length: Int
        let type: UInt32
        var payload: Range<Int> { (start + 8)..<(start + 8 + length) }
        var entire: Range<Int> { start..<(start + length + 12) }
    }

    /// Work around ImageIO's excluded-poster APNG indexing bug. A synthetic, skipped poster
    /// frame disposes to transparent before native ImageIO composites the real first frame.
    private static func normalizePNG(_ data: Data) throws -> PNGInput {
        let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]
        guard data.starts(with: signature) else { return PNGInput(data: data, firstIndex: 0, declaredFrames: nil) }
        let ihdr: UInt32 = 0x49484452, actl: UInt32 = 0x6163544C, fctl: UInt32 = 0x6663544C
        let idat: UInt32 = 0x49444154, fdat: UInt32 = 0x66644154, iend: UInt32 = 0x49454E44
        var chunks: [PNGChunk] = []
        var offset = 8, width = 0, height = 0, declared: Int?, firstData: Int?, firstControl: Int?, controls = 0
        var sequence: UInt32 = 0
        var ended = false
        while offset <= data.count - 12 {
            let length = Int(uint32(data, offset)), type = uint32(data, offset + 4)
            guard length <= data.count - offset - 12 else { throw PetImageError.corrupt }
            let chunk = PNGChunk(start: offset, length: length, type: type)
            guard crc32(data, (offset + 4)..<(offset + 8 + length)) == uint32(data, offset + 8 + length) else { throw PetImageError.corrupt }
            if chunks.isEmpty {
                guard type == ihdr, length == 13 else { throw PetImageError.corrupt }
                width = Int(uint32(data, offset + 8)); height = Int(uint32(data, offset + 12))
                try checkDimensions(width, height)
            } else if type == ihdr { throw PetImageError.corrupt }
            if type == actl {
                guard length == 8, declared == nil, firstData == nil else { throw PetImageError.corrupt }
                declared = Int(uint32(data, offset + 8))
                guard let count = declared, count > 0 else { throw PetImageError.corrupt }
                guard count <= maximumFrames else { throw PetImageError.tooManyFrames }
            }
            if type == fctl || type == fdat {
                guard declared != nil, length >= 4, uint32(data, offset + 8) == sequence else { throw PetImageError.corrupt }
                sequence += 1
            }
            if type == fctl {
                guard length == 26 else { throw PetImageError.corrupt }
                controls += 1
                if firstControl == nil { firstControl = chunks.count }
                let frameWidth = Int(uint32(data, offset + 12)), frameHeight = Int(uint32(data, offset + 16))
                try checkDimensions(frameWidth, frameHeight)
                let x = Int(uint32(data, offset + 20)), y = Int(uint32(data, offset + 24))
                guard x + frameWidth <= width, y + frameHeight <= height,
                      data[offset + 32] <= 2, data[offset + 33] <= 1 else { throw PetImageError.corrupt }
            }
            if type == idat, firstData == nil { firstData = chunks.count }
            chunks.append(chunk)
            offset += length + 12
            if type == iend {
                guard length == 0, offset == data.count else { throw PetImageError.corrupt }
                ended = true
                break
            }
        }
        guard ended, let dataIndex = firstData else { throw PetImageError.corrupt }
        if let count = declared {
            guard controls == count, let controlIndex = firstControl else { throw PetImageError.corrupt }
            if controlIndex > dataIndex {
                var normalized = Data(signature)
                for (index, chunk) in chunks.enumerated() {
                    if index == dataIndex {
                        var control = Data()
                        for value in [UInt32(0), UInt32(width), UInt32(height), UInt32(0), UInt32(0)] { appendUInt32(value, to: &control) }
                        control.append(contentsOf: [0, 0, 0, 100, 1, 0]) // zero delay; dispose background; source
                        appendChunk(fctl, payload: control, to: &normalized)
                    }
                    if chunk.type == actl {
                        var payload = Data(data[chunk.payload])
                        replaceUInt32(UInt32(count + 1), in: &payload, at: 0)
                        appendChunk(chunk.type, payload: payload, to: &normalized)
                    } else if chunk.type == fctl || chunk.type == fdat {
                        var payload = Data(data[chunk.payload])
                        replaceUInt32(uint32(payload, 0) + 1, in: &payload, at: 0)
                        appendChunk(chunk.type, payload: payload, to: &normalized)
                    } else { normalized.append(data[chunk.entire]) }
                }
                return PNGInput(data: normalized, firstIndex: 1, declaredFrames: count)
            }
        }
        return PNGInput(data: data, firstIndex: 0, declaredFrames: declared)
    }

    private static func uint32(_ data: Data, _ offset: Int) -> UInt32 {
        (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(contentsOf: [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
    }
    private static func replaceUInt32(_ value: UInt32, in data: inout Data, at offset: Int) {
        var bytes = Data(); appendUInt32(value, to: &bytes)
        data.replaceSubrange(offset..<(offset + 4), with: bytes)
    }
    private static func appendChunk(_ type: UInt32, payload: Data, to data: inout Data) {
        appendUInt32(UInt32(payload.count), to: &data)
        let start = data.count
        appendUInt32(type, to: &data)
        data.append(payload)
        appendUInt32(crc32(data, start..<data.count), to: &data)
    }
    private static let crcTable: [UInt32] = (0..<256).map { byte in
        var crc = UInt32(byte)
        for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 0 ? 0 : 0xEDB88320) }
        return crc
    }
    private static func crc32(_ data: Data, _ range: Range<Int>) -> UInt32 {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var crc: UInt32 = 0xFFFFFFFF
            for index in range { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(bytes[index])) & 255)] }
            return crc ^ 0xFFFFFFFF
        }
    }
}
