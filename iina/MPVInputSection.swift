//
//  MPVInputSection.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

protocol InputSection: CustomStringConvertible {
  var name: String { get }
  var keyBindingList: [KeyMapping] { get }
  var isForce: Bool { get }
}

class MPVInputSection: InputSection {
  static let DEFAULT_SECTION_NAME = "default"
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  let keyBindingList: [KeyMapping]
  let isForce: Bool

  init(name: String, _ keyBindingsDict: [String: KeyMapping], isForce: Bool) {
    self.name = name
    self.keyBindingList = Array(keyBindingsDict.values)
    self.isForce = isForce
  }

  init(name: String, _ keyBindingsArray: [KeyMapping], isForce: Bool) {
    self.name = name
    self.keyBindingList = keyBindingsArray
    self.isForce = isForce
  }

  var description: String {
    get {
      "MPVInputSection(\"\(name)\", \(isForce ? "force" : "weak"), \(keyBindingList.count) bindings)"
    }
  }
}
