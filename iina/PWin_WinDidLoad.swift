//
//  PWin_WinDidLoad.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-23.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {

  /// Called when window is initially loaded. Add all subviews here.
  override func windowDidLoad() {
    log.verbose("PlayerWindow windowDidLoad starting")
    super.windowDidLoad()
    guard let window else { return }
    guard let contentView = window.contentView else { return }

    miniPlayer = MiniPlayerViewController()
    miniPlayer.windowController = self

    viewportView.player = player

    co = buildObservers()

    /// Set base options for `collectionBehavior` here, and then insert/remove full screen options
    /// using `resetCollectionBehavior`. Do not mess with the base options again because doing so seems
    /// to cause flickering while animating.
    /// Always use option `.fullScreenDisallowsTiling`. As of MacOS 14.2.1, tiling is at best glitchy &
    /// at worst results in an infinite loop with our code.
    // FIXME: support tiling for at least native full screen
    window.collectionBehavior = [.managed, .fullScreenDisallowsTiling]

    window.initialFirstResponder = nil

    // size
    window.minSize = Constants.SizeLimit.minVideoSize

    // need to deal with control bar, so we handle it manually
    window.isMovableByWindowBackground  = false

    // Registers this window for didChangeScreenProfileNotification
    window.displaysWhenScreenProfileChanges = true

    leftTimeLabel.mode = .current
    rightTimeLabel.mode = Preference.bool(for: .showRemainingTime) ? .remaining : .duration

    // gesture recognizers
    rotationHandler.windowController = self
    magnificationHandler.windowController = self
    contentView.addGestureRecognizer(magnificationHandler.magnificationGestureRecognizer)
    contentView.addGestureRecognizer(rotationHandler.rotationGestureRecognizer)

    // scroll wheel
    playSlider.scrollWheelDelegate = PlaySliderScrollWheel(slider: playSlider, log)
    volumeSlider.scrollWheelDelegate = VolumeSliderScrollWheel(slider: volumeSlider, log)
    windowScrollWheel = PWinScrollWheel(self)

    playlistView.windowController = self
    quickSettingView.windowController = self

    // other initialization
    osdAccessoryProgress.usesThreadedAnimation = false

    /// Note that this will add `videoView`, but at first run it will not yet have a video layer.
    /// Need to wait until after mpv is initialized before creating `videoView.layer`
    addVideoViewToWindow()
    player.start()

    /// Use an animation task to init views, to hopefully prevent partial/redundant draws.
    /// NOTE: this will likely execute *after* `_showWindow()`
    animationPipeline.submitInstantTask{ [self] in

      // Top bar: other init
      topBarView.clipsToBounds = true
      topBarBottomBorder.identifier = .init(rawValue: "TopBar-BottomBorder")
      topBarBottomBorder.fillColor = NSColor.titleBarBorder

      viewportView.clipsToBounds = true

      /// Set `window.contentView`'s background to black so that the windows behind this one don't bleed through
      /// when `lockViewportToVideoSize` is disabled, or when in legacy full screen on a Macbook screen  with a
      /// notch and the preference `allowVideoToOverlapCameraHousing` is false. Also needed so that sidebars don't
      /// bleed through during their show/hide animations.
      setEmptySpaceColor(to: Constants.Color.defaultWindowBackgroundColor)

      applyThemeMaterial()

      // Titlebar accessories

      // Update this here to reduce animation jitter on older versions of MacOS:
      viewportTopOffsetFromTopBarTopConstraint.constant = PlayerWindowController.standardTitleBarHeight

      // Work around a bug in macOS Ventura where HDR content becomes dimmed when playing in full
      // screen mode once overlaying views are fully hidden (issue #3844). After applying this
      // workaround another bug in Ventura where an external monitor goes black could not be
      // reproduced (issue #4015). The workaround adds a tiny subview with such a low alpha level it
      // is invisible to the human eye. This workaround may not be effective in all cases.
      if #available(macOS 13, *) {
        let view = NSView(frame: NSRect(origin: .zero, size: NSSize(width: 0.1, height: 0.1)))
        view.layer?.backgroundColor = Constants.Color.defaultWindowBackgroundColor
        view.layer?.opacity = 0.01
        contentView.addSubview(view)
    }

      initSeekPreview(in: contentView)
      initTitleBarAccessories()
      initBottomBarView(in: contentView, style: .visualEffectView)
      initSpeedLabel()
      initPlaybackBtnsView()
      initVolumeView()
      initAlbumArtView()
      fragPositionSliderView.userInterfaceLayoutDirection = .leftToRight

      bufferIndicatorView.roundCorners()
      additionalInfoView.roundCorners()
      osdVisualEffectView.roundCorners()

      contentView.configureSubtreeForCoreAnimation()

      // Make sure to set this inside the animation task! See note above
      loaded = true

      // Update to corect values before displaying. Only useful when restoring at launch
      updateUI()

      if let priorState = priorStateIfRestoring {
        if let layoutSpec = priorState.layoutSpec {
          // Preemptively set window frames to prevent windows from "jumping" during restore
          if layoutSpec.mode == .musicMode {
            let geo = priorState.geoSet.musicMode.toPWinGeometry()
            player.window.setFrameImmediately(geo, notify: false)
          } else {
            let geo = priorState.geoSet.windowed
            player.window.setFrameImmediately(geo, notify: false)
          }
        }

        defaultAlbumArtView.isHidden = player.info.isVideoTrackSelected
      }

      if player.disableUI { hideFadeableViews() }

      log.verbose("PlayerWindow windowDidLoad done")
      player.events.emit(.windowLoaded)
    }
  }

  private func initSeekPreview(in contentView: NSView) {
    // This is above the play slider and by default, will swallow clicks. Send events to play slider instead
    seekPreview.timeLabel.nextResponder = playSlider
    contentView.addSubview(seekPreview.timeLabel, positioned: .below, relativeTo: osdVisualEffectView)
    contentView.addSubview(seekPreview.thumbnailPeekView, positioned: .below, relativeTo: seekPreview.timeLabel)

    // Yes, left, not leading!
    seekPreview.timeLabelHorizontalCenterConstraint = seekPreview.timeLabel.centerXAnchor.constraint(equalTo: contentView.leftAnchor, constant: 200) // dummy value for now
    seekPreview.timeLabelHorizontalCenterConstraint.identifier = .init("SeekTimeHoverLabelHSpaceConstraint")
    seekPreview.timeLabelHorizontalCenterConstraint.isActive = true

    // This is a bit confusing but the constant here can be thought of as the X value in window,
    // not flipped (so, larger values toward the top)
    seekPreview.timeLabelVerticalSpaceConstraint = contentView.bottomAnchor.constraint(equalTo: seekPreview.timeLabel.bottomAnchor, constant: 0)
    seekPreview.timeLabelVerticalSpaceConstraint.identifier = .init("SeekTimeHoverLabelVSpaceConstraint")
    seekPreview.timeLabelVerticalSpaceConstraint?.isActive = true
  }

  private func initTitleBarAccessories() {
    let builder = CustomTitleBar.shared
    let iconSpacingH = Constants.Distance.titleBarIconHSpacing
    // - LEADING

    let leadingTB = leadingTitleBarAccessoryView
    leadingTB.idString = "leadingTitleBarAccessoryView"

    let leadingSpacerLeading = NSView()
    leadingSpacerLeading.identifier = .init("leadingTitleBarLeadingSpacer")
    leadingTitleBarLeadingSpaceConstraint = leadingSpacerLeading.widthAnchor.constraint(equalToConstant: 0)
    leadingTitleBarLeadingSpaceConstraint?.isActive = true

    leadingSidebarToggleButton = builder.makeTitleBarButton(Images.sidebarLeading,
                                                            identifier: "leadingSidebarToggleButton",
                                                            target: self,
                                                            action: #selector(toggleLeadingSidebarVisibility(_:)))

    let leadingSpacerTrailing = NSView()
    leadingSpacerTrailing.identifier = .init("leadingTitleBarTrailingSpacer")
    leadingTitleBarTrailingSpaceConstraint = leadingSpacerTrailing.widthAnchor.constraint(equalToConstant: 0)
    leadingTitleBarTrailingSpaceConstraint?.isActive = true

    leadingTB.orientation = .horizontal
    leadingTB.alignment = .centerY
    leadingTB.distribution = .fill
    leadingTB.spacing = 0
    leadingTB.detachesHiddenViews = true
    leadingTB.setHuggingPriority(.init(500), for: .horizontal)

    leadingTB.addArrangedSubview(leadingSpacerLeading)
    leadingTB.addArrangedSubview(leadingSidebarToggleButton)
    leadingTB.addArrangedSubview(leadingSpacerTrailing)

    // - TRAILING

    let trailingTB = trailingTitleBarAccessoryView
    trailingTB.idString = "trailingTitleBarAccessoryView"

    let trailingSpacerLeading = NSView()
    trailingSpacerLeading.identifier = .init("trailingTitleBarLeadingSpacer")
    
    trailingTitleBarLeadingSpaceConstraint = trailingSpacerLeading.widthAnchor.constraint(equalToConstant: 0)
    trailingTitleBarLeadingSpaceConstraint?.isActive = true

    onTopButton = builder.makeTitleBarButton(Images.onTopOff,
                                             identifier: "onTopButton",
                                             target: self, action: #selector(toggleOnTop(_:)))
    onTopButton.alternateImage = Images.onTopOn

    trailingSidebarToggleButton = builder.makeTitleBarButton(Images.sidebarTrailing,
                                                             identifier: "trailingSidebarToggleButton",
                                                             target: self,
                                                             action: #selector(toggleTrailingSidebarVisibility(_:)))

    let trailingSpacerTrailing = NSView()
    trailingSpacerTrailing.identifier = .init("trailingTitleBarTrailingSpacer")
    trailingTitleBarTrailingSpaceConstraint = trailingSpacerTrailing.widthAnchor.constraint(equalToConstant: 0)
    trailingTitleBarTrailingSpaceConstraint?.isActive = true

    trailingTB.orientation = .horizontal
    trailingTB.alignment = .centerY
    trailingTB.distribution = .fill
    trailingTB.spacing = iconSpacingH
    trailingTB.detachesHiddenViews = true
    trailingTB.setHuggingPriority(.init(500), for: .horizontal)

    trailingTB.addArrangedSubview(trailingSpacerLeading)
    trailingTB.addArrangedSubview(trailingSidebarToggleButton)
    trailingTB.addArrangedSubview(onTopButton)
    trailingTB.addArrangedSubview(trailingSpacerTrailing)

    addTitleBarAccessoryViews()
  }

  func initBottomBarView(in contentView: NSView, style: Preference.OSCOverlayStyle) {
    bottomBarView.removeFromSuperview()
    switch style {
    case .visualEffectView:
      bottomBarView = NSVisualEffectView()
    case .clearGradient:
      bottomBarView = NSView()
      let gradient = CAGradientLayer()
      gradient.frame = bottomBarView.bounds
      // Top → Bottom
      gradient.startPoint = CGPoint(x: 0.5, y: 1.0)
      gradient.endPoint = CGPoint(x: 0.5, y: 0.0)
      // Ideally the gradient would use a quadratic function, but seems we are limited to linear, so just fudge it a bit.
      gradient.colors = [CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
                         CGColor(red: 0, green: 0, blue: 0, alpha: 0.3),
                         CGColor(red: 0, green: 0, blue: 0, alpha: 0.6)]
      bottomBarView.layer = gradient
      bottomBarView.wantsLayer = true
    }

    contentView.addSubview(bottomBarView, positioned: .above, relativeTo: viewportView)
    bottomBarView.clipsToBounds = true
    if let bottomBarView = bottomBarView as? NSVisualEffectView {
      bottomBarView.blendingMode = .withinWindow
      bottomBarView.material = .sidebar
      bottomBarView.state = .active
    } else {
      bottomBarView.wantsLayer = true
      bottomBarView.layer?.backgroundColor = .clear
    }
    bottomBarView.identifier = .init("bottomBarView")  // helps with debug logging
    bottomBarView.isHidden = true
    bottomBarView.translatesAutoresizingMaskIntoConstraints = false

    viewportBtmOffsetFromTopOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 0)
    viewportBtmOffsetFromTopOfBottomBarConstraint.isActive = true
    viewportBtmOffsetFromTopOfBottomBarConstraint.identifier = .init("viewportBtmOffsetFromTopOfBottomBarConstraint")

    viewportBtmOffsetFromBtmOfBottomBarConstraint = viewportView.bottomAnchor.constraint(equalTo: bottomBarView.bottomAnchor, constant: 0)
    viewportBtmOffsetFromBtmOfBottomBarConstraint.isActive = true
    viewportBtmOffsetFromBtmOfBottomBarConstraint.identifier = .init("viewportBtmOffsetFromBtmOfBottomBarConstraint")

    bottomBarLeadingSpaceConstraint = bottomBarView.leadingAnchor.constraint(equalTo: leadingSidebarView.trailingAnchor, constant: 0)
    bottomBarLeadingSpaceConstraint.isActive = true
    bottomBarLeadingSpaceConstraint.identifier = .init("bottomBarLeadingSpaceConstraint")

    bottomBarTrailingSpaceConstraint = bottomBarView.trailingAnchor.constraint(equalTo: trailingSidebarView.leadingAnchor, constant: 0)
    bottomBarTrailingSpaceConstraint.isActive = true
    bottomBarTrailingSpaceConstraint.identifier = .init("bottomBarTrailingSpaceConstraint")

    oscBottomMainView.identifier = .init("oscBottomMainView")  // helps with debug logging
    oscBottomMainView.spacing = 4
    oscBottomMainView.orientation = .horizontal
    oscBottomMainView.alignment = .centerY
    oscBottomMainView.distribution = .gravityAreas
    oscBottomMainView.translatesAutoresizingMaskIntoConstraints = false
    oscBottomMainView.wantsLayer = true
    oscBottomMainView.layer?.backgroundColor = .clear

    bottomBarTopBorder.identifier = .init("bottomBarTopBorder")  // helps with debug logging
    bottomBarTopBorder.boxType = .custom
    bottomBarTopBorder.titlePosition = .noTitle
    bottomBarTopBorder.borderWidth = 0
    bottomBarTopBorder.borderColor = NSColor.clear
    bottomBarTopBorder.fillColor = NSColor.titleBarBorder
    bottomBarTopBorder.translatesAutoresizingMaskIntoConstraints = false
    bottomBarView.addSubview(bottomBarTopBorder)
    bottomBarTopBorder.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    bottomBarTopBorder.bottomAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 1).isActive = true
  }

  private func initSpeedLabel() {
    speedLabel.identifier = .init("speedLabel")  // helps with debug logging
    speedLabel.translatesAutoresizingMaskIntoConstraints = false
    speedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 26).isActive = true
    speedLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    speedLabel.setContentCompressionResistancePriority(.required, for: .vertical)
    speedLabel.setContentHuggingPriority(.required, for: .horizontal)
    speedLabel.setContentHuggingPriority(.required, for: .vertical)
    speedLabel.font = NSFont.messageFont(ofSize: 10)
    speedLabel.textColor = .textColor
    speedLabel.alphaValue = 0.75
    speedLabel.isBordered = false
    speedLabel.drawsBackground = false
    speedLabel.isBezeled = false
    speedLabel.isEditable = false
    speedLabel.isSelectable = false
    speedLabel.isEnabled = true
    speedLabel.refusesFirstResponder = true
    speedLabel.alignment = .center

    speedLabel.nextResponder = playButton
  }

  private func initPlaybackBtnsView() {
    let oscGeo = currentLayout.controlBarGeo

    // Play button
    playButton.image = Images.play
    playButton.target = self
    playButton.action = #selector(playButtonAction(_:))
    playButton.refusesFirstResponder = true
    playButton.identifier = .init("playButton")  // helps with debug logging
    playButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    playButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    let playIconSize = oscGeo.playIconSize
    playBtnWidthConstraint = playButton.widthAnchor.constraint(equalToConstant: playIconSize)
    playBtnWidthConstraint.identifier = .init("playBtnWidthConstraint")
    playBtnWidthConstraint.priority = .init(850)  // allow to shrink for animations or speedLabel
    playBtnWidthConstraint.isActive = true
    let playAspectConstraint = playButton.widthAnchor.constraint(equalTo: playButton.heightAnchor)
    playAspectConstraint.isActive = true

    let playbackBtnsVStackView = ClickThroughStackView()
    playbackBtnsVStackView.identifier = .init("playbackBtnsVStackView")
    playbackBtnsVStackView.orientation = .vertical
    playbackBtnsVStackView.alignment = .centerX
    playbackBtnsVStackView.detachesHiddenViews = true
    playbackBtnsVStackView.layer?.backgroundColor = .clear
    playbackBtnsVStackView.spacing = 0
    playbackBtnsVStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    playbackBtnsVStackView.addView(speedLabel, in: .center)
    playbackBtnsVStackView.addView(playButton, in: .center)
    playbackBtnsVStackView.setHuggingPriority(.init(250), for: .vertical)
    playbackBtnsVStackView.setHuggingPriority(.init(250), for: .horizontal)
    playbackBtnsVStackView.translatesAutoresizingMaskIntoConstraints = false

    // Left Arrow button
    leftArrowButton.image = oscGeo.leftArrowImage
    leftArrowButton.target = self
    leftArrowButton.action = #selector(leftArrowButtonAction(_:))
    leftArrowButton.identifier = .init("leftArrowButton")
    leftArrowButton.refusesFirstResponder = true
    leftArrowButton.bounceOnClick = true

    // Right Arrow button
    rightArrowButton.image = oscGeo.rightArrowImage
    rightArrowButton.target = self
    rightArrowButton.action = #selector(rightArrowButtonAction(_:))
    rightArrowButton.identifier = .init("rightArrowButton")
    rightArrowButton.refusesFirstResponder = true
    rightArrowButton.bounceOnClick = true

    fragPlaybackBtnsView.identifier = .init("fragPlaybackBtnsView")
    fragPlaybackBtnsView.addSubview(leftArrowButton)
    fragPlaybackBtnsView.addSubview(playbackBtnsVStackView)
    fragPlaybackBtnsView.addSubview(rightArrowButton)

    playbackBtnsVStackView.heightAnchor.constraint(lessThanOrEqualTo: fragPlaybackBtnsView.heightAnchor).isActive = true

    fragPlaybackBtnsView.translatesAutoresizingMaskIntoConstraints = false
    fragPlaybackBtnsView.setContentHuggingPriority(.init(rawValue: 249), for: .vertical)  // hug superview more than default

    // Try to make sure the buttons' bounding boxes reach the full height, for activation
    // (their images will be limited by the width constraint & will stop scaling before this)
    let leftArrowHeightConstraint = leftArrowButton.heightAnchor.constraint(equalTo: fragPlaybackBtnsView.heightAnchor)
    leftArrowHeightConstraint.identifier = .init("leftArrowHeightConstraint")
    leftArrowHeightConstraint.priority = .defaultHigh
    leftArrowHeightConstraint.isActive = true
    let rightArrowHeightConstraint = rightArrowButton.heightAnchor.constraint(equalTo: fragPlaybackBtnsView.heightAnchor)
    rightArrowHeightConstraint.identifier = .init("rightArrowHeightConstraint")
    rightArrowHeightConstraint.priority = .defaultHigh
    rightArrowHeightConstraint.isActive = true

    // Video controllers and timeline indicators should not flip in a right-to-left language.
    fragPlaybackBtnsView.userInterfaceLayoutDirection = .leftToRight

    let playBtnVertOffsetConstraint = playButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    playBtnVertOffsetConstraint.isActive = true

    let playBtnHorizOffsetConstraint = playbackBtnsVStackView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor)
    playBtnHorizOffsetConstraint.isActive = true

    speedLabel.topAnchor.constraint(equalTo: fragPlaybackBtnsView.topAnchor).isActive = true

    fragPlaybackBtnsWidthConstraint = fragPlaybackBtnsView.widthAnchor.constraint(equalToConstant: oscGeo.totalPlayControlsWidth)
    fragPlaybackBtnsWidthConstraint.identifier = .init("fragPlaybackBtnsWidthConstraint")
    fragPlaybackBtnsWidthConstraint.isActive = true

    leftArrowBtnHorizOffsetConstraint = leftArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                 constant: oscGeo.leftArrowOffsetX)
    leftArrowBtnHorizOffsetConstraint.identifier = .init("leftArrowBtnHorizOffsetConstraint")
    leftArrowBtnHorizOffsetConstraint.isActive = true

    arrowBtnWidthConstraint = leftArrowButton.widthAnchor.constraint(equalToConstant: oscGeo.arrowIconWidth)
    arrowBtnWidthConstraint.identifier = .init("arrowBtnWidthConstraint")
    arrowBtnWidthConstraint.isActive = true

    rightArrowBtnHorizOffsetConstraint = rightArrowButton.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor,
                                                                                   constant: oscGeo.rightArrowOffsetX)
    rightArrowBtnHorizOffsetConstraint.identifier = .init("rightArrowBtnHorizOffsetConstraint")
    rightArrowBtnHorizOffsetConstraint.isActive = true

    // Left & Right arrow buttons are always same size
    let arrowBtnsEqualWidthConstraint = leftArrowButton.widthAnchor.constraint(equalTo: rightArrowButton.widthAnchor, multiplier: 1)
    arrowBtnsEqualWidthConstraint.identifier = .init("arrowBtnsEqualWidthConstraint")
    arrowBtnsEqualWidthConstraint.isActive = true

    let leftArrowBtnVertOffsetConstraint = leftArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    leftArrowBtnVertOffsetConstraint.isActive = true
    let rightArrowBtnVertOffsetConstraint = rightArrowButton.centerYAnchor.constraint(equalTo: fragPlaybackBtnsView.centerYAnchor)
    rightArrowBtnVertOffsetConstraint.isActive = true
  }

  private func initVolumeView() {
    // We are early in the loading process. Don't trust cached ControlBarGeometry too much...
    let oscGeo = ControlBarGeometry(mode: currentLayout.mode)

    // Volume view
    fragVolumeView.identifier = .init("fragVolumeView")
    fragVolumeView.translatesAutoresizingMaskIntoConstraints = false
    fragVolumeView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

    // Mute button
    muteButton.identifier = .init("muteButton")
    let volImage = Images.volume3
    muteButton.image = volImage
    muteButton.target = self
    muteButton.action = #selector(muteButtonAction(_:))
    muteButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular, scale: .large)
    fragVolumeView.addSubview(muteButton)
    muteButton.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
    muteButton.centerYAnchor.constraint(equalTo: fragVolumeView.centerYAnchor).isActive = true
    volumeIconHeightConstraint = muteButton.heightAnchor.constraint(equalToConstant: oscGeo.volumeIconHeight)
    volumeIconHeightConstraint.priority = .init(900)
    volumeIconHeightConstraint.isActive = true
    volumeIconWidthConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: volImage.aspect)
    volumeIconWidthConstraint.priority = .init(900)
    volumeIconWidthConstraint.isActive = true

    // Volume slider
    fragVolumeView.addSubview(volumeSlider)
    volumeSlider.cell = VolumeSliderCell()
    volumeSlider.identifier = .init("volumeSlider")
    volumeSlider.controlSize = .regular
    volumeSlider.translatesAutoresizingMaskIntoConstraints = false
    let volumeSliderWidthConstraint = volumeSlider.widthAnchor.constraint(equalToConstant: oscGeo.volumeSliderWidth)
    volumeSliderWidthConstraint.identifier = .init("volumeSliderWidthConstraint")
    volumeSliderWidthConstraint.priority = .init(900)
    volumeSliderWidthConstraint.isActive = true
    volumeSlider.centerYAnchor.constraint(equalTo: muteButton.centerYAnchor).isActive = true
    volumeSlider.leadingAnchor.constraint(equalTo: muteButton.trailingAnchor, constant: 4).isActive = true
    volumeSlider.superview!.trailingAnchor.constraint(equalTo: volumeSlider.trailingAnchor, constant: 6).isActive = true
    volumeSlider.target = self
    volumeSlider.action = #selector(volumeSliderAction(_:))
  }

  private func initAlbumArtView() {
    defaultAlbumArtView.identifier = .init("defaultAlbumArtView")
    defaultAlbumArtView.wantsLayer = true
    defaultAlbumArtView.layer?.contents = #imageLiteral(resourceName: "default-album-art")
    defaultAlbumArtView.isHidden = true
    viewportView.addSubview(defaultAlbumArtView)

    defaultAlbumArtView.translatesAutoresizingMaskIntoConstraints = false

    // Add 1:1 aspect ratio constraint
    let aspectConstraint = defaultAlbumArtView.widthAnchor.constraint(equalTo: defaultAlbumArtView.heightAnchor, multiplier: 1)
    aspectConstraint.priority = .defaultHigh
    aspectConstraint.isActive = true
    // Always fill superview
    let widthGE = defaultAlbumArtView.widthAnchor.constraint(greaterThanOrEqualTo: viewportView.widthAnchor)
    widthGE.priority = .defaultHigh
    widthGE.isActive = true
    let heightGE = defaultAlbumArtView.heightAnchor.constraint(greaterThanOrEqualTo: viewportView.heightAnchor)
    heightGE.priority = .defaultHigh
    heightGE.isActive = true
    let widthEq = defaultAlbumArtView.widthAnchor.constraint(equalTo: viewportView.widthAnchor)
    widthEq.priority = .defaultLow
    widthEq.isActive = true
    let heightEq = defaultAlbumArtView.heightAnchor.constraint(equalTo: viewportView.heightAnchor)
    heightEq.priority = .defaultLow
    heightEq.isActive = true
    // Center in superview
    defaultAlbumArtView.centerXAnchor.constraint(equalTo: viewportView.centerXAnchor).isActive = true
    defaultAlbumArtView.centerYAnchor.constraint(equalTo: viewportView.centerYAnchor).isActive = true
  }

}
