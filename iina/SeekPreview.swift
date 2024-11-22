//
//  SeekPreview.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-21.
//  Copyright © 2024 lhc. All rights reserved.
//

extension PlayerWindowController {

  /// Encapsulates state & objects needed for seek preview UI.
  /// This class is not a view in itself.
  class SeekPreview {
    static let margins = MarginQuad(top: Constants.Distance.Thumbnail.extraOffsetY,
                                    trailing: Constants.Distance.Thumbnail.extraOffsetX,
                                    bottom: Constants.Distance.Thumbnail.extraOffsetY,
                                    leading: Constants.Distance.Thumbnail.extraOffsetX)

    let timeLabel = NSTextField()
    let thumbnailPeekView = ThumbnailPeekView()

    var timeLabelHorizontalCenterConstraint: NSLayoutConstraint!
    var timeLabelVerticalSpaceConstraint: NSLayoutConstraint!

    var animationState: UIAnimationState = .shown
    /// For auto hiding seek time & thumbnail after a timeout.
    var hideTimer: Timer?

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

    /// `posInWindowX` is where center of timeLabel, thumbnailPeekView should be
    // TODO: Investigate using CoreAnimation!
    // https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html
    func showPreview(withThumbnail showThumbnail: Bool, forTime previewTimeSec: Double,
                     posInWindowX: CGFloat, _ player: PlayerCore,
                     _ currentLayout: LayoutState, currentControlBar: NSView,
                     _ videoGeo: VideoGeometry, viewportSize: NSSize, isRightToLeft: Bool) -> Bool {

      let log = player.log
      let margins = SeekPreview.margins
      let timeLabelHeight = timeLabel.fittingSize.height
      let thumbStore = player.info.currentPlayback?.thumbnails
      let ffThumbnail = thumbStore?.getThumbnail(forSecond: previewTimeSec)

      var showThumbnail = showThumbnail
      var thumbWidth: Double
      var thumbHeight: Double
      if showThumbnail, let ffThumbnail {
        let rotatedImage = ffThumbnail.image
        thumbWidth = Double(rotatedImage.width)
        thumbHeight = Double(rotatedImage.height)
        if thumbWidth <= 0 || thumbHeight <= 0 {
          showThumbnail = false
        }
      } else {
        showThumbnail = false
        thumbWidth = 0
        thumbHeight = 0
      }

      /// Calculate `availableHeight`: viewport height, minus top & bottom bars, minus extra space
      let availableHeight = viewportSize.height - currentLayout.insideBars.totalHeight - margins.totalHeight - timeLabelHeight
      /// `availableWidth`: viewport width, minus extra space
      let availableWidth = viewportSize.width - margins.totalWidth
      let oscOriginInWindowY = currentControlBar.superview!.convert(currentControlBar.frame.origin, to: nil).y
      let oscHeight = currentControlBar.frame.size.height

      var thumbAspect = showThumbnail ? (thumbWidth / thumbHeight) : 1.0

      if showThumbnail {
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
          // Need to check available space in viewport above & below OSC
          let totalExtraVerticalSpace = margins.totalHeight + timeLabelHeight
          let availableHeightBelow = max(0, oscOriginInWindowY - currentLayout.insideBottomBarHeight - totalExtraVerticalSpace)
          if availableHeightBelow > thumbHeight {
            // Show below by default, if there is space for the desired size
            showAbove = false
          } else {
            // If not enough space to show the full-size thumb below, then show above if it has more space
            let availableHeightAbove = max(0, viewportSize.height - (oscOriginInWindowY + oscHeight + totalExtraVerticalSpace + currentLayout.insideTopBarHeight))
            showAbove = availableHeightAbove > availableHeightBelow
            if showThumbnail, showAbove, thumbHeight > availableHeightAbove {
              // Scale down thumbnail so it doesn't get clipped by the side of the window
              thumbHeight = availableHeightAbove
              thumbWidth = thumbHeight * thumbAspect
            }
          }

          if showThumbnail, !showAbove, thumbHeight > availableHeightBelow {
            thumbHeight = availableHeightBelow
            thumbWidth = thumbHeight * thumbAspect
          }
        }
      }

      // Need integers below.
      thumbWidth = round(thumbWidth)
      thumbHeight = round(thumbHeight)

      let timeLabelOriginY: CGFloat
      let thumbOriginY: CGFloat
      if showAbove {
        // Show thumbnail above seek time, which is above slider
        timeLabelOriginY = oscOriginInWindowY + oscHeight + margins.bottom
        thumbOriginY = timeLabelOriginY + timeLabelHeight
      } else {
        // Show thumbnail below slider
        timeLabelOriginY = oscOriginInWindowY - margins.top - timeLabelHeight
        thumbOriginY = timeLabelOriginY - thumbHeight
      }
      // Constrain X origin so that it stays entirely inside the viewport (and not inside the outside sidebars)
      let minX = isRightToLeft ? currentLayout.outsideTrailingBarWidth + margins.trailing : currentLayout.outsideLeadingBarWidth + margins.leading
      let maxX = minX + availableWidth
      let thumbOriginX = min(max(minX, round(posInWindowX - thumbWidth / 2)), maxX - thumbWidth)

      let thumbFrame = NSRect(x: thumbOriginX, y: thumbOriginY, width: thumbWidth, height: thumbHeight)

      log.verbose{"TimeLabel centerX=\(posInWindowX), originY=\(timeLabelOriginY); thumbFrame=\(thumbFrame)"}
      timeLabelHorizontalCenterConstraint.constant = posInWindowX
      timeLabelVerticalSpaceConstraint.constant = timeLabelOriginY

