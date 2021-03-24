//
//  TUSChunk.swift
//  TUSKit
//
//  Created by Jérôme Alincourt on 11/03/2021.
//

import Foundation

public struct TUSChunk {
    private var size: Int
    private var unit: TUSChunkUnit

    public var value: Int {
        get {
            return size * unit.rawValue
        }
    }

    init(size: Int, unit: TUSChunkUnit) {
        self.size = size
        self.unit = unit
    }
}

public enum TUSChunkUnit: Int {
    case byte = 1
    case kilobyte = 1024
    case megabyte = 1048576
}
