//
//  URL+Extensions.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/27/25.
//

import Foundation
import UniformTypeIdentifiers

extension URL {
    /// 파일의 MIME 타입 반환
    var mimeType: String? {
        if let utType = UTType(filenameExtension: self.pathExtension) {
            return utType.preferredMIMEType
        }
        return nil
    }
}