      if showThumbnail && (thumbWidth < Constants.Distance.Thumbnail.minHeight || thumbHeight < Constants.Distance.Thumbnail.minHeight) {
        log.verbose("Not enough space to display thumbnail")
        showThumbnail = false
      }

      if showThumbnail {
        // Scaling is a potentially expensive operation, so do not change the last image if no change is needed
        let ffThumbnail = ffThumbnail!
        let somethingChanged = thumbStore!.currentDisplayedThumbFFTimestamp != ffThumbnail.timestamp || thumbnailPeekView.frame.width != thumbFrame.width || thumbnailPeekView.frame.height != thumbFrame.height
        if somethingChanged {
          thumbStore!.currentDisplayedThumbFFTimestamp = ffThumbnail.timestamp

          let cornerRadius = thumbnailPeekView.updateBorderStyle(thumbWidth: thumbWidth, thumbHeight: thumbHeight)

          // Apply crop first. Then aspect
          // FIXME: Cropped+Rotated is broken! Need to rotate crop box coordinates to match image rotation!
          let croppedImage: CGImage
          let rotatedImage = ffThumbnail.image
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

        thumbnailPeekView.frame.origin = thumbFrame.origin
        log.trace{"Displaying thumbnail \(showAbove ? "above" : "below") OSC, frame=\(thumbFrame)"}
        thumbnailPeekView.alphaValue = 1.0
      }

      timeLabel.alphaValue = 1.0
      timeLabel.isHidden = false
      thumbnailPeekView.isHidden = !showThumbnail

      return true
    }
  }

  // MARK: - PlayerWindowController methods

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
    guard seekPreview.animationState == .shown else { return }
    seekPreview.hideTimer?.invalidate()
    seekPreview.hideTimer = Timer.scheduledTimer(timeInterval: Constants.TimeInterval.seekPreviewHideTimeout,
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
    seekPreview.hideTimer?.invalidate()

    if animated {
      var tasks: [IINAAnimation.Task] = []

      tasks.append(IINAAnimation.Task(duration: IINAAnimation.OSDAnimationDuration * 0.5) { [self] in
        // Don't hide overlays when in PIP or when they are not actually shown
        seekPreview.animationState = .willHide
        seekPreview.thumbnailPeekView.animator().alphaValue = 0
        seekPreview.timeLabel.animator().alphaValue = 0
        if isShowingFadeableViewsForSeek {
          isShowingFadeableViewsForSeek = false
          resetFadeTimer()
        }
      })

      tasks.append(IINAAnimation.Task(duration: 0) { [self] in
        // if no interrupt then hide animation
        guard seekPreview.animationState == .willHide else { return }
        seekPreview.animationState = .hidden
        seekPreview.thumbnailPeekView.isHidden = true
        seekPreview.timeLabel.isHidden = true
      })

      animationPipeline.submit(tasks)
    } else {
      seekPreview.thumbnailPeekView.isHidden = true
      seekPreview.timeLabel.isHidden = true
      seekPreview.animationState = .hidden
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
    let notInMusicModeDisabled = !currentLayout.isMusicMode || (Preference.bool(for: .enableThumbnailForMusicMode) && musicModeGeo.isVideoVisible)

    // First check if both time & thumbnail are disabled
    guard let currentControlBar, notInMusicModeDisabled else {
      seekPreview.timeLabel.isHidden = true
      seekPreview.thumbnailPeekView.isHidden = true
      return
    }

    let centerOfKnobInSliderCoordX = playSlider.computeCenterOfKnobInSliderCoordXGiven(pointInWindow: pointInWindow)

    let playbackPositionRatio = playSlider.computeProgressRatioGiven(centerOfKnobInSliderCoordX:
                                                                      centerOfKnobInSliderCoordX)
    let previewTimeSec = mediaDuration * playbackPositionRatio
    let stringRepresentation = VideoTime.string(from: previewTimeSec)
    if seekPreview.timeLabel.stringValue != stringRepresentation {
      seekPreview.timeLabel.stringValue = stringRepresentation
    }

    // May need to adjust X to account for knob width
    let pointInSlider = NSPoint(x: centerOfKnobInSliderCoordX, y: 0)
    let pointInWindowCorrected = NSPoint(x: playSlider.convert(pointInSlider, to: nil).x, y: pointInWindow.y)

    // - 2. Thumbnail Preview

    var showThumbnail = Preference.bool(for: .enableThumbnailPreview)
    if isScrollingOrDraggingPlaySlider {
      // Thumbnail preview during seek. Is this feature enabled?
      showThumbnail = showThumbnail && Preference.bool(for: .showThumbnailDuringSliderSeek)
    }

    // Need to ensure OSC is displayed if showing thumbnail preview
    if showThumbnail && currentLayout.hasFadeableOSC {
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

    let didShow = seekPreview.showPreview(withThumbnail: showThumbnail, forTime: previewTimeSec, posInWindowX: pointInWindowCorrected.x, player, currentLayout,
                                               currentControlBar: currentControlBar, geo.video,
                                               viewportSize: viewportView.frame.size,
                                               isRightToLeft: videoView.userInterfaceLayoutDirection == .rightToLeft)
    guard didShow else { return }
    seekPreview.animationState = .shown
    // Start timer (or reset it), even if just hovering over the play slider. The Cocoa "mouseExited" event doesn't fire
    // reliably, so using a timer works well as a failsafe.
    resetSeekPreviewlTimer()
  }

}
