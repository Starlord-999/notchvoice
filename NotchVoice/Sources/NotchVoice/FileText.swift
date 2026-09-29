import AppKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Pulls plain text out of a dropped file and splits it into sentences.
enum FileText {
    static func extract(_ url: URL) throws -> String {
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        if type.conforms(to: .pdf) {
            return PDFDocument(url: url)?.string ?? ""
        }
        if type.conforms(to: .image) {
            return try ocr(url)
        }
        if type.conforms(to: .plainText) || type.conforms(to: .sourceCode) || type.conforms(to: .json) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        // rtf, docx, doc, html, odt, webarchive
        return try NSAttributedString(url: url, options: [:], documentAttributes: nil).string
    }

    static func ocr(_ url: URL) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        try VNImageRequestHandler(url: url).perform([req])
        return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func sentences(_ text: String) -> [String] {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")  // PDF line breaks are layout, not meaning
        let tok = NLTokenizer(unit: .sentence)
        tok.string = flat
        return tok.tokens(for: flat.startIndex ..< flat.endIndex)
            .map { flat[$0].trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 2 }
            .flatMap { $0.count > 400 ? split($0, 400) : [$0] }  // Laya context + TTS latency
    }

    private static func split(_ s: String, _ max: Int) -> [String] {
        var out: [String] = [], cur = ""
        for w in s.split(separator: " ") {
            if cur.count + w.count > max, !cur.isEmpty { out.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : " ") + w
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
