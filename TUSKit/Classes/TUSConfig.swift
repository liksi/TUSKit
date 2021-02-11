//
//  TUSConfig.swift
//  Pods
//
//  Created by Mark Robert Masterson on 4/6/20.
//

import Foundation

public class TUSConfig {
    let uploadURL: URL
    let URLSessionConfig: URLSessionConfiguration
    public var logLevel: TUSLogLevel = .Off

    public convenience init(withUploadURLString uploadURLString: String, andSessionConfig sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default) {
        let uploadURL = URL(string: uploadURLString)!
        self.init(withUploadURL: uploadURL, andSessionConfig: sessionConfig)
    }

    public init(withUploadURL uploadURL: URL, andSessionConfig sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default) {
        self.uploadURL = uploadURL
        self.URLSessionConfig = sessionConfig
    }
}
