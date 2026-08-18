import Foundation

/// Measures how much disk a file or directory actually occupies.
///
/// Uses allocated size rather than logical size, so the number shown in the preview is
/// the number of bytes that will genuinely come back — a cache of ten thousand tiny
/// files occupies far more than the sum of its file lengths, and quoting the smaller
/// figure would make the tool look like it under-delivered every single time.
///
/// Symlinks are never followed: a link inside a cache directory contributes its own
/// trivial size and nothing more, which is also exactly what removing it will free.
public struct DirectorySizer: Sendable {
    public init() {}

    /// - Throws: `CancellationError` if the surrounding task is cancelled. Large
    ///   Library scans are the common case, so this checks often enough that Cancel
    ///   feels immediate rather than eventually.
    public func size(of path: String) throws -> Int64 {
        let url = URL(fileURLWithPath: path)

        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else {
            return 0
        }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return allocatedSize(of: url)
        }

        var total: Int64 = 0
        var checkCounter = 0

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            // No options on purpose. Hidden files count — caches are full of dotfiles —
            // and package contents count, because a bundle sitting in a cache directory
            // occupies real space that the clean will really free.
            options: []
        ) else {
            return 0
        }

        for case let child as URL in enumerator {
            checkCounter += 1
            if checkCounter % 256 == 0 {
                try Task.checkCancellation()
            }

            guard let values = try? child.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            ) else { continue }

            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }

            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        return total
    }

    private func allocatedSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
}
