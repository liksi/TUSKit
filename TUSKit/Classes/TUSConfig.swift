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
    internal var availableExtensions: [TUSExtension] {
        get {
            guard let availableExtensions = UserDefaults.standard.value(forKey: TUSConstants.kSavedTUSConfigCapabilitiesDefaultsKey) as? [String] else {
                return []
            }
            return availableExtensions.compactMap { TUSExtension(rawValue: $0) }
        }
        set(availableExtensions) {
            UserDefaults.standard.set(availableExtensions.compactMap { $0.rawValue }, forKey: TUSConstants.kSavedTUSConfigCapabilitiesDefaultsKey)
        }
    }

    public convenience init(withUploadURLString uploadURLString: String, andSessionConfig sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default) {
        let uploadURL = URL(string: uploadURLString)!
        self.init(withUploadURL: uploadURL, andSessionConfig: sessionConfig)
    }

    public init(withUploadURL uploadURL: URL, andSessionConfig sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default) {
        self.uploadURL = uploadURL
        self.URLSessionConfig = sessionConfig
    }
}
