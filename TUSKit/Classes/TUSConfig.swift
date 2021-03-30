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
    let initialHeaders: [String:String]
    public var logLevel: TUSLogLevel = .Off
    public var concatModeIfAvailable = false
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

    public convenience init(withUploadURLString uploadURLString: String,
                            andSessionConfig sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default,
                            withCustomHeaders initialHeaders:[String:String] = [:]) {
        let uploadURL = URL(string: uploadURLString)!
        self.init(withUploadURL: uploadURL, andSessionConfig: sessionConfig, withCustomHeaders: initialHeaders)
    }

    public init(withUploadURL uploadURL: URL,
                andSessionConfig sessionConfig: URLSessionConfiguration = URLSessionConfiguration.default,
                withCustomHeaders initialHeaders:[String:String] = [:]) {
        self.uploadURL = uploadURL
        self.URLSessionConfig = sessionConfig
        self.initialHeaders = initialHeaders
    }
}
