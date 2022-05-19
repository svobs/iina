//
//  KeyInputController.swift
//  iina
//
//  Created by Matthew Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class KeyInputController {

  private var lastKeysPressed = ["", "", "", ""]
  private var lastKeyPressedIndex = 0
  private var partialKeySequences = Set<String>()
  private var observer: NSObjectProtocol? = nil

  init() {
  }

  deinit {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func start() {
    observer = NotificationCenter.default.addObserver(forName: .iinaKeyBindingChanged, object: nil, queue: .main, using: onKeyBindingsChanged)
    rebuildKeySequences()
  }

  func resolveKeyEvent(_ keyEvent: NSEvent) -> KeyMapping? {
    let keyCode = KeyCodeHelper.mpvKeyCode(from: keyEvent)
    if keyCode == "" {
      return nil
    }
    Logger.log("KeyDown: \(keyCode)", level: .verbose)
    if let kb = resolve(keyCode) {
      return kb
    }

    // try to match key sequences, up to 4 values. shortest match wins
    var keyCodeSequence = keyCode
    for i in 0..<3 {
      let prevKeyCode = lastKeysPressed[(lastKeyPressedIndex+4-i)%4]
      if prevKeyCode == "" {
        // no prev keyCode
        break
      }

      keyCodeSequence = "\(prevKeyCode)-\(keyCodeSequence)"
      Logger.log("KeyDown: trying match for seq\(i+1): \(keyCodeSequence)", level: .verbose)

      if let kb = resolve(keyCodeSequence) {
        return kb
      }
    }
    // no match, but may be part of a key sequence.
    // store prev key in circular buffer for later key sequence matching
    lastKeyPressedIndex = (lastKeyPressedIndex+1)%4
    lastKeysPressed[lastKeyPressedIndex] = keyCode

    return nil
  }

  private func resolve(_ keyCode: String) -> KeyMapping? {
    if let kb = PlayerCore.keyBindings[keyCode] {
      // reset key sequence if match, unless explicit "ignore":
      if kb.rawAction != MPVCommand.ignore.rawValue {
        lastKeysPressed[lastKeyPressedIndex] = ""
      }
      return kb
    }

    if partialKeySequences.contains(keyCode) {
      // send an explicit "ignore" for a partial sequence match, so player window doesn't beep
      return KeyMapping(key: keyCode, rawAction: MPVCommand.ignore.rawValue, isIINACommand: false, comment: nil)
    }
    return nil
  }

  private func onKeyBindingsChanged(_ sender: Notification) {
    rebuildKeySequences()
  }

  private func rebuildKeySequences() {
    Logger.log("Rebuilding key sequences", level: .verbose)
    var partialSet = Set<String>()
    for (keyCode, _) in PlayerCore.keyBindings {
      if keyCode.contains("-") {
        let keyCodeSequence = keyCode.split(separator: "-")
        var partial = ""
        for keyCode in keyCodeSequence {
          if partial != "" {
            partial = String(keyCode)
          } else {
            partial = "\(partial)-\(keyCode)"
          }
          partialSet.insert(partial)
        }
      }
    }
    partialKeySequences = partialSet
  }

}
