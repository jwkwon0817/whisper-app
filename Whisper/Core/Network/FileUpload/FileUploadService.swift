//
//  FileUploadService.swift
//  Whisper
//
//  Created by jwkwon0817 on 11/17/25.
//

import Foundation
import UIKit
import Moya
internal import Alamofire

enum FileUploadAPI {
    case uploadFile(data: Data, fileName: String, contentType: String, folder: String)
}

extension FileUploadAPI: TargetType {
    var baseURL: URL {
        return URL(string: EnvironmentVariables.baseURL)!
    }
    
    var path: String {
        return "/api/upload/"
    }
    
    var method: Moya.Method {
        return .post
    }
    
    var task: Task {
        switch self {
        case .uploadFile(let data, let fileName, let contentType, let folder):
            var formData: [Moya.MultipartFormData] = []
            formData.append(Moya.MultipartFormData(provider: .data(data), name: "file", fileName: fileName, mimeType: contentType))
            formData.append(Moya.MultipartFormData(provider: .data(folder.data(using: .utf8)!), name: "folder"))
            return .uploadMultipart(formData)
        }
    }
    
    var headers: [String: String]? {
        return nil
    }
    
    var validationType: ValidationType {
        return .successCodes
    }
}

class FileUploadService: BaseService<FileUploadAPI> {
    func uploadImage(_ image: UIImage, folder: String = "chat") async throws -> Asset {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw FileUploadError.invalidImage
        }
        
        return try await uploadFile(
            data: imageData,
            fileName: "image.jpg",
            contentType: "image/jpeg",
            folder: folder
        )
    }
    
    func uploadFile(data: Data, fileName: String, contentType: String, folder: String = "chat") async throws -> Asset {
        return try await request(.uploadFile(data: data, fileName: fileName, contentType: contentType, folder: folder), as: Asset.self)
    }
}

enum FileUploadError: LocalizedError {
    case invalidImage
    case uploadFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "유효하지 않은 이미지입니다."
        case .uploadFailed:
            return "파일 업로드에 실패했습니다."
        }
    }
}

