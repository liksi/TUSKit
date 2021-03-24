//
//  TUSExtension.swift
//  TUSKit
//
//  Created by Jérôme Alincourt on 22/02/2021.
//

import Foundation

public enum TUSExtension: String {
    case creation = "creation"
    case creationDeferLength = "creation-defer-length"
    case creationWithUpload = "creation-with-upload"
    case expiration = "expiration"
    case checksum = "checksum"
    case checksumTrailer = "checksum-trailer"
    case termination = "termination"
    case concatenation = "concatenation"
    case concatenationUnfinished = "concatenation-unfinished"
}
