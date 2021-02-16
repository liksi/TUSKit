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
    // TODO: make a class or struct for chunkSize handling value and unit
    public var chunkSize: Int = TUSConstants.chunkSize * 1024 * 1024 //Default chunksize can be overwritten

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

    internal let logger: TUSLogger
    internal let fileManager: TUSFileManager = TUSFileManager()

    internal var tusSession: TUSSession = TUSSession()

    private let executor: TUSExecutor
    
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
        logger = TUSLogger(withLevel: config.logLevel, true)
        fileManager.createFileDirectory()
        super.init()
        tusSession = TUSSession(customConfiguration: config.URLSessionConfig, andDelegate: self)

        //If we have already ran this library and uploads, a currentUploads object would exist,
        //if not, we'll get nil and won't be able to append. So create a blank array.
        if (currentUploads == nil) {
            currentUploads = []
        }
    }
    
    // MARK: Create method
    
    /// Create a file and upload to your TUS server with retries
    /// - Parameters:
    ///   - upload: the upload object
    ///   - headers: a dictionary of custom headers to send with the create/upload
    ///   - retries: number of retires to take if a call fails
    public func createOrResume(forUpload upload: TUSUpload, withCustomHeaders headers: [String: String] = [:], andRetries retries: Int = 0) {
        // TODO: handle retries
        self.executor.customHeaders = headers

        let fileName = String(format: "%@%@", upload.id, upload.fileType!)
        
        if (fileManager.fileExists(withName: fileName) == false) {
            logger.log(forLevel: .Info, withMessage:String(format: "File not found in local storage.", upload.id))
            upload.status = .new
            currentUploads?.append(upload)
            if (upload.filePathURL != nil) {
                if fileManager.moveFile(atLocation: upload.filePathURL!, withFileName: fileName) == false{
                    //fail out
                    logger.log(forLevel: .Error, withMessage:String(format: "Failed to move file.", upload.id))

                    return
                }
            } else if(upload.data != nil) {
                if fileManager.writeData(withData: upload.data!, andFileName: fileName) == false {
                    //fail out
                    logger.log(forLevel: .Error, withMessage:String(format: "Failed to create file in local storage from data.", upload.id))

                    return
                }
            }
        }
         

        // TODO: transfer this to a swift protocol for handling state change ?
        if (status == .ready) { // TODO: handle more than one upload at a time (but not for background)
            status = .uploading
            
            switch upload.status {
            case .paused, .created:
                logger.log(forLevel: .Info, withMessage:String(format: "File %@ has been previously been created", upload.id))
                executor.retrieveOffset(forUpload: upload)
            case .new:
                logger.log(forLevel: .Info, withMessage:String(format: "Creating file %@ on server", upload.id))
                upload.contentLength = "0"
                upload.uploadOffset = "0"
                // MARK: UPLOAD LENGTH
                upload.uploadLength = String(fileManager.sizeForLocalFilePath(filePath: String(format: "%@%@", fileManager.fileStorePath(), fileName)))
                updateUpload(upload)
                executor.create(forUpload: upload)
            default:
                logger.log(forLevel: .Info, withMessage: "No action taken for upload")
            }
        } else {
            // TODO: check all uploads states and reset state if needed
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
            cancel(forUpload: upload)
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
    public func retry(forUpload upload: TUSUpload) {
        executor.upload(forUpload: upload)
    }
    
    //Same as cancel
    public func pause(forUpload upload: TUSUpload) {
        cancel(forUpload: upload)
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
            logger.log(forLevel: .Error, withMessage: "file \(upload.id) failed cleaned up")
        }

        if (fileManager.deleteFile(withName: upload.id)) {
            logger.log(forLevel: .Info, withMessage: "Chunk directory for \(upload.id) cleaned up")
        } else {
            logger.log(forLevel: .Error, withMessage: "Chunk directory for \(upload.id) failed cleaned up")
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
        // INFO: if URLSession is background, this method is called after a termination of the app.
        // TODO?: session.finishTasksAndInvalidate() || session.invalidateAndCancel()
    }


    // MARK: URLSessionDataDelegate





    // Initial response (headers) from URLSessionDataDelegate
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let httpResponse = response as? HTTPURLResponse,
            let taskVerb = dataTask.currentRequest?.httpMethod {

            // TODO: handle 401 Unauthorized here, before taskVerb ? handle 403 Forbidden ?
            // Should cancel task, reset client status and send event via delegate ?
            if httpResponse.statusCode == 401 {
                self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Request not authorized"), andError: nil)
                completionHandler(.cancel)
                return
            }

            // TODO: handle this properly: check if completionHandler has to be cancelled
            completionHandler(.allow)

            if taskVerb == "POST" {
                logger.log(forLevel: .Debug, withMessage: "Initial headers received for POST request")
                // Not handling here
            } else if taskVerb == "PATCH" {
                logger.log(forLevel: .Debug, withMessage: "Initial headers received for PATCH request")
                // Not handling here
            } else if taskVerb == "HEAD" {
                logger.log(forLevel: .Debug, withMessage: "Initial headers received for HEAD request")
                // Not handling here
            }
        }
    }

    // MARK: URLSessionTaskDelegate

    // Upload progress from URLSessionTaskDelegate
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {

        let currentTaskId = executor.identifierForTask(task)
        guard let currentUpload = executor.getUploadForTaskId(currentTaskId) else {
            logger.log(forLevel: .Warn, withMessage: "While processing progress, upload object not found for task")
            self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Error while processing request progress"), andError: nil)
            return
        }
        // TODO: handle this properly
        self.delegate?.TUSProgress(bytesUploaded: Int(currentUpload.uploadOffset!)!, bytesRemaining: Int(currentUpload.uploadLength!)!)
    }




    // Completion from URLSessionTaskDelegate
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error == nil else {
            logger.log(forLevel: .Error, withMessage: error!.localizedDescription)
            // TUSFailure ?
            return
        }

        // TODO: handle errors
        let currentTaskId = executor.identifierForTask(task)
        guard let currentUpload = executor.getUploadForTaskId(currentTaskId) else {
            logger.log(forLevel: .Warn, withMessage: "While processing completion, upload object not found for task")
            self.delegate?.TUSFailure(forUpload: nil, withResponse: TUSResponse(message: "Error while processing request completion"), andError: nil)
            return
        }

        if let httpResponse = task.response as? HTTPURLResponse {
        switch task.currentRequest?.httpMethod {
        case "HEAD":
            logger.log(forLevel: .Debug, withMessage: "HEAD completed")
            if (200..<300).contains(httpResponse.statusCode) { // FIXME: change this for 200 only (protocol definition)
                currentUpload.uploadOffset = httpResponse.allHeaderFieldsUpper()["UPLOAD-OFFSET"]
                if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                    currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                }
                updateUpload(currentUpload)
                executor.upload(forUpload: currentUpload)
            } else {
                // TODO: handle this properly
                currentUpload.status = .paused
                updateUpload(currentUpload)
                self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "HEAD completed with code outside 200..<300"), andError: nil)
                return
            }
        case "POST":
            logger.log(forLevel: .Debug, withMessage: "POST completed")
            if httpResponse.statusCode == 201 {
                TUSClient.shared.logger.log(forLevel: .Info, withMessage: String(format: "File %@ created", currentUpload.id))
                currentUpload.status = .created
                currentUpload.uploadLocationURL = URL(string: httpResponse.allHeaderFieldsUpper()["LOCATION"]!, relativeTo: TUSClient.shared.uploadURL) // TODO: check why "relativeTo:"
                logger.log(forLevel: .Info, withMessage: String(format: "URL for uploadLocationURL: %@",currentUpload.uploadLocationURL?.absoluteString ?? "no value"))
                //Begin the upload
                if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                    currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                }
                self.updateUpload(currentUpload)
                self.executor.upload(forUpload: currentUpload)
            } else {
                // TODO: handle this properly
                currentUpload.status = .paused
                updateUpload(currentUpload)
                self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "POST completed with code different from 201"), andError: nil)
                return
            }
        case "PATCH":
            logger.log(forLevel: .Debug, withMessage: "PATCH completed")
            // TODO: if no error and nextChunk != nil then nextChunk
            // TODO: check behavior if URLSession.default

            if error == nil {

                    switch httpResponse.statusCode {
                    case 200..<300:
                        let currentUpload = currentUploads![0] // TODO: handle this properly
                        let chunkCount = executor.getNumberOfChunks(forUpload: currentUpload)
                        let position = executor.getCurrentChunkNumber(forUpload: currentUpload)
                        TUSClient.shared.logger.log(forLevel: .Info, withMessage:String(format: "Chunk %u / %u complete", position + 1, chunkCount))
                        //success
                        if (position + 1 < chunkCount){

                            currentUpload.uploadOffset = httpResponse.allHeaderFieldsUpper()["UPLOAD-OFFSET"]
                            if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                                currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                            }
                            TUSClient.shared.updateUpload(currentUpload)
                            executor.upload(forUpload: currentUpload)
                        } else if (httpResponse.statusCode == 204) {

                                if (position + 1 == chunkCount) {
                                    TUSClient.shared.logger.log(forLevel: .Info, withMessage:String(format: "File %@ uploaded at %@", currentUpload.id, currentUpload.uploadLocationURL!.absoluteString))
                                if let existingTaskIndex = currentUpload.currentSessionTasksId.firstIndex(of: currentTaskId) {
                                    currentUpload.currentSessionTasksId.remove(at: existingTaskIndex)
                                }
                                TUSClient.shared.updateUpload(currentUpload)
                                TUSClient.shared.delegate?.TUSSuccess(forUpload: currentUpload)
                                TUSClient.shared.cleanUp(forUpload: currentUpload)
                                TUSClient.shared.status = .ready
                                if (TUSClient.shared.currentUploads!.count > 0) {
                                    TUSClient.shared.createOrResume(forUpload: TUSClient.shared.currentUploads![0])
                                }
                            }
                        }
                        break
                    case 400..<500:
                        //reuqest error
                        // TODO: handle this properly
                        currentUpload.status = .paused
                        updateUpload(currentUpload)
                        self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "PATCH completed with code inside 400..<500"), andError: nil)
                        return
                    case 500..<600:
                        //server
                        // TODO: handle this properly
                        currentUpload.status = .paused
                        updateUpload(currentUpload)
                        self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "PATCH completed with code inside 500..<600"), andError: nil)
                        return
                    default: break
                    }

            } else {
                // TODO: TUSFailure if retrycount > retries ?
                    // TODO: handle this properly
                    currentUpload.status = .paused
                    updateUpload(currentUpload)
                    self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "HEAD completed with code outside 200..<300"), andError: nil)
                    return
            }
        default:
            // TODO: handle this properly
            currentUpload.status = .paused
            updateUpload(currentUpload)
            self.delegate?.TUSFailure(forUpload: currentUpload, withResponse: TUSResponse(message: "Current HTTP verb is not handled"), andError: nil)
            return
        }
        }

        logger.log(forLevel: .Debug, withMessage: "URLSession completed")
    }
}
