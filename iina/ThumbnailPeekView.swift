//
//  ThumbnailPeekView.swift
//  iina
//
//  Created by lhc on 12/6/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

fileprivate let thumbnailExtraOffsetX = Constants.Distance.Thumbnail.extraOffsetX
fileprivate let thumbnailExtraOffsetY = Constants.Distance.Thumbnail.extraOffsetY

class ThumbnailPeekView: NSImageView {

  var widthConstraint: NSLayoutConstraint!
  var heightConstraint: NSLayoutConstraint!

  init() {
    let dummyFrame = NSRect(origin: .zero, size: CGSize(width: 160, height: 90))
    super.init(frame: dummyFrame)
    layer?.masksToBounds = true
    imageScaling = .scaleNone
    imageFrameStyle = .none
    refusesFirstResponder = true

    let shadow = NSShadow()
    shadow.shadowColor = .black
    shadow.shadowBlurRadius = 0
    shadow.shadowOffset = .zero
    self.shadow = shadow

    translatesAutoresizingMaskIntoConstraints = false
    widthConstraint = widthAnchor.constraint(equalToConstant: dummyFrame.width)
    widthConstraint.isActive = true
    heightConstraint = heightAnchor.constraint(equalToConstant: dummyFrame.height)
    heightConstraint.isActive = true

    updateColors()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func updateBorderStyle(thumbWidth: CGFloat, thumbHeight: CGFloat) -> CGFloat {
    guard let layer = self.layer else { return 0.0 }

    let cornerRadius: CGFloat
    let style: Preference.ThumnailBorderStyle = Preference.isAdvancedEnabled ? Preference.enum(for: .thumbnailBorderStyle) : Preference.ThumnailBorderStyle.defaultValue
    switch style {
    case .plain:
      layer.borderWidth = 0
      layer.shadowRadius = 0
      cornerRadius = 0
    case .outlineSharpCorners:
      layer.borderWidth = outlineRoundedCornersWidth()
      layer.shadowRadius = 0
      cornerRadius = 0
    case .outlineRoundedCorners:
      layer.borderWidth = outlineRoundedCornersWidth()
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
      layer.borderWidth = outlineRoundedCornersWidth()
      layer.shadowRadius = shadowRadius(forHeight: thumbHeight)
      cornerRadius = 0
    case .outlinePlusShadowRoundedCorners:
      layer.borderWidth = outlineRoundedCornersWidth()
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

  private func outlineRoundedCornersWidth() -> CGFloat {
    return 1
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

  func displayThumbnail(forTime previewTimeSec: Double, originalPosX: CGFloat, _ player: PlayerCore,
                        _ currentLayout: LayoutState, currentControlBar: NSView,
                        _ videoGeo: VideoGeometry, viewportSize: NSSize, isRightToLeft: Bool) -> Bool {

    guard let thumbnails = player.info.currentPlayback?.thumbnails,
          let ffThumbnail = thumbnails.getThumbnail(forSecond: previewTimeSec) else {
      isHidden = true
      return false
    }

    let log = player.log
    let rotatedImage = ffThumbnail.image
    var thumbWidth: Double = rotatedImage.size.width
    var thumbHeight: Double = rotatedImage.size.height
    let videoAspectCAR = videoGeo.videoAspectCAR

    guard thumbWidth > 0, thumbHeight > 0 else {
      log.error("Cannot display thumbnail: thumbnail width or height is not positive!")
      isHidden = true
      return false
    }
    var thumbAspect = thumbWidth / thumbHeight

    // The aspect ratio of some videos is different at display time. May need to resize these videos
    // once the actual aspect ratio is known. (Should they be resized before being stored on disk? Doing so
    // would increase the file size without improving the quality, whereas resizing on the fly seems fast enough).
    if thumbAspect != videoAspectCAR {
      thumbHeight = (thumbWidth / videoAspectCAR).rounded()
      /// Recalculate this for later use (will use it and `thumbHeight`, and derive width)
      thumbAspect = thumbWidth / thumbHeight
    }

    /// Calculate `availableHeight` (viewport height, minus top & bottom bars)
    let availableHeight = viewportSize.height - currentLayout.insideTopBarHeight - currentLayout.insideBottomBarHeight - thumbnailExtraOffsetY - thumbnailExtraOffsetY

    let sizeOption: Preference.ThumbnailSizeOption = Preference.enum(for: .thumbnailSizeOption)
    switch sizeOption {
    case .fixedSize:
      // Stored thumb size should be correct (but may need to be scaled down)
      break
    case .scaleWithViewport:
      // Scale thumbnail as percentage of available height
      let percentage = min(1, max(0, Preference.double(for: .thumbnailDisplayedSizePercentage) / 100.0))
      thumbHeight = availableHeight * percentage
    }

    // Thumb too small?
    if thumbHeight < Constants.Distance.Thumbnail.minHeight {
      thumbHeight = Constants.Distance.Thumbnail.minHeight
    }

    // Thumb too tall?
    if thumbHeight > availableHeight {
      // Scale down thumbnail so it doesn't overlap top or bottom bars
      thumbHeight = availableHeight
    }
    thumbWidth = thumbHeight * thumbAspect

    // Also scale down thumbnail if it's wider than the viewport
    let availableWidth = viewportSize.width - thumbnailExtraOffsetX - thumbnailExtraOffsetX
    if thumbWidth > availableWidth {
      thumbWidth = availableWidth
      thumbHeight = thumbWidth / thumbAspect
    }

    let oscOriginInWindowY = currentControlBar.superview!.convert(currentControlBar.frame.origin, to: nil).y
    let oscHeight = currentControlBar.frame.size.height

    let showAbove: Bool
    if currentLayout.isMusicMode {
      showAbove = true  // always show above in music mode
    } else {
      switch currentLayout.oscPosition {
      case .top:
        showAbove = false
      case .bottom:
        showAbove = true
      case .floating:
        let totalMargin = thumbnailExtraOffsetY + thumbnailExtraOffsetY
        let availableHeightBelow = max(0, oscOriginInWindowY - currentLayout.insideBottomBarHeight - totalMargin)
        if availableHeightBelow > thumbHeight {
          // Show below by default, if there is space for the desired size
          showAbove = false
        } else {
          // If not enough space to show the full-size thumb below, then show above if it has more space
          let availableHeightAbove = max(0, viewportSize.height - (oscOriginInWindowY + oscHeight + totalMargin + currentLayout.insideTopBarHeight))
          showAbove = availableHeightAbove > availableHeightBelow
          if showAbove, thumbHeight > availableHeightAbove {
            // Scale down thumbnail so it doesn't get clipped by the side of the window
            thumbHeight = availableHeightAbove
            thumbWidth = thumbHeight * thumbAspect
          }
        }

        if !showAbove, thumbHeight > availableHeightBelow {
          thumbHeight = availableHeightBelow
          thumbWidth = thumbHeight * thumbAspect
        }
      }
    }

    // Need integers below.
    thumbWidth = round(thumbWidth)
    thumbHeight = round(thumbHeight)

    guard thumbWidth >= Constants.Distance.Thumbnail.minHeight,
          thumbHeight >= Constants.Distance.Thumbnail.minHeight else {
      log.verbose("Not enough space to display thumbnail")
      isHidden = true
      return false
    }

    let cornerRadius = updateBorderStyle(thumbWidth: thumbWidth, thumbHeight: thumbHeight)

    // Scaling is a potentially expensive operation, so do not change the last image if no change is needed
    if thumbnails.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp {
      thumbnails.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp

      let finalImage: NSImage
      // Apply crop first. Then aspect
      let croppedImage: NSImage
      if let normalizedCropRect = videoGeo.cropRectNormalized {
        croppedImage = rotatedImage.cropped(normalizedCropRect: normalizedCropRect)
      } else {
        croppedImage = rotatedImage
      }
      finalImage = croppedImage.resized(newWidth: Int(thumbWidth), newHeight: Int(thumbHeight), cornerRadius: cornerRadius)
      self.image = finalImage
      widthConstraint.constant = finalImage.size.width
      heightConstraint.constant = finalImage.size.height
    }

    let thumbOriginY: CGFloat
    if showAbove {
      // Show thumbnail above seek time, which is above slider
      thumbOriginY = oscOriginInWindowY + oscHeight + thumbnailExtraOffsetY
    } else {
      // Show thumbnail below slider
      thumbOriginY = max(thumbnailExtraOffsetY, oscOriginInWindowY - thumbHeight - thumbnailExtraOffsetY)
    }
    // Constrain X origin so that it stays entirely inside the viewport (and not inside the outside sidebars)
    let minX = (isRightToLeft ? currentLayout.outsideTrailingBarWidth : currentLayout.outsideLeadingBarWidth) + thumbnailExtraOffsetX
    let maxX = minX + availableWidth
    let thumbOriginX = min(max(minX, round(originalPosX - thumbWidth / 2)), maxX - thumbWidth)
    frame.origin = NSPoint(x: thumbOriginX, y: thumbOriginY)

    if log.isTraceEnabled {
      log.trace("Displaying thumbnail \(showAbove ? "above" : "below") OSC, size \(frame.size)")
    }
    alphaValue = 1.0
    isHidden = false
    return true
  }
}
