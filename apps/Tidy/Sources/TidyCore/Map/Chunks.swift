import Darwin

/// A growable buffer of plain values in fixed-size chunks mapped straight from the kernel.
/// Unlike an array it never reallocates (no doubling slack, no copies left behind for the
/// allocator to keep), and freeing it gives the memory back at once. Elements never move,
/// so a pointer to one stays valid. Not thread-safe: the store's lock guards it.
final class Chunks<Element>: @unchecked Sendable {
    let shift: Int
    var chunkLength: Int { 1 << shift }
    private var chunks: [UnsafeMutablePointer<Element>] = []
    private(set) var count = 0

    /// `shift`: elements per chunk as a power of two.
    init(shift: Int) {
        precondition(_isPOD(Element.self), "Chunks holds plain values only")
        self.shift = shift
    }

    deinit {
        let bytes = chunkLength * MemoryLayout<Element>.stride
        for chunk in chunks { munmap(chunk, bytes) }
    }

    private func addChunk() {
        let bytes = chunkLength * MemoryLayout<Element>.stride
        guard let raw = mmap(nil, bytes, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0), raw != MAP_FAILED else {
            fatalError("Out of memory for the space map")
        }
        chunks.append(raw.bindMemory(to: Element.self, capacity: chunkLength))
    }

    /// Bytes mapped (whole chunks; untouched pages of the last one cost nothing until used).
    var mappedBytes: Int { chunks.count * chunkLength * MemoryLayout<Element>.stride }

    @inline(__always) func pointer(_ index: Int) -> UnsafeMutablePointer<Element> {
        chunks[index >> shift] + (index & (chunkLength - 1))
    }

    subscript(index: Int) -> Element {
        @inline(__always) unsafeAddress { UnsafePointer(pointer(index)) }
        @inline(__always) unsafeMutableAddress { pointer(index) }
    }

    @discardableResult
    func append(_ element: Element) -> Int {
        if count == chunks.count << shift { addChunk() }
        pointer(count).initialize(to: element)
        count += 1
        return count - 1
    }

    /// Appends a run that must stay contiguous (a name): starts a new chunk if it wouldn't
    /// fit in this one. Returns where it starts.
    func appendContiguous(_ elements: UnsafeBufferPointer<Element>) -> Int {
        precondition(elements.count <= chunkLength)
        let room = (chunks.count << shift) - count
        if room < elements.count {
            count = chunks.count << shift
            addChunk()
        } else if chunks.isEmpty {
            addChunk()
        }
        let start = count
        if let base = elements.baseAddress { pointer(start).initialize(from: base, count: elements.count) }
        count += elements.count
        return start
    }
}
