import Foundation

/// One row in the browse outline: a file, link, or folder with its children. Immutable,
/// so a tree can be built off the main actor and handed over.
public final class ArchiveNode: Sendable, Identifiable {
    public let id: Int
    public let name: String
    /// Where it will be written, relative to the output ("docs/readme 2.txt"): unique
    /// per item, the same names extraction gives duplicates and case clashes.
    public let path: String
    /// The entry's path in the archive ("docs/readme.txt"), for extracting it.
    public let archivePath: String
    /// Set when the name had to change: the name in the archive.
    public let originalName: String?
    /// False when the archive doesn't record the size (single-file .gz/.bz2/.xz).
    public let sizeKnown: Bool
    public let kind: ArchiveEntryInfo.Kind
    /// A file's size, or a folder's total.
    public let size: Int64
    /// For folders: every file and folder inside, at any depth.
    public let itemCount: Int
    public let modified: Date?
    /// The file is encrypted, or (folders) something inside is.
    public let isEncrypted: Bool
    public let linkTarget: String?
    /// Sorted: folders first, then by name as Finder sorts. Nil for non-folders.
    public let children: [ArchiveNode]?

    init(id: Int, name: String, path: String, archivePath: String, originalName: String?, sizeKnown: Bool,
         kind: ArchiveEntryInfo.Kind, size: Int64, itemCount: Int,
         modified: Date?, isEncrypted: Bool, linkTarget: String?, children: [ArchiveNode]?) {
        self.id = id
        self.name = name
        self.path = path
        self.archivePath = archivePath
        self.originalName = originalName
        self.sizeKnown = sizeKnown
        self.kind = kind
        self.size = size
        self.itemCount = itemCount
        self.modified = modified
        self.isEncrypted = isEncrypted
        self.linkTarget = linkTarget
        self.children = children
    }

    public var isFolder: Bool { kind == .directory }
}

/// The archive's entries as a tree (folders that only appear in paths are filled in).
public struct ArchiveTree: Sendable {
    public let roots: [ArchiveNode]
    public let fileCount: Int
    public let folderCount: Int
    public let totalBytes: Int64
    /// False when some sizes aren't recorded in the archive.
    public var sizesKnown = true

    public static let empty = ArchiveTree(roots: [], fileCount: 0, folderCount: 0, totalBytes: 0)

    public var itemCount: Int { fileCount + folderCount }

    public init(roots: [ArchiveNode], fileCount: Int, folderCount: Int, totalBytes: Int64) {
        self.roots = roots
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.totalBytes = totalBytes
    }

