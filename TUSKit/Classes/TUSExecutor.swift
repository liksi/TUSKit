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
//    private lazy var delegateQueue: OperationQueue = {
//        var queue = OperationQueue()
//        queue.maxConcurrentOperationCount = 1 // TODO: get value from config
//        return queue
//    }()

    // Semaphore ?

    private override init() {}

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
            TUSClient.shared.cancel(forUpload: upload)

            return
        }

        var request = URLRequest(url: uploadLocationURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "HEAD"

        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion
        ]

        for header in requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current }) {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let offsetTask = TUSSession.session.dataTask(with: request)

        offsetTask.taskDescription = "HEAD \(upload.id)" // Or UUID().uuidString ?

        upload.currentSessionTasksId.append(identifierForTask(offsetTask))
        TUSClient.shared.updateUpload(upload)

        offsetTask.resume()

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Offset request launched")
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

        // TODO: check if "creation" extension is available first
        var request = URLRequest(url: TUSClient.shared.uploadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"

        // Content-Length is not-zero only for "creation-with-upload" extension
        // TODO : handle "creation-with-upload" protocol extension
        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion,
            "Upload-Extension": "creation",
            "Content-Length": "0",
            "Upload-Length": upload.uploadLength!, // Must throw if not set (or check for "creation-defer-length" protocol extension)
            "Upload-Metadata": upload.encodedMetadata
        ]

        for header in requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current}) {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let creationTask = TUSSession.session.dataTask(with: request)

        creationTask.taskDescription = "POST \(upload.id)" // Or UUID().uuidString ?

        upload.currentSessionTasksId.append(identifierForTask(creationTask))
        TUSClient.shared.updateUpload(upload)

        creationTask.resume()

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Creation request launched")
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

        let nextChunk = getChunkData(forUpload: upload, withOffset: uploadOffset)

        let nextChunkURL = writeChunk(forUpload: upload, withData: nextChunk!)

        guard let uploadLocationURL = upload.uploadLocationURL else {
            TUSClient.shared.logger.log(forLevel: .Warn, withMessage: "Current upload has not been created on server, cancelling")
            TUSClient.shared.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: "No uploadLocationURL, cancelling"), andError: nil)
            TUSClient.shared.cancel(forUpload: upload)

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

        for header in requestHeaders.merging(upload.customHeaders ?? [:], uniquingKeysWith: { (current, _) in current}) {
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

    // TODO: implement "concatenation" extension

    // TODO: implement "termination" extension

    // TODO: implement OPTIONS request for Tus Core Protocol

    func identifierForTask(_ task: URLSessionTask) -> String {
        return "\(self.TUSSession.session.configuration.identifier ?? "tuskit.executor").\(task.description)"
    }

    func getUploadForTaskId(_ taskId: String) -> TUSUpload? {
        TUSClient.shared.currentUploads?.first(where: { $0.currentSessionTasksId.contains(taskId)})
    }

    private func getChunkData(forUpload upload: TUSUpload, withOffset offset: UInt64) -> Data? {
        var data: Data? = nil
        let chunkSize = UInt64(TUSClient.shared.chunkSize)

        let fileSize = TUSClient.shared.fileManager.sizeForUpload(upload)
        let remaining = fileSize - offset
        let nextChunkSize = min(chunkSize, remaining)

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

            data = Data(outputFileHandle.readData(ofLength: Int(nextChunkSize)))
        } catch let error as NSError {
            print("Error: \(error.localizedDescription)")
        }

        return data
    }

    private func writeChunk(forUpload upload: TUSUpload, withData data: Data) -> URL? {
        if (!TUSClient.shared.fileManager.fileExists(withName: upload.id)) {
            TUSClient.shared.fileManager.createChunkDirectory(withId: upload.id)
        }

        return TUSClient.shared.fileManager.writeChunkData(withData: data, andUploadId: upload.id, andPosition: (getCurrentChunkNumber(forUpload: upload) + 1))
    }

    func getNumberOfChunks(forUpload upload: TUSUpload) -> Int {
        let fileSize = TUSClient.shared.fileManager.sizeForUpload(upload)
        let chunkSize = UInt64(TUSClient.shared.chunkSize)

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
        let chunkSize = UInt64(TUSClient.shared.chunkSize)
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

    internal func cancel(forUpload upload: TUSUpload, withUploadStatus uploadStatus: TUSUploadStatus = .canceled) {
        if let existingUpload = TUSClient.shared.currentUploads?.first(where: { $0.id == upload.id }) {
            // dataTasks, uploadTasks, downloadTasks
            TUSSession.session.getTasksWithCompletionHandler { (dataTasks, uploadTasks, _) in
                let tasks = dataTasks + uploadTasks
                for task in tasks {
                    let state = task.state
                    var canceledTasksId = [String]()
                    for taskId in existingUpload.currentSessionTasksId {
                        if self.identifierForTask(task) == taskId && state == .running { // TODO: better handling of state
                            task.cancel()
                            canceledTasksId.append(taskId)
                        }
                    }
                    for canceledTasksId in canceledTasksId {
                        guard let canceledTaskIdIndex = existingUpload.currentSessionTasksId.firstIndex(of: canceledTasksId) else {
                            continue
                        }
                        existingUpload.currentSessionTasksId.remove(at: canceledTaskIdIndex)
                    }
                }
                // getMainQueue ?
                TUSClient.shared.updateUpload(existingUpload)
            }

            // TODO: check for status before changing it ?
            existingUpload.status = uploadStatus

            TUSClient.shared.updateUpload(existingUpload)
        }
    }
}
