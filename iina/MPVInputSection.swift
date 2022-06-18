//
//  MPVInputSection.swift
//  iina
//
//  Created by Matthew Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class MPVInputSection {
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  let keyBindings: [String: KeyMapping]
  let isForce: Bool
  let isExclusive: Bool

  init(name: String, _ keyBindings:  [KeyMapping], isForce: Bool, isExclusive: Bool = false) {
    self.name = name
    self.keyBindings = keyBindings.reduce(into: [String: KeyMapping]()) {
      $0[$1.key] = $1
    }
    self.isForce = isForce
    self.isExclusive = isExclusive
  }
}
