//
//  TUSClient.swift
//  Pods
//
//  Created by Mark Robert Masterson on 4/5/20.
//
import Foundation


public class TUSClient: NSObject {

    
    // MARK: Properties

    public static let shared = TUSClient()
    private static var config: TUSConfig?

    public var uploadURL: URL // TODO: check if readonly needed
    public var delegate: TUSDelegate?
    public var chunkSize: TUSChunk = TUSChunk(size: TUSConstants.chunkSize, unit: TUSChunkUnit.megabyte) //Default chunksize can be overwritten

    // TODO: make this Atomic ?
    public var currentUploads: [TUSUpload]? {
        get {
            guard let data = UserDefaults.standard.object(forKey: TUSConstants.kSavedTUSUploadsDefaultsKey) as? Data,
                let decoded = try? JSONDecoder().decode([TUSUpload]?.self, from: data) else {
                return nil
            }

            return decoded
        }
        set(currentUploads) {
            if let savedData = try? JSONEncoder().encode(currentUploads) {
                UserDefaults.standard.set(savedData, forKey: TUSConstants.kSavedTUSUploadsDefaultsKey)
            }
        }
    }

    public var status: TUSClientStatus? {
        get {
            guard let status = UserDefaults.standard.value(forKey: TUSConstants.kSavedTUSClientStatusDefaultsKey) as? String else {
                return .ready
            }
            return TUSClientStatus(rawValue: status)
        }
        set(status) {
            UserDefaults.standard.set(status?.rawValue, forKey: TUSConstants.kSavedTUSClientStatusDefaultsKey)
        }
    }

    internal lazy var availableExtensions = {
        return TUSClient.config?.availableExtensions
    }()

    internal let logger: TUSLogger
    internal let fileManager: TUSFileManager = TUSFileManager()

    internal var tusSession: TUSSession = TUSSession()

    private let executor: TUSExecutor

    private lazy var isConcatModeEnabled = {
        return TUSClient.config?.concatMode ?? false
    }()
    
    //MARK: Initializers
    public class func setup(with config:TUSConfig){
        TUSClient.config = config
    }

    private override init() {
        guard let config = TUSClient.config else {
            fatalError("Error - you must call setup before accessing TUSClient")
        }

        uploadURL = config.uploadURL
        executor = TUSExecutor.shared
        let configuredLogger = TUSLogger(withLevel: config.logLevel, true)
        logger = configuredLogger
        fileManager.createFileDirectory()
        super.init()
        let configuredSession = TUSSession(customConfiguration: config.URLSessionConfig, andDelegate: self)
        tusSession = configuredSession

        //If we have already ran this library and uploads, a currentUploads object would exist,
        //if not, we'll get nil and won't be able to append. So create a blank array.
        if (currentUploads == nil) {
            currentUploads = []
        }

        TUSExecutor.shared.retrieveServerCapabilities(withUrl: config.uploadURL, andTusSession: configuredSession, andLogger: configuredLogger)
    }
    
    // MARK: Create method
    
