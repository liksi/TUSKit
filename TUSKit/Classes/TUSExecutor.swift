//
//  TUSExecutor.swift
//  TUSKit
//
//  Created by Mark Robert Masterson on 4/16/20.
//

import Foundation

class TUSExecutor: NSObject {

    static let shared = TUSExecutor()

    private lazy var TUSSession: TUSSession = {
        return TUSClient.shared.tusSession
    }()
    var customHeaders: [String: String] = [:]
//    private lazy var delegateQueue: OperationQueue = {
//        var queue = OperationQueue()
//        queue.maxConcurrentOperationCount = 1 // TODO: get value from config
//        return queue
//    }()

    // Semaphore ?

    private override init() {}

    func retrieveServerCapabilities(withUrl url: URL = TUSClient.shared.uploadURL, andTusSession tusSession: TUSSession? = nil, andLogger logger: TUSLogger = TUSClient.shared.logger) {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "OPTIONS"
        
        logger.log(forLevel: .Debug, withMessage: "Capabilities request has headers: \(customHeaders as AnyObject)")

        let requestHeaders = [String:String]()

        for header in requestHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current}) {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let session = tusSession?.session ?? TUSSession.session

        let capabilitiesTask = session.dataTask(with: request)

        capabilitiesTask.taskDescription = "OPTIONS \(url)" // Or UUID().uuidString ?

        capabilitiesTask.resume()

        logger.log(forLevel: .Debug, withMessage: "Capabilities request launched")
    }

    func retrieveOffset(forUpload upload: TUSUpload) {
// TODO: check needed ?
        switch upload.status {
        case .new, .uploading, .canceled:
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Offset retrieval cannot be done with status: \(String(describing: upload.status))"), andError: nil)
            TUSClient.shared.status = .ready
            return
        case .error:
            // TODO: log ?
            break
        default:
            break
        }

        // TODO: handle misconfiguration

        guard let uploadLocationURL = upload.uploadLocationURL else {
            TUSClient.shared.logger.log(forLevel: .Warn, withMessage: "Current upload has not been created on server, cancelling")
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "No uploadLocationURL, cancelling"), andError: nil)
            TUSClient.shared.cancel(forUpload: upload) { _ in
                TUSClient.shared.status = .ready
            }

            return
        }

        var request = URLRequest(url: uploadLocationURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "HEAD"

        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion
        ]

        let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
        let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let offsetTask = TUSSession.session.downloadTask(with: request)

        offsetTask.taskDescription = "HEAD \(upload.id)" // Or UUID().uuidString ?

        upload.currentSessionTasksId.append(identifierForTask(offsetTask))
        TUSClient.shared.updateUpload(upload)

        offsetTask.resume()

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Offset request launched")
    }

    func retrieveOffsetForConcatenation(forUpload upload: TUSUpload) {

        if (TUSClient.shared.isStrictProtocol) {
            guard TUSClient.shared.isConcatModeEnabled else {
                TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Server cannot handle concatenation extension"), andError: nil)
                TUSClient.shared.status = .ready
                return
            }
        }

        for (index, partialLocationState) in upload.partialUploadLocations.enumerated() {

            if partialLocationState.status != .finished {
                var request = URLRequest(url: partialLocationState.serverURL!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
                request.httpMethod = "HEAD"

                let requestHeaders = [
                    "Tus-Resumable": TUSConstants.TUSProtocolVersion
                ]

                let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
                let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

                for header in headers {
                    request.addValue(header.value, forHTTPHeaderField: header.key)
                }

                let partialOffsetTask = TUSSession.session.downloadTask(with: request)

                partialOffsetTask.taskDescription = "HEAD Concat \(String(describing: partialLocationState.chunkNumber)) \(upload.id)"
                upload.currentSessionTasksId.append(identifierForTask(partialOffsetTask))

                upload.partialUploadLocations[index].offsetRequestPending = true

                TUSClient.shared.updateUpload(upload)

                partialOffsetTask.resume()
            }
        }

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Concat offset requests launched")
    }

    func create(forUpload upload: TUSUpload) {
        // TODO: check needed ?
        switch upload.status {
        case .new:
            break
        default:
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Creation cannot be done with status: \(String(describing: upload.status))"), andError: nil)
            TUSClient.shared.status = .ready
            return
        }

        // TODO: handle misconfiguration

        if (TUSClient.shared.isStrictProtocol) {
            guard TUSClient.shared.availableExtensions?.contains(.creation) ?? false else {
                TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Server cannot handle creation extension"), andError: nil)
                TUSClient.shared.status = .ready
                return
            }
        }

        var request = URLRequest(url: TUSClient.shared.uploadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"

        // Content-Length is not-zero only for "creation-with-upload" extension
        // TODO : handle "creation-with-upload" protocol extension
        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion,
            "Content-Length": "0",
            "Upload-Length": upload.uploadLength!, // TODO: Must throw if not set (or check for "creation-defer-length" protocol extension)
            "Upload-Metadata": upload.encodedMetadata
        ]

        let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
        let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let creationTask = TUSSession.session.downloadTask(with: request)

        creationTask.taskDescription = "POST \(upload.id)" // Or UUID().uuidString ?

        upload.currentSessionTasksId.append(identifierForTask(creationTask))
        TUSClient.shared.updateUpload(upload)

        creationTask.resume()

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Creation request launched")
    }

    func createForConcatenation(forUpload upload: TUSUpload) {
        // TODO: check needed ?
        switch upload.status {
        case .new, .enqueued:
            break
        default:
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Creation for concatenation cannot be done with status: \(String(describing: upload.status))"), andError: nil)
            TUSClient.shared.status = .ready
            return
        }

        if (TUSClient.shared.isStrictProtocol) {
            guard TUSClient.shared.availableExtensions?.contains(.creation) ?? false,
                    TUSClient.shared.isConcatModeEnabled else {
                TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Server cannot handle concatenation extension"), andError: nil)
                TUSClient.shared.status = .ready
                return
            }
        }

        var offset = UInt64(0)

        let numberOfChunks = getNumberOfChunks(forUpload: upload)

        for i in 0..<numberOfChunks {
            let chunkSize = getChunkSize(forUpload: upload, withOffset: offset)
            offset += chunkSize

            let optChunk = upload.partialUploadLocations.first { $0.chunkNumber == i }
            let chunkExist = optChunk != nil

            var partialUploadState: TUSPartialUploadState
            if (chunkExist) {
                partialUploadState = optChunk!
            } else {
                partialUploadState = TUSPartialUploadState()
            }

            if (partialUploadState.serverURL == nil) {
                var request = URLRequest(url: TUSClient.shared.uploadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
                request.httpMethod = "POST"

                // Content-Length is not-zero only for "creation-with-upload" extension
                // TODO : handle "creation-with-upload" protocol extension
                let requestHeaders = [
                    "Tus-Resumable": TUSConstants.TUSProtocolVersion,
                    "Content-Length": "0",
                    "Upload-Concat": "partial",
                    "Upload-Length": String(chunkSize)
                ]

                let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
                let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

                for header in headers {
                    request.addValue(header.value, forHTTPHeaderField: header.key)
                }

                let creationForConcatenationTask = TUSSession.session.downloadTask(with: request)

                creationForConcatenationTask.taskDescription = "POST Concat \(i) \(upload.id)"

                let taskId = identifierForTask(creationForConcatenationTask)

                partialUploadState.chunkNumber = i
                partialUploadState.chunkSize = Int(chunkSize)
                partialUploadState.creationRequestId = taskId

                if (chunkExist) {
                    for (index, value) in upload.partialUploadLocations.enumerated() {
                        if (value.chunkNumber == i) {
                            upload.partialUploadLocations[index] = partialUploadState
                            break
                        }
                    }
                } else {
                    upload.partialUploadLocations.append(partialUploadState)
                }

                upload.currentSessionTasksId.append(taskId)

                TUSClient.shared.updateUpload(upload)

                creationForConcatenationTask.resume()
            }
        }

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Creation for concatenation requests launched")

    }

    func upload(forUpload upload: TUSUpload) {
// TODO: check needed ?
        switch upload.status {
        case .created, .paused, .enqueued, .uploading:
            break
        default:
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Upload cannot be done with status: \(String(describing: upload.status))"), andError: nil)
            TUSClient.shared.status = .ready
            return
        }
        // .created: need offset only when "creation-with-upload"
        // .paused: need offset
        // .retry: start without offset ?

        // TODO: handle misconfiguration

        let uploadOffset = UInt64(upload.uploadOffset ?? "0")!

        let nextChunk = getChunkData(forUpload: upload, withFileOffset: uploadOffset, withChunkLength: getChunkSize(forUpload: upload, withOffset: uploadOffset))

        let nextChunkURL = writeChunk(forUpload: upload, withData: nextChunk!)

        guard let uploadLocationURL = upload.uploadLocationURL else {
            TUSClient.shared.logger.log(forLevel: .Warn, withMessage: "Current upload has not been created on server, cancelling")
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "No uploadLocationURL, cancelling"), andError: nil)
            TUSClient.shared.cancel(forUpload: upload) { _ in
                TUSClient.shared.status = .ready
            }

            return
        }

        var request = URLRequest(url: uploadLocationURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 300)
        request.httpMethod = "PATCH"

        // Content-Length is not-zero only for "creation-with-upload" extension
        // TODO : handle "creation-with-upload" protocol extension
        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion,
            "Content-Type": "application/offset+octet-stream",
            "Content-Length": String(nextChunk!.count),
            "Upload-Offset": upload.uploadOffset!, // Must throw if not set
            "Upload-Metadata": upload.encodedMetadata
        ]

        let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
        let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let uploadTask = TUSSession.session.uploadTask(with: request, fromFile: nextChunkURL!)

        uploadTask.taskDescription = "PATCH \(upload.id)" // Or UUID().uuidString ?

        upload.status = .uploading
        upload.currentSessionTasksId.append(identifierForTask(uploadTask))
        TUSClient.shared.updateUpload(upload)

        uploadTask.resume()

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Upload request launched")
    }

    func uploadForConcatenation(forUpload upload: TUSUpload) {
        switch upload.status {
        case .created, .paused, .enqueued, .uploading:
            break
        default:
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Upload cannot be done with status: \(String(describing: upload.status))"), andError: nil)
            TUSClient.shared.status = .ready
            return
        }


        // because Content-Length is inferred from file when using background session, we have to rewrite all chunks
        for (index, partialLocationState) in upload.partialUploadLocations.enumerated() {
            if (partialLocationState.status != .finished) {
                let chunkOffset = partialLocationState.offset ?? "0"
                writeOneChunk(forUpload: upload, withChunkNumber: index, withChunkOffset: Int(chunkOffset)!)
            }
        }

        for (index, partialLocationState) in upload.partialUploadLocations.enumerated() {

            if (partialLocationState.status != .finished) {
                let chunkOffset = partialLocationState.offset ?? "0"
                var request = URLRequest(url: partialLocationState.serverURL!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 300)
                request.httpMethod = "PATCH"

                let requestHeaders = [
                    "Tus-Resumable": TUSConstants.TUSProtocolVersion,
                    "Content-Type": "application/offset+octet-stream",
                    "Content-Length": String(partialLocationState.chunkSize! - Int(chunkOffset)!), // Must be set for stream or data upload tasks
                    "Upload-Offset": chunkOffset
                ]

                let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
                let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

                for header in headers {
                    request.addValue(header.value, forHTTPHeaderField: header.key)
                }

                let partialUploadTask = TUSSession.session.uploadTask(with: request, fromFile: partialLocationState.localFileURL!)

                partialUploadTask.taskDescription = "PATCH Concat \(String(describing: partialLocationState.chunkNumber)) \(upload.id)"
                upload.currentSessionTasksId.append(identifierForTask(partialUploadTask))

                upload.partialUploadLocations[index].status = .uploading
                TUSClient.shared.updateUpload(upload)

                partialUploadTask.resume()
            }
        }

        upload.status = .uploading
        TUSClient.shared.updateUpload(upload)

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Concat upload requests launched")
    }

    func concatenationMerging(forUpload upload: TUSUpload) {
        switch upload.status {
        case .uploading, .enqueued:
            break
        default:
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Finalize concatenation cannot be done with status: \(String(describing: upload.status))"), andError: nil)
            TUSClient.shared.status = .ready
            return
        }

        if (TUSClient.shared.isStrictProtocol) {
            guard TUSClient.shared.isConcatModeEnabled else {
                TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Server cannot handle concatenation extension"), andError: nil)
                TUSClient.shared.status = .ready
                return
            }

            if let extensions = TUSClient.shared.availableExtensions,
                !extensions.contains(.concatenationUnfinished),
                (upload.partialUploadLocations.first { String($0.chunkSize ?? -1) != $0.offset }) != nil {
                    TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "Server cannot handle concatenation-unfinished extension and merging request loaded while upload is not finished"), andError: nil)
                    TUSClient.shared.status = .ready
                    return
            }
        }

        // TODO: handle concatenation-unfinished protocol extension

        var request = URLRequest(url: TUSClient.shared.uploadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"

        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion,
            "Upload-Concat": "final;\(upload.partialUploadLocations.map({$0.serverURL!.absoluteString}).joined(separator: " "))",
            "Upload-Metadata": upload.encodedMetadata
        ]

        let uploadHeaders = requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current })
        let headers = uploadHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current })

        for header in headers {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let concatenationMergingTask = TUSSession.session.downloadTask(with: request)

        concatenationMergingTask.taskDescription = "POST Concat Final \(upload.id)"

        let mergingRequestId = identifierForTask(concatenationMergingTask)
        upload.currentSessionTasksId.append(mergingRequestId)
        upload.mergingRequestId = mergingRequestId
        TUSClient.shared.updateUpload(upload)

        concatenationMergingTask.resume()

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Concatenation merging request launched")
    }

    // TODO: implement "termination" extension

    func identifierForTask(_ task: URLSessionTask) -> String {
        return "\(self.TUSSession.session.configuration.identifier ?? "tuskit.executor").\(task.taskIdentifier)"
    }

    func getUploadForTaskId(_ taskId: String) -> TUSUpload? {
        TUSClient.shared.currentUploads?.first(where: { $0.currentSessionTasksId.contains(taskId)})
    }

    func getPartialUploadIndexForTask(_ task: URLSessionTask, withUpload upload: TUSUpload) -> Int? {
        let concatUploadURL = task.originalRequest?.url ?? task.currentRequest?.url ?? nil

        return upload.partialUploadLocations.firstIndex(where: { $0.serverURL == concatUploadURL })
    }

    func getNumberOfChunks(forUpload upload: TUSUpload) -> Int {
        let fileSize = TUSClient.shared.fileManager.sizeForUpload(upload)
        let chunkSize = UInt64(TUSClient.shared.chunkSize.value)

        let (qt, rt) = fileSize.quotientAndRemainder(dividingBy: chunkSize)

        var totalNumberOfChunks = Int(qt)
        if (rt > 0) {
            totalNumberOfChunks += 1
        }

        return totalNumberOfChunks
    }

    func getRemainingNumberOfChunks(forUpload upload: TUSUpload) -> Int {
        let fileSize = TUSClient.shared.fileManager.sizeForUpload(upload)
        let offset = UInt64(upload.uploadOffset ?? "0")!
        let chunkSize = UInt64(TUSClient.shared.chunkSize.value)
        let remainingSize = fileSize - offset

        let (qt, rt) = remainingSize.quotientAndRemainder(dividingBy: chunkSize)

        var remainingChunks = Int(qt)
        if (rt > 0) {
            remainingChunks += 1
        }

        return remainingChunks
    }


    func getCurrentChunkNumber(forUpload upload: TUSUpload) -> Int {
        let currentNumberOfChunks = getNumberOfChunks(forUpload: upload) - getRemainingNumberOfChunks(forUpload: upload)

        return currentNumberOfChunks
    }

    private func getFileOffset(forUpload upload: TUSUpload, withChunkNumber chunkNumber: Int) -> UInt64 {
        return UInt64(TUSClient.shared.chunkSize.value * chunkNumber)
    }

    private func getChunkSize(forUpload upload: TUSUpload, withOffset offset: UInt64, withChunkOffset chunkOffset: UInt64 = 0) -> UInt64 {
        let chunkSize = UInt64(TUSClient.shared.chunkSize.value) - chunkOffset

        let fileSize = TUSClient.shared.fileManager.sizeForUpload(upload)
        let remaining = fileSize - (offset + chunkOffset)

        return min(chunkSize, remaining)
    }

    private func getChunkData(forUpload upload: TUSUpload, withFileOffset offset: UInt64, withChunkLength chunkLength: UInt64) -> Data? {
        var data: Data? = nil

        do {
            let outputFileHandle = try FileHandle(forReadingFrom: TUSClient.shared.fileManager.getFileURL(forUpload: upload)!)
            defer {
                if #available(iOS 13.0, *) {
                    try? outputFileHandle.close()
                } else {
                    outputFileHandle.closeFile()
                }
            }

            if #available(iOS 13.0, *) {
                try outputFileHandle.seek(toOffset: offset)
            } else {
                outputFileHandle.seek(toFileOffset: offset)
            }

        data = Data(outputFileHandle.readData(ofLength: Int(chunkLength)))
        } catch let error as NSError {
            print("Error: \(error.localizedDescription)")
        }

        return data
    }

    private func writeChunk(forUpload upload: TUSUpload, withData data: Data, andPosition position: Int? = nil) -> URL? {
        let currentPosition = position ?? getCurrentChunkNumber(forUpload: upload)
        if (!TUSClient.shared.fileManager.fileExists(withName: upload.id)) {
            TUSClient.shared.fileManager.createChunkDirectory(withId: upload.id)
        }

        return TUSClient.shared.fileManager.writeChunkData(withData: data, andUploadId: upload.id, andPosition: (currentPosition + 1))
    }

    private func writeOneChunk(forUpload upload: TUSUpload, withChunkNumber chunkNumber: Int, withChunkOffset chunkOffset: Int = 0) {
        if (!TUSClient.shared.fileManager.fileExists(withName: upload.id)) {
            TUSClient.shared.fileManager.createChunkDirectory(withId: upload.id)
        }

        let offset = getFileOffset(forUpload: upload, withChunkNumber: chunkNumber)
        let length = getChunkSize(forUpload: upload, withOffset: offset, withChunkOffset: UInt64(chunkOffset))
        let data = getChunkData(forUpload: upload, withFileOffset: offset, withChunkLength: length)!

        let chunkFileURL = writeChunk(forUpload: upload, withData: data, andPosition: chunkNumber)!

        let chunkStateIndex = upload.partialUploadLocations.firstIndex { $0.chunkNumber == chunkNumber }!
        upload.partialUploadLocations[chunkStateIndex].localFileURL = chunkFileURL
        upload.partialUploadLocations[chunkStateIndex].chunkSize = data.count

        TUSClient.shared.updateUpload(upload)
    }

    
