//
//  TUSResponse.swift
//  Pods
//
//  Created by Mark Robert Masterson on 4/5/20.
//

import Foundation

public class TUSResponse: NSObject, Codable {
    
    public var message: String?

    public init(message: String) {
        super.init()
        self.message = message
    }
    
}
