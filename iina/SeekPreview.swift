//
//  SeekPreview.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-21.
//  Copyright © 2024 lhc. All rights reserved.
//

class SeekPreview {

  /// Seek Preview: time label
  let timeLabel = NSTextField()
  var timeLabelHorizontalCenterConstraint: NSLayoutConstraint!
  var timeLabelVerticalSpaceConstraint: NSLayoutConstraint!
  /// Seek Preview: thumbnail
  let thumbnailPeekView = ThumbnailPeekView()


  init() {
    timeLabel.identifier = .init("SeekTimeLabel")
    timeLabel.controlSize = .large
    timeLabel.translatesAutoresizingMaskIntoConstraints = false
    timeLabel.isBordered = false
    timeLabel.drawsBackground = false
    timeLabel.isBezeled = false
    timeLabel.isEditable = false
    timeLabel.isSelectable = false
    timeLabel.isEnabled = true
    timeLabel.refusesFirstResponder = true
    timeLabel.alignment = .center
    timeLabel.setContentHuggingPriority(.required, for: .horizontal)
    timeLabel.setContentHuggingPriority(.required, for: .vertical)

    thumbnailPeekView.identifier = .init("ThumbnailPeekView")
    thumbnailPeekView.isHidden = true

    timeLabel.isHidden = true
  }

  // TODO: Investigate using CoreAnimation!
  // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html
  func displayThumbnail(forTime previewTimeSec: Double, originalPosX: CGFloat, _ player: PlayerCore,
                        _ currentLayout: LayoutState, currentControlBar: NSView,
                        _ videoGeo: VideoGeometry, viewportSize: NSSize, isRightToLeft: Bool,
                        margins: MarginQuad) -> Bool {

    guard let thumbnails = player.info.currentPlayback?.thumbnails,
          let ffThumbnail = thumbnails.getThumbnail(forSecond: previewTimeSec) else {
      thumbnailPeekView.isHidden = true
      return false
    }

    let log = player.log
    let rotatedImage = ffThumbnail.image
    var thumbWidth: Double = Double(rotatedImage.width)
    var thumbHeight: Double = Double(rotatedImage.height)

    /// Calculate `availableHeight`: viewport height, minus top & bottom bars, minus extra space
    let availableHeight = viewportSize.height - currentLayout.insideBars.totalHeight - margins.totalHeight
    /// `availableWidth`: viewport width, minus extra space
    let availableWidth = viewportSize.width - margins.totalWidth
    let oscOriginInWindowY = currentControlBar.superview!.convert(currentControlBar.frame.origin, to: nil).y
    let oscHeight = currentControlBar.frame.size.height

    let hasThumbnail = thumbWidth > 0 && thumbHeight > 0
    var thumbAspect = hasThumbnail ? (thumbWidth / thumbHeight) : 1.0

    if hasThumbnail {
      // The aspect ratio of some videos is different at display time. May need to resize these videos
      // once the actual aspect ratio is known. (Should they be resized before being stored on disk? Doing so
      // would increase the file size without improving the quality, whereas resizing on the fly seems fast enough).
      let videoAspectCAR = videoGeo.videoAspectCAR
      if thumbAspect != videoAspectCAR {
        thumbHeight = (thumbWidth / videoAspectCAR).rounded()
        /// Recalculate this for later use (will use it and `thumbHeight`, and derive width)
        thumbAspect = thumbWidth / thumbHeight
      }

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
      if thumbWidth > availableWidth {
        thumbWidth = availableWidth
        thumbHeight = thumbWidth / thumbAspect
      }
    }

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
        let totalMargin = margins.totalHeight
        let availableHeightBelow = max(0, oscOriginInWindowY - currentLayout.insideBottomBarHeight - totalMargin)
        if availableHeightBelow > thumbHeight {
          // Show below by default, if there is space for the desired size
          showAbove = false
        } else {
          // If not enough space to show the full-size thumb below, then show above if it has more space
          let availableHeightAbove = max(0, viewportSize.height - (oscOriginInWindowY + oscHeight + totalMargin + currentLayout.insideTopBarHeight))
          showAbove = availableHeightAbove > availableHeightBelow
          if hasThumbnail, showAbove, thumbHeight > availableHeightAbove {
            // Scale down thumbnail so it doesn't get clipped by the side of the window
            thumbHeight = availableHeightAbove
            thumbWidth = thumbHeight * thumbAspect
          }
        }

        if hasThumbnail, !showAbove, thumbHeight > availableHeightBelow {
          thumbHeight = availableHeightBelow
          thumbWidth = thumbHeight * thumbAspect
        }
      }
    }

    // Need integers below.
    thumbWidth = round(thumbWidth)
    thumbHeight = round(thumbHeight)

    let thumbOriginY: CGFloat
    if showAbove {
      // Show thumbnail above seek time, which is above slider
      thumbOriginY = oscOriginInWindowY + oscHeight + margins.bottom
    } else {
      // Show thumbnail below slider
      thumbOriginY = max(margins.top, oscOriginInWindowY - thumbHeight - margins.top)
    }
    // Constrain X origin so that it stays entirely inside the viewport (and not inside the outside sidebars)
    let minX = isRightToLeft ? currentLayout.outsideTrailingBarWidth + margins.trailing : currentLayout.outsideLeadingBarWidth + margins.leading
    let maxX = minX + availableWidth
    let thumbOriginX = min(max(minX, round(originalPosX - thumbWidth / 2)), maxX - thumbWidth)

    let thumbFrame = NSRect(x: thumbOriginX, y: thumbOriginY, width: thumbWidth, height: thumbHeight)

    if hasThumbnail {
      guard thumbWidth >= Constants.Distance.Thumbnail.minHeight,
            thumbHeight >= Constants.Distance.Thumbnail.minHeight else {
        log.verbose("Not enough space to display thumbnail")
        thumbnailPeekView.isHidden = true
        return false
      }

      // Scaling is a potentially expensive operation, so do not change the last image if no change is needed
      let somethingChanged = thumbnails.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp || thumbnailPeekView.frame.width != thumbFrame.width || thumbnailPeekView.frame.height != thumbFrame.height
      if somethingChanged {
        thumbnails.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp

        let cornerRadius = thumbnailPeekView.updateBorderStyle(thumbWidth: thumbWidth, thumbHeight: thumbHeight)

        // Apply crop first. Then aspect
        // FIXME: Cropped+Rotated is broken! Need to rotate crop box coordinates to match image rotation!
        let croppedImage: CGImage
        if let normalizedCropRect = videoGeo.cropRectNormalized {
          croppedImage = rotatedImage.cropped(normalizedCropRect: normalizedCropRect)
        } else {
          croppedImage = rotatedImage
        }
        let finalImage = croppedImage.resized(newWidth: Int(thumbWidth), newHeight: Int(thumbHeight), cornerRadius: cornerRadius)
        thumbnailPeekView.image = NSImage.from(finalImage)
        thumbnailPeekView.widthConstraint.constant = thumbFrame.width
        thumbnailPeekView.heightConstraint.constant = thumbFrame.height
      }
    }

    thumbnailPeekView.frame.origin = thumbFrame.origin
    log.trace{"Displaying thumbnail \(showAbove ? "above" : "below") OSC, frame=\(thumbFrame)"}
    thumbnailPeekView.alphaValue = 1.0
    thumbnailPeekView.isHidden = false
    return true
  }
}

