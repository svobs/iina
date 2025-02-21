//
//  ClickThroughView.swift
//  iina
//
//  Created by Matt Svoboda on 11/28/23.
//  Copyright © 2023 lhc. All rights reserved.
//

import Foundation
 
class ClickThroughView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }
}

class ClickThroughStackView: NSStackView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }
}

class ClickThroughTextField: NSTextField {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }
}
