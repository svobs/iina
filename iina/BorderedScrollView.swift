//
//  BorderedScrollView.swift
//  iina
//
//  Created by Matt Svoboda on 12/13/22.
//  Copyright © 2022 lhc. All rights reserved.
//

import Foundation

// Based on Lucas Derraugh's "Cocoa Programming L71 - Customizing NSView & NSBox".
// Each `@IBInspectable` annotation allows the attached property to be customized
// via the Attributes Inspector in Interface Builder.
@IBDesignable
class BorderedScrollView: NSScrollView {
  @IBInspectable var borderColor: NSColor? {
    didSet { needsDisplay = true }
  }

  @IBInspectable var borderWidth: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  @IBInspectable var cornerRadius: CGFloat = 0 {
    didSet { needsDisplay = true }
  }

  override var wantsUpdateLayer: Bool {
    return true
  }

  override func updateLayer() {
    guard let layer = layer else { return }

    layer.borderColor = borderColor?.cgColor
    layer.borderWidth = borderWidth
    layer.cornerRadius = cornerRadius
  }
}
