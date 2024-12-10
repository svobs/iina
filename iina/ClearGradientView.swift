//
//  ClearGradientView.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-10.
//  Copyright © 2024 lhc. All rights reserved.
//

class ClearGradientView: NSView {
  // Ideally the gradient would use a quadratic function, but seems we are limited to linear, so just fudge it a bit.
  @IBInspectable var startColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.0)
  @IBInspectable var midColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.3)
  @IBInspectable var endColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.6)

  override func draw(_ rect: CGRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let colors = [startColor, midColor, endColor]

    // Start at top, going to bottom
    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: colors as CFArray,
                                    locations: [1.0, 0.5, 0.0]) else {
      return
    }

    context.drawLinearGradient(gradient, start: CGPoint.zero,
                               end: CGPoint(x: 0, y: bounds.height),
                               options: [])
  }
}
