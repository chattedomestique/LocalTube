import Foundation

// MARK: - Library Paths
//
// Pure path arithmetic for the download library. The database stores
// absolute paths (video file, thumbnail, banner); everything that needs
// to reason about "is this file inside the library?" or "what would this
// path be under a different root?" goes through here so the rules live
// in exactly one place.
//
// All functions are string-based and never touch the filesystem.

enum LibraryPaths {

    /// Standardizes a path: resolves `..`/`.`, collapses duplicate
    /// separators, expands `~`, and strips any trailing slash.
    static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let expanded = (path as NSString).expandingTildeInPath
        var standardized = (expanded as NSString).standardizingPath
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    /// True when `path` is `root` itself or lives somewhere beneath it.
    /// Both sides are normalized first so "/a/b/" and "/a/b" compare equal
    /// and "/a/bc" is *not* considered inside "/a/b".
    static func isPath(_ path: String, under root: String) -> Bool {
        let p = normalize(path)
        let r = normalize(root)
        guard !p.isEmpty, !r.isEmpty else { return false }
        if p == r { return true }
        return p.hasPrefix(r + "/")
    }

    /// The portion of `path` after `root` (no leading slash), or nil when
    /// `path` isn't inside `root`.
    static func relativePath(of path: String, under root: String) -> String? {
        let p = normalize(path)
        let r = normalize(root)
        guard !p.isEmpty, !r.isEmpty else { return nil }
        if p == r { return "" }
        guard p.hasPrefix(r + "/") else { return nil }
        return String(p.dropFirst(r.count + 1))
    }

    /// Rewrites `path` from `oldRoot` to `newRoot`, or returns nil when
    /// `path` isn't inside `oldRoot`.
    static func rebase(_ path: String, from oldRoot: String, to newRoot: String) -> String? {
        guard let rel = relativePath(of: path, under: oldRoot) else { return nil }
        let n = normalize(newRoot)
        return rel.isEmpty ? n : (n as NSString).appendingPathComponent(rel)
    }

    /// Given a stored path and the set of roots the library has lived in,
    /// returns the root the path belongs to (longest match wins), if any.
    static func root(of path: String, among roots: [String]) -> String? {
        let candidates = roots
            .map(normalize)
            .filter { !$0.isEmpty && isPath(path, under: $0) }
        return candidates.max { $0.count < $1.count }
    }

    /// Candidate locations for `path` if the library has moved: the path
    /// itself first, then the same relative path under `currentRoot` for
    /// every historical root it could have belonged to.
    static func candidateLocations(for path: String, currentRoot: String, knownRoots: [String]) -> [String] {
        var out: [String] = []
        let normalized = normalize(path)
        guard !normalized.isEmpty else { return out }
        out.append(normalized)
        for old in knownRoots {
            guard let rebased = rebase(normalized, from: old, to: currentRoot),
                  !out.contains(rebased) else { continue }
            out.append(rebased)
        }
        return out
    }

    /// A filesystem-safe single path component. Rejects anything that
    /// could climb out of its parent directory.
    static func isSafeComponent(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}