    /// Create a file and upload to your TUS server with retries
    /// - Parameters:
    ///   - upload: the upload object
    ///   - headers: a dictionary of custom headers to send with the create/upload
    ///   - retries: number of retires to take if a call fails
    public func createOrResume(forUpload upload: TUSUpload, withCustomHeaders headers: [String: String]? = nil, andRetries retries: Int = 0) {
        // TODO: handle retries
        if let customHeaders = headers {
            upload.customHeaders = customHeaders
        }

        let fileName = String(format: "%@%@", upload.id, upload.fileType!)
        
        if (fileManager.fileExists(withName: fileName) == false) {
            logger.log(forLevel: .Info, withMessage:String(format: "File not found in local storage.", upload.id))
            upload.status = .new
            currentUploads?.append(upload)
            if (upload.filePathURL != nil) {
                if (fileManager.copyFile(atLocation: upload.filePathURL!, withFileName: fileName) == false) {
                    //fail out
                    let message = String(format: "Failed to copy file.")
                    logger.log(forLevel: .Error, withMessage: message)
                    upload.status = .error
                    updateUpload(upload)
                    self.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: message), andError: nil)

                    return
                }
            } else if (upload.data != nil) {
                if (fileManager.writeData(withData: upload.data!, andFileName: fileName) == false) {
                    //fail out
                    let message = String(format: "Failed to create file in local storage from data.", upload.id)
                    logger.log(forLevel: .Error, withMessage: message)
                    upload.status = .error
                    updateUpload(upload)
                    self.delegate?.TUSFailure(forUpload: upload, withResponse: TUSResponse(message: message), andError: nil)

                    return
                }
            }
        }
         

        // TODO: transfer this to a swift protocol for handling state change ?
        if (status == .ready) { // TODO: handle more than one upload at a time (but not for background)
            status = .uploading
            
            switch upload.status {
            case .paused, .created, .enqueued: // .uploading ?
                logger.log(forLevel: .Info, withMessage:String(format: "File %@ has been previously been created", upload.id))
                if self.isConcatModeEnabled {
                    executor.retrieveOffsetForConcatenation(forUpload: upload)
                } else {
                    executor.retrieveOffset(forUpload: upload)
                }
            case .new:
                if self.isConcatModeEnabled {
                    logger.log(forLevel: .Info, withMessage:String(format: "Creating chunks for %@ on server", upload.id))
                    executor.createForConcatenation(forUpload: upload)
                } else {
                    logger.log(forLevel: .Info, withMessage:String(format: "Creating file %@ on server", upload.id))
                    upload.contentLength = "0"
                    upload.uploadOffset = "0"
                    upload.uploadLength = String(fileManager.sizeForLocalFilePath(filePath: String(format: "%@%@", fileManager.fileStorePath(), fileName)))
                    updateUpload(upload)
                    executor.create(forUpload: upload)
                }
            default:
                logger.log(forLevel: .Info, withMessage: "No action taken for upload with status \(upload.status?.rawValue ?? "unknown")")
            }
        } else {
            logger.log(forLevel: .Debug, withMessage: "Client not ready, not doing anything")
            // TODO?: check all uploads states and reset state if needed
        }
    }
    
    // MARK: Mass methods
    
    /// Resume all uploads
    public func resumeAll() {
        for upload in currentUploads! {
            createOrResume(forUpload: upload)
        }
    }
    
    /// Retry all uploads, even ones that failed
    public func retryAll() {
        for upload in currentUploads! {
            retry(forUpload: upload)
        }
    }
    
    /// Same as cancelAll
    public func pauseAll() {
        for upload in currentUploads! {
            pause(forUpload: upload)
        }
    }
    
    /// Cancel all uploads
    public func cancelAll() {
        for upload in currentUploads! {
            cancel(forUpload: upload)
        }
        // TODO: change TUSClient status here ?
    }
    
    /// Delete all temporary files
    public func cleanUp() {
        for upload in currentUploads! {
            cleanUp(forUpload: upload)
        }
    }
    
    
    // MARK: Methods for one upload
    
    /// Retry an upload
    /// - Parameter upload: the upload object
    public func retry(forUpload upload: TUSUpload, forced: Bool = false) {
        // TODO: check a better way of handling this
        if (status != .ready && !forced) {
            logger.log(forLevel: .Info, withMessage: "Client busy, try again later")
            return
        }

        if (upload.status == .uploading) {
            executor.cancel(forUpload: upload, withUploadStatus: .error) { invalidStateUpload in
                TUSClient.shared.retry(forUpload: invalidStateUpload)
            }
            return
        }

        if (upload.status == .error || forced) {
            upload.status = .enqueued
            createOrResume(forUpload: upload)
        }
    }
    
    public func pause(forUpload upload: TUSUpload, completion: @escaping (TUSUpload)->Void = {_ in}) {
        executor.cancel(forUpload: upload, withUploadStatus: .paused, completion: completion)
    }
    
    /// Cancel an upload
    /// - Parameter upload: the upload object
    public func cancel(forUpload upload: TUSUpload) {
        executor.cancel(forUpload: upload)
    }
    
    /// Delete temporary files for an upload
    /// - Parameter upload: the upload object
    public func cleanUp(forUpload upload: TUSUpload) {
        //Delete stuff here
        let fileName = String(format: "%@%@", upload.id, upload.fileType!)
        currentUploads?.remove(at: 0) // TODO: check upload id

        if (fileManager.deleteFile(withName: fileName)) {
            logger.log(forLevel: .Info, withMessage: "file \(upload.id) cleaned up")
        } else {
            logger.log(forLevel: .Warn, withMessage: "file \(upload.id) failed cleaned up")
        }

        if (fileManager.deleteFile(withName: upload.id)) {
            logger.log(forLevel: .Info, withMessage: "Chunk directory for \(upload.id) cleaned up")
        } else {
            logger.log(forLevel: .Warn, withMessage: "Chunk directory for \(upload.id) failed cleaned up")
        }
    }

    
    //MARK: Helpers
    
    /// Reset the state of TUSClient - maily used for debugging, can be very destructive
    /// - Parameter newState: the new state
    func resetState(to newState: TUSClientStatus) {
        self.status = newState
    }
    
    /// Update an uploads data, used for persistence - not useful outside of the library
    /// - Parameter upload: the upload object
    func updateUpload(_ upload: TUSUpload) {
        let needleUploadIndex = currentUploads?.firstIndex(where: { $0.id == upload.id })
        currentUploads![needleUploadIndex!] = upload
        let updated = currentUploads
        self.currentUploads = updated
    }
}

