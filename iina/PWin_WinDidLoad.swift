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
    window.minSize = AppData.minVideoSize

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

    windowScrollWheel = PWinScrollWheel(self)

    playSliderScrollWheel.configure(playSlider, log)

    volumeSliderScrollWheel.configure(volumeSlider, log)

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

      // FIXME: stick to individual side of screen
      // FIXME: parent playlist

      // Top bar: other init
      topBarView.clipsToBounds = true
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

      // This is above the play slider and by default, will swallow clicks. Send events to play slider instead
      seekPreview.timeLabel.nextResponder = playSlider
      contentView.addSubview(seekPreview.timeLabel, positioned: .below, relativeTo: osdVisualEffectView)
      contentView.addSubview(seekPreview.thumbnailPeekView, positioned: .below, relativeTo: seekPreview.timeLabel)
      initTitleBarAccessories()
      initBottomBarView(in: contentView)
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

      if player.info.isRestoring {
        if let priorState = player.info.priorState, let layoutSpec = priorState.layoutSpec {
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

  private func initTitleBarAccessories() {
    let builder = CustomTitleBar.shared
    // - LEADING

    let leadingTB = leadingTitleBarAccessoryView
    leadingTB.idString = "leadingTitleBarAccessoryView"
    leadingTB.translatesAutoresizingMaskIntoConstraints = false

    leadingTB.heightAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true

    let leadingSpacerLeading = NSView()
    leadingSpacerLeading.identifier = .init("leadingTitleBarLeadingSpacer")
    leadingTitleBarLeadingSpaceConstraint = leadingSpacerLeading.widthAnchor.constraint(equalToConstant: 0)
    leadingTitleBarLeadingSpaceConstraint?.isActive = true

    leadingSidebarToggleButton = builder.makeTitleBarButton(Images.sidebarLeading,
                                                            identifier: "leadingSidebarToggleButton",
                                                            target: self,
                                                            action: #selector(toggleLeadingSidebarVisibility(_:)))
    leadingSidebarToggleButton.widthAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true

    let leadingSpacerTrailing = NSView()
    leadingSpacerTrailing.identifier = .init("leadingTitleBarTrailingSpacer")
    leadingTitleBarTrailingSpaceConstraint = leadingSpacerTrailing.widthAnchor.constraint(equalToConstant: 0)
    leadingTitleBarTrailingSpaceConstraint?.isActive = true

    leadingTB.orientation = .horizontal
    leadingTB.alignment = .centerY
    leadingTB.distribution = .fill
    leadingTB.spacing = 0
    leadingTB.detachesHiddenViews = true

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
    onTopButton.widthAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true

    trailingSidebarToggleButton = builder.makeTitleBarButton(Images.sidebarTrailing,
                                                             identifier: "trailingSidebarToggleButton",
                                                             target: self,
                                                             action: #selector(toggleTrailingSidebarVisibility(_:)))
    trailingSidebarToggleButton.widthAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true

    let trailingSpacerTrailing = NSView()
    trailingSpacerTrailing.identifier = .init("trailingTitleBarTrailingSpacer")
    trailingTitleBarTrailingSpaceConstraint = trailingSpacerTrailing.widthAnchor.constraint(equalToConstant: 0)
    trailingTitleBarTrailingSpaceConstraint?.isActive = true

    trailingTitleBarAccessoryView.heightAnchor.constraint(equalToConstant: PlayerWindowController.standardTitleBarHeight).isActive = true

    trailingTB.orientation = .horizontal
    trailingTB.alignment = .centerY
    trailingTB.distribution = .fill
    trailingTB.spacing = 0
    trailingTB.detachesHiddenViews = true

    trailingTB.addArrangedSubview(trailingSpacerLeading)
    trailingTB.addArrangedSubview(trailingSidebarToggleButton)
    trailingTB.addArrangedSubview(onTopButton)
    trailingTB.addArrangedSubview(trailingSpacerTrailing)

    // - Controllers

    addTitleBarAccessoryViews()
  }

  private func initBottomBarView(in contentView: NSView) {
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
    bottomBarTopBorder.fillColor = NSColor.titleBarBorder
    bottomBarTopBorder.translatesAutoresizingMaskIntoConstraints = false
    bottomBarView.addSubview(bottomBarTopBorder)
    bottomBarTopBorder.addConstraintsToFillSuperview(top: 0, leading: 0, trailing: 0)
    bottomBarTopBorder.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
    bottomBarTopBorder.borderColor = NSColor.clear
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
    playButton = NSButton(image: Images.play, target: self,
                          action: #selector(playButtonAction(_:)))
    playButton.identifier = .init("playButton")  // helps with debug logging
    playButton.isBordered = false
    playButton.bezelStyle = .regularSquare
    playButton.imagePosition = .imageOnly
    playButton.refusesFirstResponder = true
    playButton.imageScaling = .scaleProportionallyUpOrDown
    if #available(macOS 11.0, *) {
      /// The only reason for setting this is so that `replayImage`, when used, will be drawn in bold.
      /// This is ignored when using play & pause images (they are static assets).
      /// Looks like `pointSize` here is ignored. Not sure if `scale` is relevant either?
      let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold, scale: .small)
      playButton.symbolConfiguration = config
    }
    playButton.translatesAutoresizingMaskIntoConstraints = false
    playButton.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    playButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    let playIconSize = oscGeo.playIconSize
    playBtnWidthConstraint = playButton.widthAnchor.constraint(equalToConstant: playIconSize)
    playBtnWidthConstraint.identifier = .init("playBtnWidthConstraint")
    playBtnWidthConstraint.priority = .init(850)  // allow to shrink for animations or speedLabel
    playBtnWidthConstraint.isActive = true
    let playAspectConstraint = playButton.widthAnchor.constraint(equalTo: playButton.heightAnchor)
    playAspectConstraint.isActive = true

    let playButtonVStackView = ClickThroughStackView()
    playButtonVStackView.identifier = .init("playButtonVStackView")
    playButtonVStackView.orientation = .vertical
    playButtonVStackView.alignment = .centerX
    playButtonVStackView.detachesHiddenViews = true
    playButtonVStackView.layer?.backgroundColor = .clear
    playButtonVStackView.spacing = 0
    playButtonVStackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    playButtonVStackView.addView(speedLabel, in: .center)
    playButtonVStackView.addView(playButton, in: .center)
    playButtonVStackView.setHuggingPriority(.init(250), for: .vertical)
    playButtonVStackView.setHuggingPriority(.init(250), for: .horizontal)
    playButtonVStackView.translatesAutoresizingMaskIntoConstraints = false

    // Left Arrow button
    leftArrowButton = NSButton(image: oscGeo.leftArrowImage, target: self,
                               action: #selector(leftArrowButtonAction(_:)))
    leftArrowButton.identifier = .init("leftArrowButton")
    leftArrowButton.setButtonType(.multiLevelAccelerator)
    leftArrowButton.isBordered = false
    leftArrowButton.maxAcceleratorLevel = 5
    leftArrowButton.bezelStyle = .regularSquare
    leftArrowButton.imagePosition = .imageOnly
    leftArrowButton.refusesFirstResponder = true
    leftArrowButton.imageScaling = .scaleProportionallyUpOrDown
    leftArrowButton.translatesAutoresizingMaskIntoConstraints = false

    // Right Arrow button
    rightArrowButton = NSButton(image: oscGeo.rightArrowImage, target: self,
                                action: #selector(rightArrowButtonAction(_:)))
    rightArrowButton.identifier = .init("rightArrowButton")
    rightArrowButton.setButtonType(.multiLevelAccelerator)
    rightArrowButton.isBordered = false
    rightArrowButton.maxAcceleratorLevel = 5
    rightArrowButton.bezelStyle = .regularSquare
    rightArrowButton.imagePosition = .imageOnly
    rightArrowButton.refusesFirstResponder = true
    rightArrowButton.imageScaling = .scaleProportionallyUpOrDown
    rightArrowButton.translatesAutoresizingMaskIntoConstraints = false

    fragPlaybackBtnsView.identifier = .init("fragPlaybackBtnsView")
    fragPlaybackBtnsView.addSubview(leftArrowButton)
    fragPlaybackBtnsView.addSubview(playButtonVStackView)
    fragPlaybackBtnsView.addSubview(rightArrowButton)

    playButtonVStackView.heightAnchor.constraint(lessThanOrEqualTo: fragPlaybackBtnsView.heightAnchor).isActive = true

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

    let playBtnHorizOffsetConstraint = playButtonVStackView.centerXAnchor.constraint(equalTo: fragPlaybackBtnsView.centerXAnchor)
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
    let image = Images.volume3
    muteButton.image = image
    muteButton.target = self
    muteButton.action = #selector(muteButtonAction(_:))
    muteButton.setButtonType(.momentaryPushIn)
    muteButton.isBordered = false
    muteButton.maxAcceleratorLevel = 5
    muteButton.bezelStyle = .regularSquare
    muteButton.imagePosition = .imageOnly
    muteButton.refusesFirstResponder = true
    muteButton.imageScaling = .scaleProportionallyUpOrDown
    muteButton.translatesAutoresizingMaskIntoConstraints = false
    fragVolumeView.addSubview(muteButton)
    muteButton.addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0)
    muteButton.centerYAnchor.constraint(equalTo: fragVolumeView.centerYAnchor).isActive = true
    volumeIconHeightConstraint = muteButton.heightAnchor.constraint(equalToConstant: oscGeo.volumeIconHeight)
    volumeIconHeightConstraint.priority = .init(900)
    volumeIconHeightConstraint.isActive = true
    volumeIconWidthConstraint = muteButton.widthAnchor.constraint(equalTo: muteButton.heightAnchor, multiplier: image.aspect)
    volumeIconWidthConstraint.priority = .init(900)
    volumeIconWidthConstraint.isActive = true

    // Volume slider
    fragVolumeView.addSubview(volumeSlider)
    volumeSlider.cell = VolumeSliderCell()
    volumeSlider.identifier = .init("volumeSlider")
    volumeSlider.controlSize = .mini
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
