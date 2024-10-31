//
//  CocoaObserver.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-15.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

typealias PrefDidChangeCallback = (_ key: Preference.Key, _ newValue: Any?) -> Void
typealias NotiCenterCallback = (Notification) -> Void

/// Convenience class for dealing with `NotificationCenter` notifications and `Preference` change observation
class CocoaObserver: NSObject {
  struct NCObserver {
    let name: Notification.Name
    let object: Any?
    let callback: NotiCenterCallback

    init(_ name: Notification.Name, object: Any? = nil, _ callback: @escaping NotiCenterCallback) {
      self.name = name
      self.object = object
      self.callback = callback
    }
  }
  private var activeObservers: [NotificationCenter: [NSObjectProtocol]] = [:]

  private let observedPrefKeys: [Preference.Key]
  private let log: Logger.Subsystem
  var prefDidChangeCallback: PrefDidChangeCallback?
  private let legacyPrefKeyObserver: NSObject?
  private let ncObserverSpecs: [NotificationCenter: [NCObserver]]

  init(_ log: Logger.Subsystem,
       prefDidChange: PrefDidChangeCallback? = nil,
       legacyPrefKeyObserver: NSObject? = nil,
       _ observedPrefKeys: [Preference.Key],
       _ ncObserverSpecs: [NotificationCenter: [NCObserver]] = [:]) {
    self.observedPrefKeys = observedPrefKeys
    self.log = log
    self.prefDidChangeCallback = prefDidChange
    self.legacyPrefKeyObserver = legacyPrefKeyObserver
    self.ncObserverSpecs = ncObserverSpecs
  }

  func addAllObservers() {
    removeAllObservers()

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }

    for (nc, specList) in ncObserverSpecs {
      for spec in specList {
        addObserver(to: nc, forName: spec.name, object: spec.object, using: spec.callback)
      }
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                             context: UnsafeMutableRawPointer?) {
    guard let keyPath, let key = PK(rawValue: keyPath), let change = change else { return }
    let newValue = change[.newKey]

    if let prefDidChangeCallback {
      prefDidChangeCallback(key, newValue)
    }
    legacyPrefKeyObserver?.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
  }

  func addObserver(to notificationCenter: NotificationCenter, forName name: Notification.Name, object: Any? = nil,
                   using callback: @escaping (Notification) -> Void) {
    let observer: NSObjectProtocol = notificationCenter.addObserver(forName: name, object: object, queue: .main, using: callback)
    var observers = activeObservers[notificationCenter] ?? []
    observers.append(observer)
    activeObservers[notificationCenter] = observers
  }

  func removeAllObservers() {
    ObjcUtils.silenced { [self] in
      // Stop observing prefs
      for key in observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }

      // Detach Notification Center observers
      let activeObservers = activeObservers
      self.activeObservers = [:]
      for (notificationCenter, observers) in activeObservers {
        for observer in observers {
          notificationCenter.removeObserver(observer)
        }
        log.verbose("Removed \(observers.count) observers from \(notificationCenter.className)")
      }
    }
  }

}
