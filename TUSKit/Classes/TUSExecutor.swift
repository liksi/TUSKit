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

    func retrieveOffset(forUpload upload: TUSUpload) {
// TODO: check needed ?
//        switch upload.status {
//        case .new:
//            print("new")
//        case .created, .paused:
//            print("created, paused")
//        case .uploading:
//            print("uploading")
//        case .canceled, .finished:
//            print("canceled, finished")
//        default:
//            print("not handling")
//        }

        // TODO: handle misconfiguration

        // TODO: check if uploadUrl exist on upload
        var request = URLRequest(url: upload.uploadLocationURL!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "HEAD"

        let requestHeaders = [
            "Tus-Resumable": TUSConstants.TUSProtocolVersion
        ]

        for header in requestHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current }) {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let offsetTask = TUSSession.session.dataTask(with: request)

        offsetTask.taskDescription = "HEAD \(upload.id)" // Or UUID().uuidString ?

        upload.currentSessionTasksId.append(identifierForTask(offsetTask))
        TUSClient.shared.updateUpload(upload)

        offsetTask.resume()
    }

    func create(forUpload upload: TUSUpload) {
        // TODO: check needed ?
//        switch upload.status {
//        case .new:
//            print("new")
//        case .created, .paused:
//            print("created, paused")
//        case .uploading:
//            print("uploading")
//        case .canceled, .finished:
//            print("canceled, finished")
//        default:
//            print("not handling")
//        }

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

        for header in requestHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current}) {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let creationTask = TUSSession.session.dataTask(with: request)

        creationTask.taskDescription = "POST \(upload.id)" // Or UUID().uuidString ?

        upload.currentSessionTasksId.append(identifierForTask(creationTask))
        TUSClient.shared.updateUpload(upload)

        creationTask.resume()
    }

    func upload(forUpload upload: TUSUpload) {
// TODO: check needed ?
//        switch upload.status {
//        case .new:
//            print("new")
//        case .created, .paused:
//            print("created, paused")
//        case .uploading:
//            print("uploading")
//        case .canceled, .finished:
//            print("canceled, finished")
//        default:
//            print("not handling")
//        }
        // .created: need offset only when "creation-with-upload"
        // .paused: need offset
        // .retry: start without offset ?

        // TODO: handle misconfiguration

        let uploadOffset = UInt64(upload.uploadOffset ?? "0")!

        let nextChunk = getChunkData(forUpload: upload, withOffset: uploadOffset)

        let nextChunkURL = writeChunk(forUpload: upload, withData: nextChunk!)

        // TODO: check if "creation" extension is available first
        var request = URLRequest(url: upload.uploadLocationURL!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
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

        for header in requestHeaders.merging(customHeaders, uniquingKeysWith: { (current, _) in current}) {
            request.addValue(header.value, forHTTPHeaderField: header.key)
        }

        let uploadTask = TUSSession.session.uploadTask(with: request, fromFile: nextChunkURL!)

        uploadTask.taskDescription = "PATCH \(upload.id)" // Or UUID().uuidString ?

        upload.status = .uploading
        TUSClient.shared.updateUpload(upload)

        upload.currentSessionTasksId.append(identifierForTask(uploadTask))
        TUSClient.shared.updateUpload(upload)

        uploadTask.resume()
    }

    // TODO: implement "concatenation" extension

    // TODO: implement "termination" extension

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

    func getCurrentChunkNumber(forUpload upload: TUSUpload) -> Int {
        guard let offset = UInt64(upload.uploadOffset!) else {
            return -1
        }

        let chunkSize = UInt64(TUSClient.shared.chunkSize)

        let (q, r) = offset.quotientAndRemainder(dividingBy: chunkSize)

        if (r > 0) {
            fatalError("Error while handling upload current chunk number")
        }

        print("Current chunk number \(q)")

        return Int(q)
    }

    
//    private var sharedTask: URLSessionDataTask?
//
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

    internal func cancel(forUpload upload: TUSUpload) {
        if let existingUpload = TUSClient.shared.currentUploads?.first(where: { $0.id == upload.id }) {
            // dataTasks, uploadTasks, downloadTasks
            TUSSession.session.getTasksWithCompletionHandler { (_, uploadTasks, _) in
                for uploadTask in uploadTasks {
                    let state = uploadTask.state
                    var canceledTasksId = [String]()
                    for taskId in existingUpload.currentSessionTasksId {
                        if self.identifierForTask(uploadTask) == taskId && state == .running {
                            uploadTask.cancel()
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
            }
            existingUpload.status = .canceled
            TUSClient.shared.updateUpload(existingUpload)
        }

//        TUSClient.shared.status = .ready
    }

    // MARK: Private Networking / Other methods
    internal func get(forUpload upload: TUSUpload) {
        var request: URLRequest = URLRequest(url: upload.uploadLocationURL!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        //TODO: Fix
        //let task = TUSClient.shared.tusSession.session.downloadTask(with: request) { (url, response, error) in
        //    TUSClient.shared.logger.log(forLevel: .Info, withMessage:response!.description)
        //}
    }
}


