//
//  TUSDelegate.swift
//  Pods
//
//  Created by Mark Robert Masterson on 4/5/20.
//

import Foundation

@objc public protocol TUSDelegate {

    func TUSProgress(bytesUploaded uploaded: Int, bytesRemaining remaining: Int) -> Void


    func TUSSuccess(forUpload upload: TUSUpload) -> Void

    func TUSFailure(forUpload upload: TUSUpload?, withResponse response: TUSResponse?, andError error: Error?) -> Void

    @objc optional func TUSAuthRequired(forUpload upload: TUSUpload?) -> Void
}
