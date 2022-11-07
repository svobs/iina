//
//  OSCToolbarButton.swift
//  iina
//
//  Created by Matt Svoboda on 11/6/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

class OSCToolbarButton {
  static func setStyle(of toolbarButton: NSButton, buttonType: Preference.ToolBarButton) {
    toolbarButton.translatesAutoresizingMaskIntoConstraints = false
    toolbarButton.bezelStyle = .regularSquare
    toolbarButton.image = buttonType.image()
    toolbarButton.isBordered = false
    toolbarButton.tag = buttonType.rawValue
    toolbarButton.refusesFirstResponder = true
    toolbarButton.toolTip = buttonType.description()
    let sideSize = Preference.ToolBarButton.frameHeight
    Utility.quickConstraints(["H:[btn(\(sideSize))]", "V:[btn(\(sideSize))]"], ["btn": toolbarButton])
  }
}
