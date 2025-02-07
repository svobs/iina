//
//  ThumbnailPeekView.swift
//  iina
//
//  Created by lhc on 12/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let outlineBorderWidth: CGFloat = 1

/// Stores the thumbnail image in the seek preview UI, if configured.
///
/// See: `SeekPreview.swift`
class ThumbnailPeekView: NSImageView {

  var widthConstraint: NSLayoutConstraint!
  var heightConstraint: NSLayoutConstraint!

  init() {
    let dummyFrame = NSRect(origin: .zero, size: CGSize(width: 160, height: 90))
    super.init(frame: dummyFrame)
    wantsLayer = true
    layer?.masksToBounds = true
    imageScaling = .scaleNone
    imageFrameStyle = .none
    refusesFirstResponder = true

    let shadow = NSShadow()
    shadow.shadowColor = .black
    shadow.shadowBlurRadius = 0
    shadow.shadowOffset = .zero
    self.shadow = shadow

    updateColors()

    translatesAutoresizingMaskIntoConstraints = false
    widthConstraint = widthAnchor.constraint(equalToConstant: dummyFrame.width)
    widthConstraint.isActive = true
    heightConstraint = heightAnchor.constraint(equalToConstant: dummyFrame.height)
    heightConstraint.isActive = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateBorderStyle(thumbWidth: CGFloat, thumbHeight: CGFloat) -> CGFloat {
    guard let layer = self.layer else { return 0.0 }

    let cornerRadius: CGFloat
    let style: Preference.ThumnailBorderStyle = Preference.isAdvancedEnabled ? Preference.enum(for: .thumbnailBorderStyle) : Preference.ThumnailBorderStyle.defaultValue
    switch style {
    case .plain:
      layer.borderWidth = 0
      layer.shadowRadius = 0
      cornerRadius = 0
    case .outlineSharpCorners:
      layer.borderWidth = outlineBorderWidth
      layer.shadowRadius = 0
      cornerRadius = 0
    case .outlineRoundedCorners:
      layer.borderWidth = outlineBorderWidth
      layer.shadowRadius = 0
      cornerRadius = roundedCornerRadius(forHeight: thumbHeight)
    case .shadowSharpCorners:
      layer.borderWidth = 0
      layer.shadowRadius = shadowRadius(forHeight: thumbHeight)
      cornerRadius = 0
    case .shadowRoundedCorners:
      layer.borderWidth = 0
      layer.shadowRadius = shadowRadius(forHeight: thumbHeight)
      cornerRadius = roundedCornerRadius(forHeight: thumbHeight)
    case .outlinePlusShadowSharpCorners:
      layer.borderWidth = outlineBorderWidth
      layer.shadowRadius = shadowRadius(forHeight: thumbHeight)
      cornerRadius = 0
    case .outlinePlusShadowRoundedCorners:
      layer.borderWidth = outlineBorderWidth
      layer.shadowRadius = shadowRadius(forHeight: thumbHeight)
      cornerRadius = roundedCornerRadius(forHeight: thumbHeight)
    }

    layer.cornerRadius = cornerRadius
    return cornerRadius
  }

  private func roundedCornerRadius(forHeight frameHeight: CGFloat) -> CGFloat {
    // Set corner radius to betwen 10 and 20
    return 10 + min(10, max(0, (frameHeight - 400) * 0.01))
  }

  private func shadowRadius(forHeight frameHeight: CGFloat) -> CGFloat {
    // Set shadow radius to between 0 and 10 based on frame height
    // shadow is set in xib
    return min(10, 2 + (frameHeight * 0.005))
  }

  func updateColors() {
    guard let layer = self.layer else { return }
    layer.borderColor = CGColor(gray: 0.6, alpha: 0.5)

    if effectiveAppearance.isDark {
      layer.shadowColor = CGColor(gray: 1, alpha: 0.75)
    } else {
      layer.shadowColor = CGColor(gray: 0, alpha: 0.75)
    }
  }
}
