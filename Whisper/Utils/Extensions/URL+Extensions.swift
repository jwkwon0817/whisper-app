//
//  URL+Extensions.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/27/25.
//

import Foundation
import UniformTypeIdentifiers

extension URL {
    var mimeType: String? {
        if let utType = UTType(filenameExtension: self.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }
}

