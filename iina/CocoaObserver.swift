//
//  CocoaObserver.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-15.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

typealias PrefDidChangeCallback = (_ key: Preference.Key, _ newValue: Any?) -> Void

/// Convenience class for dealing with `NotificationCenter` notifications and `Preference` change observation
class CocoaObserver: NSObject {
  private var notificationCenterObservers: [NotificationCenter: [NSObjectProtocol]] = [:]

  private let observedPrefKeys: [Preference.Key]
  private let log: Logger.Subsystem
  private let prefDidChangeCallback: PrefDidChangeCallback
  private let legacyPrefKeyObserver: NSObject?

  init(observedPrefKeys: [Preference.Key], _ log: Logger.Subsystem,
       prefDidChange: @escaping PrefDidChangeCallback,
       legacyPrefKeyObserver: NSObject? = nil) {
    self.observedPrefKeys = observedPrefKeys
    self.log = log
    self.prefDidChangeCallback = prefDidChange
    self.legacyPrefKeyObserver = legacyPrefKeyObserver
  }

  func initObservers() {
    removeObservers()

    observedPrefKeys.forEach { key in
      UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, options: .new, context: nil)
    }
  }

  override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                             context: UnsafeMutableRawPointer?) {
    guard let keyPath, let key = PK(rawValue: keyPath), let change = change else { return }
    let newValue = change[.newKey]

    prefDidChangeCallback(key, newValue)
    legacyPrefKeyObserver?.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
  }

  func addObserver(to notificationCenter: NotificationCenter, forName name: Notification.Name, object: Any? = nil,
                   using block: @escaping (Notification) -> Void) {
    let observer: NSObjectProtocol = notificationCenter.addObserver(forName: name, object: object, queue: .main, using: block)
    var observers = notificationCenterObservers[notificationCenter] ?? []
    observers.append(observer)
    notificationCenterObservers[notificationCenter] = observers
  }

  func removeObservers() {
    ObjcUtils.silenced { [self] in
      for key in observedPrefKeys {
        UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
      }

      let ncObservers = notificationCenterObservers
      notificationCenterObservers = [:]
      for (notificationCenter, observers) in ncObservers {
        for observer in observers {
          notificationCenter.removeObserver(observer)
        }
        log.verbose("Removed \(observers.count) observers from \(notificationCenter.className)")
      }
    }
  }

}
