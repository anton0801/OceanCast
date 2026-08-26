//
//  DeviceFacts.swift
//  Ocean Cast
//
//  Plain system facts, no SDK involved. No User-Agent is collected — this app
//  does not send one.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceFacts {
    static var osVersion: String {
        #if canImport(UIKit)
        let system = UIDevice.current.systemName
        let version = UIDevice.current.systemVersion
        return "\(system) \(version)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? ""
    }

    static var locale: String {
        Locale.current.identifier
    }
}
