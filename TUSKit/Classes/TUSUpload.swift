//
//  TUSUpload.swift
//  Pods
//
//  Created by Mark Robert Masterson on 4/5/20.
//

import Foundation

public class TUSUpload: NSObject, Codable { // NSObject, NSCoding {
    // TODO: chunkSize and position : chunkSize to compare with currently configured if position > 0

    enum CodingKeys: String, CodingKey {
        case id
        case fileType
        case filePath
        case uploadLocation
        case partialUploadLocations
        case mergingRequestId
        case currentSessionTasksId
        case contentLength
        case uploadLength
        case uploadOffset
        case customHeaders
        case status
        case prevStatus
        case chunkSize
        case currentChunkPosition
        case metadata
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(fileType, forKey: .fileType)
        try container.encodeIfPresent(filePath, forKey: .filePath)
        try container.encodeIfPresent(uploadLocation, forKey: .uploadLocation)
        try container.encode(partialUploadLocations, forKey: .partialUploadLocations)
        try container.encodeIfPresent(mergingRequestId, forKey: .mergingRequestId)
        try container.encode(currentSessionTasksId, forKey: .currentSessionTasksId)
        try container.encodeIfPresent(contentLength, forKey: .contentLength)
        try container.encodeIfPresent(uploadLength, forKey: .uploadLength)
        try container.encodeIfPresent(uploadOffset, forKey: .uploadOffset)
        try container.encodeIfPresent(customHeaders, forKey: .customHeaders)
        try container.encodeIfPresent(status?.rawValue, forKey: .status)
        try container.encodeIfPresent(prevStatus?.rawValue, forKey: .prevStatus)
//        try container.encodeIfPresent(chunkSize, forKey: .chunkSize)
        try container.encode(metadata, forKey: .metadata)
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType)
        filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        uploadLocation = try container.decodeIfPresent(String.self, forKey: .uploadLocation)
        partialUploadLocations = try container.decode([TUSPartialUploadState].self, forKey: .partialUploadLocations)
        mergingRequestId = try container.decodeIfPresent(String.self, forKey: .mergingRequestId)
        currentSessionTasksId = try container.decode([String].self, forKey: .currentSessionTasksId)
        contentLength = try container.decodeIfPresent(String.self, forKey: .contentLength)
        uploadLength = try container.decodeIfPresent(String.self, forKey: .uploadLength)
        uploadOffset = try container.decodeIfPresent(String.self, forKey: .uploadOffset)
//        chunkSize = try container.decodeIfPresent(Int.self, forKey: .chunkSize)

        metadata = try container.decode([String: String].self, forKey: .metadata)

        customHeaders = try container.decodeIfPresent([String: String].self, forKey: .customHeaders)

        if let decodedStatus = try container.decodeIfPresent(String.self, forKey: .status) {
            status = TUSUploadStatus(rawValue: decodedStatus)
        }

        if let decodedPrevStatus = try container.decodeIfPresent(String.self, forKey: .prevStatus) {
            prevStatus = TUSUploadStatus(rawValue: decodedPrevStatus)
        }
    }
    
    // MARK: Properties
    public let id: String
    var fileType: String? // TODO: Make sure only ".fileExtension" gets set. Current setup sets fileType as something like "1A1F31FE6-BB39-4A78-AECD-3C9BDE6D129E.jpeg"
    private var filePath: String? // TODO: set only filename, FileManager can retrieve path
    var filePathURL: URL? {
        get {
            guard let filePathValue = filePath else {
                return nil
            }
            return URL(string: filePathValue)
        }
        set(filePathURL) {
            self.filePath = filePathURL?.absoluteString
        }
    }
    var data: Data?
    private var uploadLocation: String?
    public var uploadLocationURL: URL? {
        get {
            guard let uploadLocationValue = uploadLocation else {
                return nil
            }
            return URL(string: uploadLocationValue)
        }
        set(uploadLocationURL) {
            self.uploadLocation = uploadLocationURL?.absoluteString
        }
    }
    var partialUploadLocations: [TUSPartialUploadState] = []
    var mergingRequestId: String?
    var currentSessionTasksId: [String] = []
    var contentLength: String?
    var uploadLength: String?
    var uploadOffset: String?
    public var customHeaders: [String: String]?
    public var status: TUSUploadStatus? {
        didSet {
            TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Upload status : \(String(describing: status)) - Old value: \(String(describing: oldValue))")
            switch oldValue {
                case .canceled, .paused, .error, .authRequired, .finished, .ready:
                    break
                default:
                    prevStatus = oldValue
            }
        }
    }
    var prevStatus: TUSUploadStatus?
//    var chunkSize: Int?
    public var metadata: [String : String] = [:]
    var encodedMetadata: String {
        metadata["filename"] = id
        return metadata.map { (key, value) in
            "\(key) \(value.toBase64())"
        }.joined(separator: ",")
    }

    public init(withId id: String,
                andMetadata metadata: [String: String],
                andFilePathURL filePathURL: URL? = nil,
                andFileType fileType: String? = nil,
                andData data: Data? = nil,
                andUploadLocationURL uploadLocationURL: URL? = nil,
                andPartialUploadLocations partialUploadLocations: [TUSPartialUploadState]? = nil,
                andMergingRequestId mergingRequestId: String? = nil,
                andCurrentSessionTasksId currentSessionTasksId: [String]? = nil,
                andContentLength contentLength: String? = nil,
                andUploadLength uploadLength: String? = nil,
                andUploadOffset uploadOffset: String? = nil,
                andCustomHeaders customHeaders: [String: String]? = nil,
                andStatus status: TUSUploadStatus? = nil) {
        self.id = id
        super.init()
        self.metadata = metadata
        self.filePathURL = filePathURL
        self.fileType = fileType
        self.data = data
        self.uploadLocationURL = uploadLocationURL
        self.partialUploadLocations = partialUploadLocations ?? []
        self.mergingRequestId = mergingRequestId
        self.currentSessionTasksId = currentSessionTasksId ?? []
        self.contentLength = contentLength
        self.uploadLength = uploadLength
        self.uploadOffset = uploadOffset
        self.customHeaders = customHeaders
        self.status = status
    }

    public convenience init(withId id: String,
                            andFilePathURL filePath: URL? = nil,
                            andFileType fileType: String? = nil) {
        self.init(withId: id, andMetadata: [:], andFilePathURL: filePath, andFileType: fileType)
    }
}
