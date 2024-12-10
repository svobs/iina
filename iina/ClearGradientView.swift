//
//  ClearGradientView.swift
//  iina
//
//  Created by Matt Svoboda on 2024-12-10.
//  Copyright © 2024 lhc. All rights reserved.
//

@IBDesignable
class ClearGradientView: NSView {
  // Ideally the gradient would use a quadratic function, but seems we are limited to linear, so just fudge it a bit.
  @IBInspectable var startColor: CGColor = .init(red: 0, green: 0, blue: 0, alpha: 0.0)
  @IBInspectable var midColor: CGColor = .init(red: 0, green: 0, blue: 0, alpha: 0.1)
  @IBInspectable var endColor: CGColor = .init(red: 0, green: 0, blue: 0, alpha: 0.5)

  override func draw(_ rect: CGRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let colors = [startColor, midColor, endColor]

    // Start at top, going to bottom
    let colorLocations: [CGFloat] = [1.0, 0.75, 0.0]

    guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: colorLocations) else {
      return
    }

    context.drawLinearGradient(gradient, start: CGPoint.zero,
                               end: CGPoint(x: 0, y: bounds.height),
                               options: [])
  }
}
