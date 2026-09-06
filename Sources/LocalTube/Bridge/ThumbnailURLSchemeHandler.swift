import WebKit
import Foundation

// MARK: - Thumbnail URL Scheme Handler
//
// Serves local thumbnail / banner images via the `localtube-thumb://` custom
// URL scheme. This sidesteps WKWebView's file:// cross-origin restrictions
// that would block loading images from arbitrary filesystem paths.
//
// URL format: localtube-thumb:///absolute/path/to/thumbnail.jpg?v=N
//             (path is percent-encoded by BridgeEventEmitter)
//
// Hardening: only image files that live inside one of the library roots
// (current download folder + any previous folder the library lived in)
// are served. The old handler would return any image on the disk.

final class ThumbnailURLSchemeHandler: NSObject, WKURLSchemeHandler {

    /// Returns the folders images may be served from. Called on the main
    /// thread for every request (WebKit invokes scheme handlers there).
    private let allowedRoots: () -> [String]

    init(allowedRoots: @escaping () -> [String]) {
        self.allowedRoots = allowedRoots
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        let filePath = resolveFilePath(from: url)

        guard !filePath.isEmpty,
              FileManager.default.fileExists(atPath: filePath) else {
            urlSchemeTask.didFailWithError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist)
            )
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
            let mimeType = mimeType(for: filePath)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type":   mimeType,
                    "Content-Length": "\(data.count)",
                    "Cache-Control":  "max-age=86400",
                ]
            )!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // Nothing to cancel for synchronous file reads
    }

    // MARK: - Helpers

    private func resolveFilePath(from url: URL) -> String {
        // localtube-thumb:///path/to/file.jpg  → path = /path/to/file.jpg
        // `URL.path` already percent-decodes; decoding a second time would
        // corrupt any path that legitimately contains a '%'.
        let path = url.path
        guard !path.isEmpty else { return "" }

        // C1 fix: normalize and reject anything that tries to climb.
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !standardized.contains("..") else { return "" }

        // Only allow image files (no arbitrary file reads)
        let ext = (standardized as NSString).pathExtension.lowercased()
        let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif"]
        guard allowedExtensions.contains(ext) else { return "" }

        // Only serve from inside the library.
        let roots = allowedRoots().filter { !$0.isEmpty }
        guard roots.contains(where: { LibraryPaths.isPath(standardized, under: $0) }) else {
            AppLogger.error("ThumbnailURLSchemeHandler: refused path outside library roots: \(standardized)")
            return ""
        }

        return standardized
    }

    private func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "webp":        return "image/webp"
        case "gif":         return "image/gif"
        default:            return "image/jpeg"
        }
    }
}
