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
    var localFileURL: URL?
    var chunkSize: Int?
    var status: TUSUploadStatus?
    var offset: String?
    var creationRequestId: String?
}
