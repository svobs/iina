//
//  MPVInputSection.swift
//  iina
//
//  Created by Matthew Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class MPVInputSection: CustomStringConvertible {
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  let keyBindings: [String: KeyMapping]
  let isForce: Bool

  init(name: String, _ keyBindingsDict: [String: KeyMapping], isForce: Bool) {
    self.name = name
    self.keyBindings = keyBindingsDict
    self.isForce = isForce
  }

  init(name: String, _ keyBindingsList:  [KeyMapping], isForce: Bool) {
    self.name = name
    self.keyBindings = keyBindingsList.reduce(into: [String: KeyMapping]()) {
      $0[$1.key] = $1
    }
    self.isForce = isForce
  }

  var description: String {
    get {
      "InputSection(\"\(name)\", \(isForce ? "force" : "weak"), \(keyBindings.count) bindings)"
    }
  }
}
