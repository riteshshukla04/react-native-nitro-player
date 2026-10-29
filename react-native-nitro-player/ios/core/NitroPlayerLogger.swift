//
//  Logger.swift
//  NitroPlayer
//
//  Created by Ritesh Shukla on 18/02/26.
//

import Foundation

class NitroPlayerLogger {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif

    static func log(_ header: String = "NitroPlayer", _ message: @autoclosure () -> String) {
        if isEnabled {
            print("[\(header)] \(message())")
        }
    }
}
