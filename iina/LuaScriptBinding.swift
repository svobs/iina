//
//  LuaScriptBinding.swift
//  iina
//
//  Created by Matthew Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation


class MPVInputSection {
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"


  let name: String
  let keyBindings: [KeyMapping]
  let flags: [String]
  var enabled: Bool = false

  var isForced: Bool {
    get {
      flags.contains(MPVInputSection.FLAG_FORCE)
    }
  }

  init(name: String, _ keyBindings:  [KeyMapping], flags: [String], enabled: Bool = false) {
    self.name = name
    self.keyBindings = keyBindings
    self.flags = flags
    self.enabled = enabled
  }
}


class LuaScriptBinding {

}