//    // MARK: Private Networking / Upload methods
//
//    private func urlRequest(withFullURL url: URL, andMethod method: String, andContentLength contentLength: String?, andUploadLength uploadLength: String?, andFilename fileName: String, andHeaders headers: [String: String]) -> URLRequest {
//
//        var request: URLRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
//        request.httpMethod = method
//        request.addValue(TUSConstants.TUSProtocolVersion, forHTTPHeaderField: "TUS-Resumable")
//
//        if let contentLength = contentLength {
//            request.addValue(contentLength, forHTTPHeaderField: "Content-Length")
//        }
//
//        if let uploadLength = uploadLength {
//            request.addValue(uploadLength, forHTTPHeaderField: "Upload-Length")
//        }
//
//        for header in headers.merging(customHeaders, uniquingKeysWith: { (current, _) in current }) {
//            request.addValue(header.value, forHTTPHeaderField: header.key)
//        }
//
//        return request
//    }

    internal func cancel(forUpload upload: TUSUpload, withUploadStatus uploadStatus: TUSUploadStatus = .canceled, completion: @escaping (TUSUpload)->Void = {_ in}) {
        if let _ = TUSClient.shared.currentUploads?.first(where: { $0.id == upload.id }) {
            // [dataTasks, uploadTasks, downloadTasks], executed on session delegate queue
            TUSSession.session.getTasksWithCompletionHandler { (dataTasks, uploadTasks, _) in
                let tasks = dataTasks + uploadTasks
                for task in tasks {
                    let state = task.state
                    for taskId in upload.currentSessionTasksId {
                        if self.identifierForTask(task) == taskId && state == .running { // TODO: better handling of state ( || state == .suspended ?)
                            task.cancel()
                        }
                    }

                    upload.currentSessionTasksId.removeAll()
                }

                // TODO: check for status before changing it ?
                upload.status = uploadStatus
                TUSClient.shared.updateUpload(upload)
                completion(upload)
            }
        }
    }

    internal func getConcatChunkUploadedCount(forUpload upload: TUSUpload) -> Int {
        return upload.partialUploadLocations.filter({$0.status == .finished }).count
    }

    internal func getConcatChunkCreatedCount(forUpload upload: TUSUpload) -> Int {
        return upload.partialUploadLocations.filter({ $0.serverURL != nil }).count
    }

    internal func isAnyConcatOffsetRequestPending(forUpload upload: TUSUpload) -> Bool {
        return upload.partialUploadLocations.first { $0.offsetRequestPending == true } != nil
    }

    internal func hasAnyTaskPending(forUpload upload: TUSUpload? = nil) -> Bool {
        guard let upload = upload else {
            return TUSClient.shared.currentUploads?.first { $0.currentSessionTasksId.count > 0 } != nil
        }
        return upload.currentSessionTasksId.count > 0
    }
}
