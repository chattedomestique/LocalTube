import WebKit
import Foundation

// MARK: - Thumbnail URL Scheme Handler
//
// Serves local thumbnail files via the `localtube-thumb://` custom URL scheme.
// This sidesteps WKWebView's file:// cross-origin restrictions that would block
// loading images from arbitrary filesystem paths.
//
// URL format: localtube-thumb:///absolute/path/to/thumbnail.jpg
//             localtube-thumb://localhost/absolute/path/to/thumbnail.jpg

final class ThumbnailURLSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let url = urlSchemeTask.request.url!
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
        // localtube-thumb://localhost/path      → host = "localhost", path = /path
        var path = url.path
        if path.isEmpty { path = url.absoluteString }
        // URL-decode percent encoding
        return path.removingPercentEncoding ?? path
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
