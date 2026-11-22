import Compression
import Foundation

/// The exchange format uses ordinary single-disk ZIP files with ASCII entry paths.
/// Write stored entries and accept both stored entries and Java's raw DEFLATE entries.
enum PortableZIP {
    private struct Entry {
        let name: Data
        let flags: Int
        let method: Int
        let crc: UInt32
        let compressed: Int
        let expanded: Int
        let offset: Int
    }

    static func write(_ destination: URL, root: URL, names: [String]) throws {
        guard !names.isEmpty, names.count <= PortableLimits.entries, Set(names).count == names.count else {
            throw PortableDataError.invalidFormat
        }
        let output = try PortableFiles.openOutput(destination)
        defer { try? output.close() }
        var entries: [Entry] = []
        var expanded = 0
        for name in names {
            let source = root.appendingPathComponent(name)
            let limit = try PortableLimits.entry(name)
            var crc = ZIPChecksum()
            let size = try PortableFiles.chunks(source, limit: limit) { crc.update($0) }
            expanded += size
            let offset = Int(try output.offset())
            guard expanded <= PortableLimits.archive, offset + size < PortableLimits.archive else {
                throw PortableDataError.tooLarge
            }
            let entry = Entry(name: Data(name.utf8), flags: 0x800, method: 0, crc: crc.value,
                compressed: size, expanded: size, offset: offset)
            var header = Data()
            header.zip32(0x04034b50)
            appendFileFields(entry, to: &header)
            header.zip16(entry.name.count)
            header.zip16(0)
            header.append(entry.name)
            try output.write(contentsOf: header)
            try PortableFiles.chunks(source, limit: size) { try output.write(contentsOf: $0) }
            entries.append(entry)
        }
        let centralOffset = Int(try output.offset())
        var central = Data()
        for entry in entries {
            central.zip32(0x02014b50)
            central.zip16(20)
            appendFileFields(entry, to: &central)
            central.zip16(entry.name.count)
            for _ in 0..<4 { central.zip16(0) }
            central.zip32(0)
            central.zip32(UInt32(entry.offset))
            central.append(entry.name)
        }
        let centralSize = central.count
        central.zip32(0x06054b50)
        central.zip32(0)
        central.zip16(entries.count)
        central.zip16(entries.count)
        central.zip32(UInt32(centralSize))
        central.zip32(UInt32(centralOffset))
        central.zip16(0)
        guard centralOffset + central.count <= PortableLimits.archive else { throw PortableDataError.tooLarge }
        try output.write(contentsOf: central)
        try output.synchronize()
    }

    private static func appendFileFields(_ entry: Entry, to header: inout Data) {
        header.zip16(20)
        header.zip16(entry.flags)
        header.zip16(entry.method)
        header.zip16(0)
        header.zip16(0x21) // 1980-01-01
        header.zip32(entry.crc)
        header.zip32(UInt32(entry.compressed))
        header.zip32(UInt32(entry.expanded))
    }

    static func extract(_ archive: URL, to root: URL) throws -> Set<String> {
        let size = try PortableFiles.size(archive, limit: PortableLimits.archive)
        guard size >= 22 else { throw PortableDataError.invalidFormat }
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        let tailOffset = max(0, size - 22 - 65535)
        try input.seek(toOffset: UInt64(tailOffset))
        let tail = try PortableFiles.read(input, count: size - tailOffset)
        guard let end = stride(from: tail.count - 22, through: 0, by: -1).first(where: {
            tail.zip32($0) == 0x06054b50 && $0 + 22 + tail.zip16($0 + 20) == tail.count
        }), tail.zip32(end + 4) == 0, tail.zip16(end + 8) == tail.zip16(end + 10) else {
            throw PortableDataError.invalidFormat
        }
        let count = tail.zip16(end + 10)
        let centralSize = Int(tail.zip32(end + 12))
        let centralOffset = Int(tail.zip32(end + 16))
        guard (1...PortableLimits.entries).contains(count), centralOffset + centralSize == tailOffset + end else {
            throw PortableDataError.invalidFormat
        }
        var cursor = centralOffset
        var names = Set<String>()
        var entries: [(String, Entry)] = []
        var total = 0
        for _ in 0..<count {
            guard cursor + 46 <= centralOffset + centralSize else { throw PortableDataError.invalidFormat }
            try input.seek(toOffset: UInt64(cursor))
            let record = try PortableFiles.read(input, count: 46)
            let length = record.zip16(28)
            cursor += 46 + length + record.zip16(30) + record.zip16(32)
            let method = record.zip16(10)
            let flags = record.zip16(8)
            guard record.zip32(0) == 0x02014b50, record.zip16(34) == 0, (1...120).contains(length),
                cursor <= centralOffset + centralSize, method == 0 || method == 8,
                flags & ~0x80e == 0 else { throw PortableDataError.invalidFormat }
            let bytes = try PortableFiles.read(input, count: length)
            guard let name = String(data: bytes, encoding: .ascii), names.insert(name).inserted else {
                throw PortableDataError.invalidFormat
            }
            let entry = Entry(name: bytes, flags: flags, method: method, crc: record.zip32(16),
                compressed: Int(record.zip32(20)), expanded: Int(record.zip32(24)),
                offset: Int(record.zip32(42)))
            total += entry.expanded
            guard try entry.expanded <= PortableLimits.entry(name), total <= PortableLimits.archive else {
                throw PortableDataError.tooLarge
            }
            entries.append((name, entry))
        }
        guard cursor == centralOffset + centralSize else { throw PortableDataError.invalidFormat }
        let sorted = entries.sorted { $0.1.offset < $1.1.offset }
        try PortableFiles.directory(root)
        for (index, pair) in sorted.enumerated() {
            try Task.checkCancellation()
            let (name, entry) = pair
            let boundary = index + 1 < sorted.count ? sorted[index + 1].1.offset : centralOffset
            guard entry.offset + 30 <= boundary else { throw PortableDataError.invalidFormat }
            try input.seek(toOffset: UInt64(entry.offset))
            let header = try PortableFiles.read(input, count: 30)
            let extra = header.zip16(28)
            let start = entry.offset + 30 + entry.name.count + extra
            guard header.zip32(0) == 0x04034b50, header.zip16(6) == entry.flags, header.zip16(8) == entry.method,
                header.zip16(26) == entry.name.count, start + entry.compressed <= boundary,
                try PortableFiles.read(input, count: entry.name.count) == entry.name else {
                throw PortableDataError.invalidFormat
            }
            if entry.flags & 8 == 0 {
                guard header.zip32(14) == entry.crc, header.zip32(18) == UInt32(entry.compressed),
                    header.zip32(22) == UInt32(entry.expanded) else { throw PortableDataError.invalidFormat }
            } else {
                let endOfData = start + entry.compressed
                guard boundary - endOfData == 12 || boundary - endOfData == 16 else {
                    throw PortableDataError.invalidFormat
                }
                try input.seek(toOffset: UInt64(endOfData))
                let descriptor = try PortableFiles.read(input, count: boundary - endOfData)
                let offset = descriptor.count - 12
                guard (offset == 0 || descriptor.zip32(0) == 0x08074b50), descriptor.zip32(offset) == entry.crc,
                    descriptor.zip32(offset + 4) == UInt32(entry.compressed),
                    descriptor.zip32(offset + 8) == UInt32(entry.expanded) else { throw PortableDataError.invalidFormat }
            }
            try input.seek(toOffset: UInt64(start))
            let destination = root.appendingPathComponent(name)
            try PortableFiles.directory(destination.deletingLastPathComponent())
            try extract(entry, from: input, to: destination)
        }
        return names
    }