extension TUSClient: URLSessionDataDelegate {
    // MARK: URLSessionDelegate

    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        logger.log(forLevel: .Error, withMessage: error?.localizedDescription ?? "Session became invalid without error")
        self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Session became invalid"), andError: error)
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        logger.log(forLevel: .Debug, withMessage: "Did finish events for session: \(session.configuration.identifier ?? "TUSKit session")")
        // TODO: find a way to notify TUSKit that events are handled externally (e. g. in applicationDelegate handleEventsForBackgroundURLSession)
        // INFO: if URLSession is background, this method is called after a termination of the app ? Or if app is paused ?
        // TODO?: session.finishTasksAndInvalidate() || session.invalidateAndCancel()
    }


    // MARK: URLSessionDataDelegate





    // Initial response (headers) from URLSessionDataDelegate
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse,
            let taskVerb = dataTask.currentRequest?.httpMethod {

            // TODO: handle 401 Unauthorized here, before taskVerb ? handle 403 Forbidden ?
            // Should cancel task, reset client status and send event via delegate ?
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                let currentTaskId = executor.identifierForTask(dataTask)
                if let retrievedUpload = executor.getUploadForTaskId(currentTaskId) {
                    self.executor.cancel(forUpload: retrievedUpload, withUploadStatus: .uploading) { pausedUpload in
                        TUSClient.shared.status = .ready
                        TUSClient.shared.delegate?.TUSAuthRequired?(forUpload: pausedUpload)
                    }
                } else {
                    self.status = .ready
                    self.delegate?.TUSAuthRequired?(forUpload: nil)
                }
                completionHandler(.cancel)
                return
            } else if !(200..<300).contains(httpResponse.statusCode) {
                logger.log(forLevel: .Warn, withMessage: "Initial response has \(httpResponse.statusCode) status code")
            }

            // TODO: handle 404 (not created first)
            switch taskVerb {
            case "POST", "PATCH", "HEAD":
                logger.log(forLevel: .Debug, withMessage: "Initial headers received for \(taskVerb) request")
                // Not handling here
                completionHandler(.allow)
            case "OPTIONS":
                logger.log(forLevel: .Debug, withMessage: "Initial headers received for \(taskVerb) request")
                completionHandler(.allow)
                // TODO: check status code first
                TUSClient.config?.availableExtensions = httpResponse.allHeaderFieldsUpper()["TUS-EXTENSION"]?.split(separator: ",")
                    .map { TUSExtension(rawValue: String($0))! } ?? []
                logger.log(forLevel: .Debug, withMessage: "Available extensions: \(String(describing: TUSClient.config?.availableExtensions))")
            default:
                logger.log(forLevel: .Debug, withMessage: "Initial headers received for \(taskVerb) request, canceling completion")
                completionHandler(.allow)
            }
        }
    }

    // MARK: URLSessionTaskDelegate

    // Upload progress from URLSessionTaskDelegate
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {

        let currentTaskId = executor.identifierForTask(task)
        guard let currentUpload = executor.getUploadForTaskId(currentTaskId) else {
            self.status = .ready
            logger.log(forLevel: .Warn, withMessage: "While processing progress, upload object not found for task \(currentTaskId)")
//            self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Error while processing request progress"), andError: nil)
            return
        }
        // TODO: handle this properly
        let bytesUploaded: Int
        let uploadLength: Int
        if isConcatModeEnabled {
            bytesUploaded = currentUpload.partialUploadLocations.reduce(0) { prev, _partialState in prev + (Int(_partialState.offset ?? "0")!) } + Int(totalBytesSent)
            uploadLength = currentUpload.partialUploadLocations.reduce(0) { prev, _partialState in prev + (_partialState.chunkSize ?? 0) }
        } else {
            bytesUploaded = Int(currentUpload.uploadOffset ?? "0")! + Int(totalBytesSent)
            uploadLength = Int(currentUpload.uploadLength ?? "0")!
        }
        self.delegate?.TUSProgress?(forUpload: currentUpload, bytesUploaded: bytesUploaded, bytesRemaining: uploadLength)
    }




    // Completion from URLSessionTaskDelegate
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {

        // TODO: handle errors
        let currentTaskId = executor.identifierForTask(task)

        TUSClient.shared.logger.log(forLevel: .Debug, withMessage: "Currently handling completion for TaskId: \(currentTaskId)")

        // TODO: check if -999 The operation could not be completed is needed here ?
        if let completionError = error as NSError?,
        completionError.code == NSURLErrorNetworkConnectionLost || completionError.code == -997 || completionError.code == NSURLErrorCancelled { // -997 == Lost connection to background transfer service : NSURLErrorBackgroundSessionWasDisconnected ?
            self.status = .uploading
            logger.log(forLevel: .Warn, withMessage: "Lost network connection, pausing and retrying current upload")

            guard let currentUpload = executor.getUploadForTaskId(currentTaskId) else {
                self.status = .ready
                logger.log(forLevel: .Error, withMessage: "While processing retry after connection lost, upload object not found for task \(currentTaskId)")
                self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Error while processing request retry"), andError: nil)
                return
            }

            self.executor.cancel(forUpload: currentUpload, withUploadStatus: .error) { pausedUpload in
                TUSClient.shared.status = .ready
                TUSClient.shared.retry(forUpload: pausedUpload)
            }

            return
        }

        guard error == nil else {
            logger.log(forLevel: .Error, withMessage: error!.localizedDescription)
            var existingUpload: TUSUpload?
            if let retrievedUpload = executor.getUploadForTaskId(currentTaskId) {
                retrievedUpload.status = .error
                if let existingTaskIndex = retrievedUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                    retrievedUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                }
                updateUpload(retrievedUpload)
                existingUpload = retrievedUpload
                logger.log(forLevel: .Error, withMessage: "Failed task was \(currentTaskId)")
                self.status = .ready
            }
            self.delegate?.TUSFailure(forUpload: existingUpload, withResponse: nil, andError: error)
            return
        }

        if (task.originalRequest?.httpMethod ?? task.currentRequest?.httpMethod ?? "") == "OPTIONS" {
            logger.log(forLevel: .Debug, withMessage: "OPTIONS completed")
            return
        }


        guard let currentUpload = executor.getUploadForTaskId(currentTaskId) else {
            logger.log(forLevel: .Error, withMessage: "While processing completion, upload object not found for task \(currentTaskId)")
            self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Error while processing request completion"), andError: nil)
            return
        }

        if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
            currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
        }

        let concatMode = isConcatModeEnabled // FIXME: change this behavior for something more reliable (like enum for mode ?)

        if let httpResponse = task.response as? HTTPURLResponse {

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                self.executor.cancel(forUpload: currentUpload, withUploadStatus: .uploading) { pausedUpload in
                    TUSClient.shared.status = .ready
                    TUSClient.shared.delegate?.TUSAuthRequired?(forUpload: pausedUpload)
                }

                return
            }

            switch task.currentRequest?.httpMethod {
            case "HEAD":
                logger.log(forLevel: .Debug, withMessage: "HEAD completed")
                if (200..<300).contains(httpResponse.statusCode) { // FIXME: change this for 200 only (protocol definition)
                    if (!concatMode) {
                        currentUpload.uploadOffset = httpResponse.allHeaderFieldsUpper()["UPLOAD-OFFSET"]
                        updateUpload(currentUpload)
                        executor.upload(forUpload: currentUpload)
                    } else {
                        let chunkNumber = executor.getPartialUploadChunkNumberForTask(task, withUpload: currentUpload)! // TODO: guard or if let ?
                        var partialUploadState = currentUpload.partialUploadLocations[chunkNumber]
                        partialUploadState.status = .ready
                        partialUploadState.offset = httpResponse.allHeaderFieldsUpper()["UPLOAD-OFFSET"]
                        currentUpload.partialUploadLocations[chunkNumber] = partialUploadState
                        updateUpload(currentUpload)

                        if (executor.getConcatChunkUploadedCount(forUpload: currentUpload) >= executor.getNumberOfChunks(forUpload: currentUpload)) {
                            executor.uploadForConcatenation(forUpload: currentUpload)
                        }
                    }
                } else {
                    // TODO: handle this properly
                    executor.cancel(forUpload: currentUpload, withUploadStatus: .error)
                    self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "HEAD completed with status code \(httpResponse.statusCode)"), andError: nil)
                    self.status = .ready
                    return
                }
            case "POST":
                logger.log(forLevel: .Debug, withMessage: "POST completed")
                if httpResponse.statusCode == 201 {
                    if (!concatMode) {
                            logger.log(forLevel: .Info, withMessage: String(format: "File %@ created", currentUpload.id))
                        currentUpload.status = .created
                        currentUpload.uploadLocationURL = URL(string: httpResponse.allHeaderFieldsUpper()["LOCATION"]!, relativeTo: self.uploadURL) // TODO: check why "relativeTo:"
                        logger.log(forLevel: .Info, withMessage: String(format: "URL for uploadLocationURL: %@",currentUpload.uploadLocationURL?.absoluteString ?? "no value"))
                        //Begin the upload
                        if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                            currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                        }
                        self.updateUpload(currentUpload)
                        self.executor.upload(forUpload: currentUpload)
                    } else {
                        let mergingRequest = currentTaskId == currentUpload.mergingRequestId

                        if (mergingRequest) {
                            currentUpload.status = .finished
                            currentUpload.uploadLocationURL = URL(string: httpResponse.allHeaderFieldsUpper()["LOCATION"]!, relativeTo: self.uploadURL)
                            logger.log(forLevel: .Info, withMessage:String(format: "File %@ uploaded at %@", currentUpload.id, currentUpload.uploadLocationURL?.absoluteString ?? "no value"))
                            self.updateUpload(currentUpload)
                            delegate?.TUSSuccess(forUpload: currentUpload)
                            cleanUp(forUpload: currentUpload)
                            status = .ready
                            if (currentUploads!.count > 0) {
                                createOrResume(forUpload: currentUploads![0])
                            }
                        } else {
                            let partialUploadURL = URL(string: httpResponse.allHeaderFieldsUpper()["LOCATION"]!, relativeTo: self.uploadURL)!

                            let partialUploadStateIndex = currentUpload.partialUploadLocations.firstIndex { $0.creationRequestId == currentTaskId }! // TODO: guard
                            var partialUploadState = currentUpload.partialUploadLocations[partialUploadStateIndex]
                            partialUploadState.serverURL = partialUploadURL
                            partialUploadState.status = .created
                            currentUpload.partialUploadLocations[partialUploadStateIndex] = partialUploadState

                            let chunkCount = executor.getNumberOfChunks(forUpload: currentUpload)

                            if (currentUpload.partialUploadLocations.filter({ $0.serverURL != nil }).count == chunkCount) {
                                currentUpload.status = .enqueued
                            }

                            self.updateUpload(currentUpload)

                            if (currentUpload.status == .enqueued) {
                                executor.uploadForConcatenation(forUpload: currentUpload)
                            }
                        }
                    }
                } else {
                    // TODO: handle this properly
                    executor.cancel(forUpload: currentUpload, withUploadStatus: .error)
                    self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "POST completed with status code \(httpResponse.statusCode)"), andError: nil)
                    status = .ready
                    return
                }
            case "PATCH":
                logger.log(forLevel: .Debug, withMessage: "PATCH completed")
                // TODO: if no error and nextChunk != nil then nextChunk
                // TODO: check behavior if URLSession.default

                    switch httpResponse.statusCode {
                    case 200..<300:
                        if (!concatMode) {
                            let chunkCount = executor.getNumberOfChunks(forUpload: currentUpload)
                            let position = executor.getCurrentChunkNumber(forUpload: currentUpload)
                            logger.log(forLevel: .Info, withMessage:String(format: "Chunk %u / %u complete", position + 1, chunkCount))
                            //success
                            if (position + 1 < chunkCount){
                                currentUpload.uploadOffset = httpResponse.allHeaderFieldsUpper()["UPLOAD-OFFSET"]
                                updateUpload(currentUpload)
                                executor.upload(forUpload: currentUpload)
                            } else if (httpResponse.statusCode == 204) {
                                if (position + 1 == chunkCount) {
                                    logger.log(forLevel: .Info, withMessage:String(format: "File %@ uploaded at %@", currentUpload.id, currentUpload.uploadLocationURL!.absoluteString))
                                    if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                                        currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                                    }
                                    currentUpload.status = .finished
                                    updateUpload(currentUpload)
                                    delegate?.TUSSuccess(forUpload: currentUpload)
                                    cleanUp(forUpload: currentUpload)
                                    status = .ready
                                    if (currentUploads!.count > 0) {
                                        createOrResume(forUpload: currentUploads![0])
                                    }
                                }
                            }
                        } else {
                            let chunkNumber = executor.getPartialUploadChunkNumberForTask(task, withUpload: currentUpload)! // TODO: guard or if let ?
                            var partialUploadState = currentUpload.partialUploadLocations[chunkNumber]
                            partialUploadState.status = .finished
                            partialUploadState.offset = String(partialUploadState.chunkSize!)
                            currentUpload.partialUploadLocations[chunkNumber] = partialUploadState
                            updateUpload(currentUpload)

                            if (executor.getConcatChunkUploadedCount(forUpload: currentUpload) >= executor.getNumberOfChunks(forUpload: currentUpload)) {
                                executor.concatenationMerging(forUpload: currentUpload)
                            }
                        }
                    case 500..<600:
                        //server
                        // TODO: handle this properly
                        executor.cancel(forUpload: currentUpload, withUploadStatus: .error)
                        self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "PATCH completed with status code \(httpResponse.statusCode)"), andError: nil)
                        status = .ready
                        return
                    default:
                        // TODO ?
                        break
                    }
            default:
                // NOTE: not handled HTTP verb
                // TODO: handle this properly
                executor.cancel(forUpload: currentUpload, withUploadStatus: .error)
                self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "Current HTTP verb is not handled"), andError: nil)
                status = .ready
                return
            }
        }

        logger.log(forLevel: .Debug, withMessage: "URLSession completed")
    }
}