// MARK: - PlayerWindowController methods

extension PlayerWindowController {

  func shouldSeekPreviewBeVisible(forPointInWindow pointInWindow: NSPoint) -> Bool {
    guard !player.disableUI,
          !isAnimatingLayoutTransition,
          !osd.isShowingPersistentOSD,
          currentLayout.hasControlBar else {
      return false
    }
    // Although isScrollingOrDraggingPlaySlider can be true when scrolling volume,
    // there shouldn't be enough overlap to create a problem. Too lazy to get this
    // perfect at this stage.
    return isScrollingOrDraggingPlaySlider || isPoint(pointInWindow, inAnyOf: [playSlider])
  }

  func resetSeekPreviewlTimer() {
    guard seekPreviewAnimationState == .shown else { return }
    hideSeekPreviewTimer?.invalidate()
    hideSeekPreviewTimer = Timer.scheduledTimer(timeInterval: Constants.TimeInterval.seekPreviewHideTimeout,
                                                target: self, selector: #selector(self.seekPreviewTimeout),
                                                userInfo: nil, repeats: false)
  }

  @objc private func seekPreviewTimeout() {
    let pointInWindow = window!.convertPoint(fromScreen: NSEvent.mouseLocation)
    guard !shouldSeekPreviewBeVisible(forPointInWindow: pointInWindow) else {
      resetSeekPreviewlTimer()
      return
    }
    hideSeekPreview(animated: true)
  }

  @objc func hideSeekPreview(animated: Bool = false) {
    hideSeekPreviewTimer?.invalidate()

    if animated {
      var tasks: [IINAAnimation.Task] = []

      tasks.append(IINAAnimation.Task(duration: IINAAnimation.OSDAnimationDuration * 0.5) { [self] in
        // Don't hide overlays when in PIP or when they are not actually shown
        seekPreviewAnimationState = .willHide
        seekPreview.thumbnailPeekView.animator().alphaValue = 0
        seekPreview.timeLabel.isHidden = true
        if isShowingFadeableViewsForSeek {
          isShowingFadeableViewsForSeek = false
          resetFadeTimer()
        }
      })

      tasks.append(IINAAnimation.Task(duration: 0) { [self] in
        // if no interrupt then hide animation
        guard seekPreviewAnimationState == .willHide else { return }
        seekPreviewAnimationState = .hidden
        seekPreview.thumbnailPeekView.isHidden = true
        seekPreview.timeLabel.isHidden = true
      })

      animationPipeline.submit(tasks)
    } else {
      seekPreview.thumbnailPeekView.isHidden = true
      seekPreview.timeLabel.isHidden = true
      seekPreviewAnimationState = .hidden
    }
  }

