//
//  TUSPartialUploadState.swift
//  TUSKit
//
//  Created by Jérôme Alincourt on 23/02/2021.
//

import Foundation

public struct TUSPartialUploadState: Codable {
    var serverURL: URL?
    var chunkNumber: Int?
    var localFile: String?
    var localFileURL: URL? {
        get {
            if let localFileName = localFile {
                return URL(fileURLWithPath: TUSClient.shared.fileManager.fileStorePath().appending(localFileName))
            }
            return nil
        }
        set (localFileURL) {
            guard let value = localFileURL else {
                localFile = nil
                return
            }

            let pathComponents = value.pathComponents

            guard pathComponents.count > 1 else {
                return
            }

            localFile = pathComponents[pathComponents.count - 2] + "/" + pathComponents[pathComponents.count - 1]
        }
    }
    var chunkSize: Int?
    var status: TUSUploadStatus?
    var offset: String?
    var creationRequestId: String?
    var offsetRequestPending: Bool = false
}
