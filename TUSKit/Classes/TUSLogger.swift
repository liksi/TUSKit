//
//  TUSLogger.swift
//  TUSKit
//
//  Created by Mark Robert Masterson on 4/18/20.
//

import Foundation
import os

internal class TUSLogger: NSObject {
    
    var enabled: Bool
    var currentLevel: TUSLogLevel?
    private let subsystem = TUSConstants.kReverseIdentifier
    
    init(withLevel level: TUSLogLevel ,_ enabled: Bool) {
        self.enabled = enabled
        currentLevel = level
    }
    
    func log(forLevel level: TUSLogLevel ,withMessage string: String) {
        if enabled {
            if (level.rawValue <= currentLevel!.rawValue) {

                if #available(iOS 10.0, *) {
                    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "TUSKit") // subsystem ?
                    os_log("%{public}@", log: log, type: level.asOSLogType(), string)
                } else {
                    print("\(level)-TUSKit: \(string)")
                }
            }
        }
    }
}

@available(iOS 10.0, *)
extension TUSLogLevel {
    func asOSLogType() -> OSLogType {
        switch self {
            case .Trace:
                return OSLogType.debug // debug
            case .Debug:
                return OSLogType.debug // debug
            case .Info:
                return OSLogType.info // info
            case .Notice:
                return OSLogType.info // info
            case .Warn:
                return OSLogType.info // info
            case .Error:
                return OSLogType.error // info
            case .Critical:
                return OSLogType.fault // fault
            default:
                return OSLogType.default
        }
    }
}