  /// Display time label & thumbnail when mouse over slider
  func refreshSeekPreviewAsync(forPointInWindow pointInWindow: NSPoint) {
    thumbDisplayTicketCounter += 1
    let currentTicket = thumbDisplayTicketCounter

    DispatchQueue.main.async { [self] in
      guard currentTicket == thumbDisplayTicketCounter else { return }

      guard shouldSeekPreviewBeVisible(forPointInWindow: pointInWindow),
            let duration = player.info.playbackDurationSec else {
        hideSeekPreview()
        return
      }
      showSeekPreview(forPointInWindow: pointInWindow, mediaDuration: duration)
    }
  }

  /// Should only be called by `refreshSeekPreviewAsync`
  private func showSeekPreview(forPointInWindow pointInWindow: NSPoint, mediaDuration: CGFloat) {
    // - 1. Seek Time Label

    let knobCenterOffsetInPlaySlider = playSlider.computeCenterOfKnobInSliderCoordXGiven(pointInWindow: pointInWindow)

    seekPreview.timeLabelHorizontalCenterConstraint?.constant = knobCenterOffsetInPlaySlider

    let playbackPositionRatio = playSlider.computeProgressRatioGiven(centerOfKnobInSliderCoordX:
                                                                      knobCenterOffsetInPlaySlider)
    let previewTimeSec = mediaDuration * playbackPositionRatio
    let stringRepresentation = VideoTime.string(from: previewTimeSec)
    if seekPreview.timeLabel.stringValue != stringRepresentation {
      seekPreview.timeLabel.stringValue = stringRepresentation
    }
    seekPreview.timeLabel.isHidden = false

    // - 2. Thumbnail Preview

    if isScrollingOrDraggingPlaySlider {
      // Thumbnail preview during seek
      guard Preference.bool(for: .enableThumbnailPreview) && Preference.bool(for: .showThumbnailDuringSliderSeek) else {
        // Feature is disabled
        seekPreview.thumbnailPeekView.isHidden = true
        return
      }
      // Need to ensure OSC is displayed if showing thumbnail preview
      let hasFadeableOSC = currentLayout.hasFadeableOSC
      if hasFadeableOSC {
        let hasTopBarFadeableOSC = currentLayout.oscPosition == .top && currentLayout.topBarView == .showFadeableTopBar
        let isOSCHidden = hasTopBarFadeableOSC ? fadeableTopBarAnimationState == .hidden : fadeableViewsAnimationState == .hidden
        if isOSCHidden {
          showFadeableViews(thenRestartFadeTimer: false, duration: 0, forceShowTopBar: hasTopBarFadeableOSC)
        } else {
          hideFadeableViewsTimer?.invalidate()
        }
        // Set this to remind ourselves to restart the fade timer when seek is done
        isShowingFadeableViewsForSeek = true
      }
    }

    guard let currentControlBar else {
      seekPreview.thumbnailPeekView.isHidden = true
      return
    }
    guard !currentLayout.isMusicMode || (Preference.bool(for: .enableThumbnailForMusicMode) && musicModeGeo.isVideoVisible) else {
      seekPreview.thumbnailPeekView.isHidden = true
      return
    }

    let thumbMargins = MarginQuad(top: Constants.Distance.Thumbnail.extraOffsetY, trailing: Constants.Distance.Thumbnail.extraOffsetX,
                                  bottom: Constants.Distance.Thumbnail.extraOffsetY, leading: Constants.Distance.Thumbnail.extraOffsetX)

    let didShow = seekPreview.displayThumbnail(forTime: previewTimeSec, originalPosX: pointInWindow.x, player, currentLayout,
                                               currentControlBar: currentControlBar, geo.video,
                                               viewportSize: viewportView.frame.size,
                                               isRightToLeft: videoView.userInterfaceLayoutDirection == .rightToLeft,
                                               margins: thumbMargins)
    guard didShow else { return }
    seekPreviewAnimationState = .shown
    // Start timer (or reset it), even if just hovering over the play slider. The Cocoa "mouseExited" event doesn't fire
    // reliably, so using a timer works well as a failsafe.
    resetSeekPreviewlTimer()
  }

}
