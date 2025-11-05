//
//  ExportDocument.swift
//  URAP Polar H10 V1
//
//  File document wrapper for exporting recordings
//

import SwiftUI
import UniformTypeIdentifiers

/// Wrapper for exporting files using SwiftUI's FileDocument protocol
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .zip, .commaSeparatedText] }

    let data: Data
    let contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
        self.contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Helper to create export documents from URLs
extension ExportDocument {
    /// Create document from file URL
    static func from(url: URL, contentType: UTType) throws -> ExportDocument {
        let data = try Data(contentsOf: url)
        return ExportDocument(data: data, contentType: contentType)
    }

    /// Create JSON document
    static func json(from url: URL) throws -> ExportDocument {
        try from(url: url, contentType: .json)
    }

    /// Create ZIP document (for CSV exports)
    static func zip(from url: URL) throws -> ExportDocument {
        try from(url: url, contentType: .zip)
    }
}
