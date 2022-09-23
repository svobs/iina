//
//  MPVInputSection.swift
//  iina
//
//  Created by Matt Svoboda on 2022.06.10.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

enum InputBindingOrigin: Codable {
  case confFile
  case iinaPlugin
  case luaScript
}

protocol InputSection: CustomStringConvertible {
  // Section name must be unique within a player core
  var name: String { get }

  var keyBindingList: [KeyMapping] { get }

  /*
   Indicates that all bindings in `keyBindingList` are "strong" or "force" in the mpv sense
   (they override previous bindings)
   */
  var isForce: Bool { get }

  /*
   Where this section came from (category). Note: "origin" is only used for display purposes
   */
  var origin: InputBindingOrigin { get }
}

class MPVInputSection: InputSection {
  static let DEFAULT_SECTION_NAME = "default"
  static let FLAG_DEFAULT = "default"
  static let FLAG_FORCE = "force"
  static let FLAG_EXCLUSIVE = "exclusive"

  let name: String
  let keyBindingList: [KeyMapping]
  let isForce: Bool
  let origin: InputBindingOrigin

  init(name: String, _ keyBindingsDict: [String: KeyMapping], isForce: Bool, origin: InputBindingOrigin) {
    self.name = name
    self.keyBindingList = Array(keyBindingsDict.values)
    self.isForce = isForce
    self.origin = origin
  }

  init(name: String, _ keyBindingsArray: [KeyMapping], isForce: Bool, origin: InputBindingOrigin) {
    self.name = name
    self.keyBindingList = keyBindingsArray
    self.isForce = isForce
    self.origin = origin
  }

  var description: String {
    get {
      "MPVInputSection(\"\(name)\", \(isForce ? "force" : "weak"), \(keyBindingList.count) bindings)"
    }
  }
}
