//
//  TUSFileManager.swift
//  TUSKit
//
//  Created by Mark Robert Masterson on 4/16/20.
//

import Foundation

class TUSFileManager: NSObject {
    // MARK: Private file storage methods
    
    internal func fileStorePath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)
        let documentsDirectory: String = paths[0]
        return documentsDirectory.appending(TUSConstants.TUSFileDirectoryName)
    }
    
    internal func createFileDirectory() {
        do {
            try FileManager.default.createDirectory(atPath: fileStorePath(), withIntermediateDirectories: false, attributes: nil)
        } catch let error as NSError {
            if (error.code != 516) { //516 is failed creating due to already existing
                let response: TUSResponse = TUSResponse(message: "Failed creating TUS directory in documents")
                TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: error)

            }
        }
    }

    internal func createChunkDirectory(withId id: String) {
        do {
            try FileManager.default.createDirectory(atPath: fileStorePath().appending(id), withIntermediateDirectories: false, attributes: nil)
        } catch let error as NSError {
            if (error.code != 516) { //516 is failed creating due to already existing
                let response: TUSResponse = TUSResponse(message: "Failed creating chunk directory in TUS folder")
                TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: error)

            }
        }
    }
    
    internal func fileExists(withName name: String) -> Bool {
        return FileManager.default.fileExists(atPath: fileStorePath().appending(name))
    }
    
    internal func moveFile(atLocation location: URL, withFileName name: String) -> Bool {
        do {
            try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: fileStorePath().appending(name)))
            return true
        } catch let error as NSError {
            let response: TUSResponse = TUSResponse(message: "Failed moving file \(location.absoluteString) to \(fileStorePath().appending(name)) for TUS folder storage")
            TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: error)
            return false
        }
    }
    
    internal func writeData(withData data: Data, andFileName name: String) -> Bool {
        do {
            try data.write(to: URL(fileURLWithPath: fileStorePath().appending(name)))
            return true
        } catch let error as NSError {
            let response: TUSResponse = TUSResponse(message: "Failed writing data to file \(fileStorePath().appending(name))")
            TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: error)
            return false
        }
    }

    func writeChunkData(withData data: Data, andUploadId id: String, andPosition position: Int) -> URL? {
        let chunkPath = id + "/" + String(position)
        if writeData(withData: data, andFileName: chunkPath) {
            return URL(fileURLWithPath: fileStorePath().appending(chunkPath))
        }
        return nil
    }

    func getChunkURL(forUpload upload: TUSUpload, andPosition position: Int) -> URL? {
        let chunkPath = upload.id + "/" + String(position)
        guard fileExists(withName: chunkPath) else {
            return nil
        }
        return URL(fileURLWithPath: fileStorePath().appending(chunkPath))
    }

    func getFileURL(forUpload upload: TUSUpload) -> URL? {
        let fileName = String(format: "%@%@", upload.id, upload.fileType!)
        return URL(fileURLWithPath: fileStorePath().appending(fileName))
    }
    
    internal func deleteFile(withName name: String) -> Bool {
        do {
            try FileManager.default.removeItem(at: URL(fileURLWithPath: fileStorePath().appending(name)))
                return true
        } catch let error as NSError {
            let response: TUSResponse = TUSResponse(message: "Failed deleting file \(name) from TUS folder storage")
            TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: error)
            return false
        }
    }
    
    internal func sizeForLocalFilePath(filePath:String) -> UInt64 {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: filePath)
            if let fileSize = fileAttributes[FileAttributeKey.size]  {
                return (fileSize as! NSNumber).uint64Value
            } else {
                let response: TUSResponse = TUSResponse(message: "Failed to get a size attribute from path: \(filePath)")
                TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: nil)
            }
        } catch {
            let response: TUSResponse = TUSResponse(message: "Failed to get a size attribute from path: \(filePath)")
            TUSClient.shared.delegate?.TUSFailure(forUpload: nil, withResponse: response, andError: error)
        }
        return 0
    }

    internal func sizeForUpload(_ upload: TUSUpload) -> UInt64 {
        let uploadFilePath = String(format: "%@%@%@", fileStorePath(), upload.id, upload.fileType!)

        return sizeForLocalFilePath(filePath: uploadFilePath)
    }
}