    private static func extract(_ entry: Entry, from input: FileHandle, to file: URL) throws {
        let output = try PortableFiles.openOutput(file)
        defer { try? output.close() }
        var count = 0
        var crc = ZIPChecksum()
        func consume(_ block: Data) throws {
            count += block.count
            guard count <= entry.expanded else { throw PortableDataError.tooLarge }
            crc.update(block)
            try output.write(contentsOf: block)
        }
        if entry.method == 0 {
            guard entry.compressed == entry.expanded else { throw PortableDataError.invalidFormat }
            var remaining = entry.compressed
            while remaining > 0 {
                try Task.checkCancellation()
                let part = try PortableFiles.read(input, count: min(remaining, PortableFiles.chunkSize))
                try consume(part)
                remaining -= part.count
            }
        } else {
            try inflate(input, length: entry.compressed, consume: consume)
        }
        guard count == entry.expanded, crc.value == entry.crc else { throw PortableDataError.invalidFormat }
        try output.synchronize()
    }

    private static func inflate(_ input: FileHandle, length: Int, consume: (Data) throws -> Void) throws {
        let capacity = PortableFiles.chunkSize
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        var stream = compression_stream(dst_ptr: buffer, dst_size: capacity, src_ptr: UnsafePointer(buffer),
            src_size: 0, state: UnsafeMutableRawPointer(buffer))
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw PortableDataError.invalidFormat
        }
        defer { compression_stream_destroy(&stream) }
        var remaining = length
        var status = COMPRESSION_STATUS_OK
        repeat {
            try Task.checkCancellation()
            let part = try PortableFiles.read(input, count: min(remaining, capacity))
            remaining -= part.count
            try part.withUnsafeBytes { bytes in
                stream.src_ptr = bytes.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(buffer)
                stream.src_size = bytes.count
                repeat {
                    stream.dst_ptr = buffer
                    stream.dst_size = capacity
                    let before = stream.src_size
                    status = compression_stream_process(&stream, remaining == 0 ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    guard status == COMPRESSION_STATUS_OK || status == COMPRESSION_STATUS_END else {
                        throw PortableDataError.invalidFormat
                    }
                    let produced = capacity - stream.dst_size
                    try consume(Data(bytes: buffer, count: produced))
                    guard status == COMPRESSION_STATUS_END || before != stream.src_size || produced > 0 else {
                        throw PortableDataError.invalidFormat
                    }
                } while status != COMPRESSION_STATUS_END && (stream.src_size > 0 || remaining == 0)
                if status == COMPRESSION_STATUS_END && (remaining != 0 || stream.src_size != 0) {
                    throw PortableDataError.invalidFormat
                }
            }
        } while status != COMPRESSION_STATUS_END
    }
}

private struct ZIPChecksum {
    private static let table: [UInt32] = (0..<256).map { value in
        (0..<8).reduce(UInt32(value)) { crc, _ in (crc >> 1) ^ ((crc & 1 == 0) ? 0 : 0xedb88320) }
    }
    private var state: UInt32 = 0xffffffff
    var value: UInt32 { state ^ 0xffffffff }
    mutating func update(_ bytes: Data) {
        for byte in bytes { state = (state >> 8) ^ Self.table[Int((state ^ UInt32(byte)) & 255)] }
    }
}

extension Data {
    func zip16(_ offset: Int) -> Int {
        Int(self[offset]) | (Int(self[offset + 1]) << 8)
    }

    func zip32(_ offset: Int) -> UInt32 {
        UInt32(zip16(offset)) | (UInt32(zip16(offset + 2)) << 16)
    }

    fileprivate mutating func zip16(_ value: Int) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    fileprivate mutating func zip32(_ value: UInt32) {
        zip16(Int(value & 0xffff))
        zip16(Int(value >> 16))
    }
}