    public init(entries: [ArchiveEntryInfo]) {
        final class Builder {
            let name: String
            let path: String
            let archivePath: String
            let originalName: String?
            var entry: ArchiveEntryInfo?
            /// Children by lowercased name (APFS is usually case-insensitive).
            var children: [String: Builder] = [:]
            var order: [String] = []
            /// Folder names that had to be renamed because a file took the name.
            var renamedFolders: [String: String] = [:]

            init(name: String, path: String, archivePath: String, originalName: String?) {
                self.name = name
                self.path = path
                self.archivePath = archivePath
                self.originalName = originalName
            }

            var isFolder: Bool { !children.isEmpty || entry == nil || entry?.kind == .directory }

            private func make(_ name: String, original: String) -> Builder {
                let node = Builder(name: name, path: path.isEmpty ? name : path + "/" + name,
                                   archivePath: archivePath.isEmpty ? original : archivePath + "/" + original,
                                   originalName: name == original ? nil : original)
                children[name.lowercased()] = node
                order.append(name.lowercased())
                return node
            }

            private func unique(_ name: String) -> String {
                var number = 2
                while children[Naming.candidate(name, number: number, isFolder: false).lowercased()] != nil { number += 1 }
                return Naming.candidate(name, number: number, isFolder: false)
            }

            /// A folder: same-named folders merge; a file in the way renames the folder.
            func folder(_ name: String) -> Builder {
                let key = name.lowercased()
                if let renamed = renamedFolders[key], let node = children[renamed] { return node }
                if let node = children[key] {
                    if node.isFolder { return node }
                    let node = make(unique(name), original: name)
                    renamedFolders[key] = node.name.lowercased()
                    return node
                }
                return make(name, original: name)
            }

            /// A file or link: never merges; duplicates get "name 2".
            func file(_ name: String) -> Builder {
                children[name.lowercased()] == nil ? make(name, original: name) : make(unique(name), original: name)
            }
        }

        let root = Builder(name: "", path: "", archivePath: "", originalName: nil)
        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init)
            guard let last = components.last else { continue }
            var node = root
            for component in components.dropLast() { node = node.folder(component) }
            let leaf = entry.kind == .directory ? node.folder(last) : node.file(last)
            leaf.entry = entry
        }

        var nextID = 0
        var files = 0
        var folders = 0
        func freeze(_ builder: Builder) -> ArchiveNode {
            nextID += 1
            let id = nextID
            let entry = builder.entry
            if builder.isFolder {
                folders += 1
                let kids = builder.order.map { freeze(builder.children[$0]!) }.sorted(by: Self.finderOrder)
                return ArchiveNode(
                    id: id, name: builder.name, path: builder.path, archivePath: builder.archivePath,
                    originalName: builder.originalName, sizeKnown: kids.allSatisfy(\.sizeKnown), kind: .directory,
                    size: kids.reduce(0) { $0 + $1.size },
                    itemCount: kids.reduce(kids.count) { $0 + $1.itemCount },
                    modified: entry?.modified,
                    isEncrypted: kids.contains(where: \.isEncrypted),
                    linkTarget: nil, children: kids
                )
            }
            files += 1
            let kind = entry?.kind ?? .file
            return ArchiveNode(
                id: id, name: builder.name, path: builder.path, archivePath: builder.archivePath,
                originalName: builder.originalName, sizeKnown: kind != .file || entry?.size != nil, kind: kind,
                size: entry?.size ?? 0, itemCount: 0, modified: entry?.modified,
                isEncrypted: entry?.isEncrypted ?? false, linkTarget: entry?.linkTarget, children: nil
            )
        }
        let roots = root.order.map { freeze(root.children[$0]!) }.sorted(by: Self.finderOrder)
        self.init(roots: roots, fileCount: files, folderCount: folders, totalBytes: roots.reduce(0) { $0 + $1.size })
        sizesKnown = roots.allSatisfy(\.sizeKnown)
    }

    static func finderOrder(_ a: ArchiveNode, _ b: ArchiveNode) -> Bool {
        if a.isFolder != b.isFolder { return a.isFolder }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Items whose name contains `query` (case- and diacritic-insensitive), with the
    /// folders that lead to them. A folder that matches keeps all its contents.
    public func filtered(_ query: String) -> ArchiveTree {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return self }
        var files = 0
        var folders = 0
        func keep(_ node: ArchiveNode) -> ArchiveNode? {
            if node.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                count(node)
                return node
            }
            guard let children = node.children else { return nil }
            let kept = children.compactMap(keep)
            guard !kept.isEmpty else { return nil }
            folders += 1
            return ArchiveNode(
                id: node.id, name: node.name, path: node.path, archivePath: node.archivePath,
                originalName: node.originalName, sizeKnown: kept.allSatisfy(\.sizeKnown), kind: node.kind,
                size: kept.reduce(0) { $0 + $1.size },
                itemCount: kept.reduce(kept.count) { $0 + $1.itemCount },
                modified: node.modified, isEncrypted: kept.contains(where: \.isEncrypted),
                linkTarget: nil, children: kept
            )
        }
        func count(_ node: ArchiveNode) {
            if node.isFolder { folders += 1 } else { files += 1 }
            node.children?.forEach(count)
        }
        let roots = self.roots.compactMap(keep)
        return ArchiveTree(roots: roots, fileCount: files, folderCount: folders, totalBytes: roots.reduce(0) { $0 + $1.size })
    }

    /// Every node, depth first (for tests and selection lookups).
    public var allNodes: [ArchiveNode] {
        var result: [ArchiveNode] = []
        func walk(_ node: ArchiveNode) {
            result.append(node)
            node.children?.forEach(walk)
        }
        roots.forEach(walk)
        return result
    }

    public func node(at path: String) -> ArchiveNode? {
        var level = roots
        var found: ArchiveNode?
        for component in path.split(separator: "/") {
            guard let next = level.first(where: { $0.name == component }) else { return nil }
            found = next
            level = next.children ?? []
        }
        return found
    }
}
