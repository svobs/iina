//
//  MiniPlayerController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class MiniPlayerController: NSViewController, NSPopoverDelegate {

  override var nibName: NSNib.Name {
    return NSNib.Name("MiniPlayerController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .mini)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  @IBOutlet weak var volumeSlider: NSSlider!
  @IBOutlet weak var muteButton: NSButton!
  @IBOutlet weak var playButton: NSButton!
  @IBOutlet weak var leftArrowButton: NSButton!
  @IBOutlet weak var rightArrowButton: NSButton!

  @IBOutlet weak var positionSliderWrapperView: NSView!

  @IBOutlet weak var volumeButton: NSButton!
  @IBOutlet var volumePopover: NSPopover!
  @IBOutlet weak var volumeSliderView: NSView!
  @IBOutlet weak var musicModeControlBarView: NSVisualEffectView!
  @IBOutlet weak var playlistWrapperView: NSVisualEffectView!
  @IBOutlet weak var mediaInfoView: NSView!
  @IBOutlet weak var controllerButtonsPanelView: NSView!
  @IBOutlet weak var titleLabel: ScrollingTextField!
  @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var artistAlbumLabel: ScrollingTextField!
  @IBOutlet weak var volumeLabel: NSTextField!
  @IBOutlet weak var togglePlaylistButton: NSButton!
  @IBOutlet weak var toggleAlbumArtButton: NSButton!
  @IBOutlet weak var leftArrowToPlayButtonSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var playButtonToRightArrowSpaceConstraint: NSLayoutConstraint!
  @IBOutlet weak var volumeButtonLeadingConstraint: NSLayoutConstraint!

  unowned var windowController: PlayerWindowController!
  var player: PlayerCore {
    return windowController.player
  }

  var window: NSWindow? {
    return windowController.window
  }

  var log: Logger.Subsystem {
    return windowController.log
  }

  var isPlaylistVisible: Bool {
    get {
      windowController.musicModeGeo.isPlaylistVisible
    }
  }

  var isVideoVisible: Bool {
    get {
      return windowController.musicModeGeo.isVideoVisible
    }
  }

  static var maxWindowWidth: CGFloat {
    return CGFloat(Preference.float(for: .musicModeMaxWidth))
  }

  lazy var hideVolumePopover: DispatchWorkItem = {
    DispatchWorkItem {
      self.volumePopover.animates = true
      self.volumePopover.performClose(self)
    }
  }()

  var currentDisplayedPlaylistHeight: CGFloat {
    // most reliable first-hand source for this is a constraint:
    let bottomBarHeight = -windowController.viewportBottomOffsetFromBottomBarBottomConstraint.constant
    return bottomBarHeight - Constants.Distance.MusicMode.oscHeight
  }

  // MARK: - Initialization

  override func viewDidLoad() {
    super.viewDidLoad()

    /// `musicModeControlBarView` is always the same height
    musicModeControlBarView.heightAnchor.constraint(equalToConstant: Constants.Distance.MusicMode.oscHeight).isActive = true

    // Clip scrolling text at the margins so it doesn't touch the sides of the window
    mediaInfoView.clipsToBounds = true

    /// Set up tracking area to show controller when hovering over it
    windowController.viewportView.addTrackingArea(NSTrackingArea(rect: windowController.viewportView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))
    musicModeControlBarView.addTrackingArea(NSTrackingArea(rect: musicModeControlBarView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    // close button
    windowController.closeButtonVE.action = #selector(windowController.close)
    windowController.closeButtonBox.action = #selector(windowController.close)
    windowController.closeButtonBackgroundViewVE.roundCorners(withRadius: 8)

    // hide controls initially
    controllerButtonsPanelView.alphaValue = 0

    // tool tips
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.description()
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    volumeButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")
    windowController.closeButtonVE.toolTip = NSLocalizedString("mini_player.close", comment: "close")
    windowController.backButtonVE.toolTip = NSLocalizedString("mini_player.back", comment: "back")

    volumePopover.delegate = self

    log.verbose("MiniPlayer viewDidLoad done")
  }

  // MARK: - UI: Controller

  /// Shows Controller on hover
  override func mouseEntered(with event: NSEvent) {
    guard player.isInMiniPlayer else { return }
    showControl()
  }

  /// Hides Controller when hover leaves controller area
  override func mouseExited(with event: NSEvent) {
    guard player.isInMiniPlayer else { return }

    /// The goal is to always show the control when the cursor is hovering over either of the 2 tracking areas.
    /// Although they are adjacent to each other, `mouseExited` can still be called when moving from one to the other.
    /// Detect and ignore this case.
    guard !windowController.isMouseEvent(event, inAnyOf: [musicModeControlBarView, windowController.viewportView]) else {
      return
    }

    hideControllerButtonsInPipeline()
  }

  // Shows OSC controls, hides media info
  private func showControl() {
    windowController.animationPipeline.submit(IINAAnimation.Task(duration: IINAAnimation.MusicModeShowButtonsDuration, { [self] in
      windowController.osdLeadingToMiniPlayerButtonsTrailingConstraint.priority = .required
      windowController.closeButtonView.isHidden = false
      windowController.closeButtonView.animator().alphaValue = 1
      controllerButtonsPanelView.animator().alphaValue = 1
      mediaInfoView.animator().alphaValue = 0
    }))
  }

  /// Hides media info, shows OSC controls (runs as async task in animationPipeline)
  private func hideControllerButtonsInPipeline() {
    guard windowController.isInMiniPlayer else { return }
    windowController.animationPipeline.submit(IINAAnimation.Task(duration: IINAAnimation.MusicModeShowButtonsDuration, { [self] in
      hideControllerButtons()
    }))
  }

  /// Hides media info, shows OSC controls (synchronous version)
  private func hideControllerButtons() {
    windowController.osdLeadingToMiniPlayerButtonsTrailingConstraint.priority = .defaultLow

    windowController.closeButtonView.animator().alphaValue = 0
    controllerButtonsPanelView.animator().alphaValue = 0
    mediaInfoView.animator().alphaValue = 1
  }

  // MARK: - UI: Media Info

  func updateScrollingLabels() {
    loadIfNeeded()
    titleLabel.stepNext()
    artistAlbumLabel.stepNext()
  }

  func resetScrollingLabels() {
    loadIfNeeded()
    titleLabel.reset()
    artistAlbumLabel.reset()
  }

  func updateTitle(mediaTitle: String, mediaAlbum: String, mediaArtist: String) {
    titleLabel.stringValue = mediaTitle
    // hide artist & album label when info not available
    if mediaArtist.isEmpty && mediaAlbum.isEmpty {
      titleLabelTopConstraint.constant = 6 + 10
      artistAlbumLabel.stringValue = ""
    } else {
      titleLabelTopConstraint.constant = 6
      if mediaArtist.isEmpty || mediaAlbum.isEmpty {
        artistAlbumLabel.stringValue = "\(mediaArtist)\(mediaAlbum)"
      } else {
        artistAlbumLabel.stringValue = "\(mediaArtist) - \(mediaAlbum)"
      }
    }
  }

  // MARK: - Volume UI

  func updateVolumeUI(volume: Double, isMuted: Bool, hasAudio: Bool) {
    volumeSlider.isEnabled = hasAudio
    volumeSlider.doubleValue = volume
    volumeLabel.intValue = Int32(volume)
    if isMuted {
      volumeButton.image = NSImage(named: "mute")
    } else {
      switch volumeLabel.intValue {
      case 0:
        volumeButton.image = NSImage(named: "volume-0")
      case 1...33:
        volumeButton.image = NSImage(named: "volume-1")
      case 34...66:
        volumeButton.image = NSImage(named: "volume-2")
      case 67...1000:
        volumeButton.image = NSImage(named: "volume")
      default:
        break
      }
    }
  }

  /// From `NSPopoverDelegate`: close volume popover
  func popoverWillClose(_ notification: Notification) {
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControllerButtonsInPipeline()
    }
  }

  /// From `NSPopoverDelegate`: open volume popover
  func handleVolumePopover(_ isTrackpadBegan: Bool, _ isTrackpadEnd: Bool, _ isMouse: Bool) {
    hideVolumePopover.cancel()
    hideVolumePopover = DispatchWorkItem {
      self.volumePopover.animates = true
      self.volumePopover.performClose(self)
    }
    if isTrackpadBegan {
       // enabling animation here causes user not seeing their volume changes during popover transition
       volumePopover.animates = false
       volumePopover.show(relativeTo: volumeButton.bounds, of: volumeButton, preferredEdge: .minY)
     } else if isTrackpadEnd {
       DispatchQueue.main.asyncAfter(deadline: .now(), execute: hideVolumePopover)
     } else if isMouse {
       // if it's a mouse, simply show popover then hide after a while when user stops scrolling
       if !volumePopover.isShown {
         volumePopover.animates = false
         volumePopover.show(relativeTo: volumeButton.bounds, of: volumeButton, preferredEdge: .minY)
       }
       let timeout = Preference.double(for: .osdAutoHideTimeout)
       DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: hideVolumePopover)
     }
  }

  // MARK: - IBActions

  @IBAction func volumeBtnAction(_ sender: NSButton) {
    if volumePopover.isShown {
      volumePopover.performClose(self)
    } else {
      windowController.updateVolumeUI()
      volumePopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
  }

  @IBAction func togglePlaylist(_ sender: Any) {
    windowController.animationPipeline.submitZeroDuration({ [self] in
      _togglePlaylist()
    })
  }

  private func _togglePlaylist() {
    guard let window = windowController.window else { return }
    let showPlaylist = !isPlaylistVisible
    log.verbose("Toggling playlist visibility from \((!showPlaylist).yn) to \(showPlaylist.yn)")
    let currentDisplayedPlaylistHeight = currentDisplayedPlaylistHeight
    var newWindowFrame = window.frame
    var newScreenID = windowController.bestScreen.screenID

    if showPlaylist {
      // Try to show playlist using stored height
      let desiredPlaylistHeight = CGFloat(Preference.integer(for: .musicModePlaylistHeight))
      // The window may be in the middle of a previous toggle, so we can't just assume window's current frame
      // represents a state where the playlist is fully shown or fully hidden. Instead, start by computing the height
      // we want to set, and then figure out the changes needed to the window's existing frame.
      let targetHeightToAdd = desiredPlaylistHeight - currentDisplayedPlaylistHeight
      // Fill up screen if needed
      newWindowFrame.size.height += targetHeightToAdd
    } else { // hide playlist
      // Save playlist height first
      saveCurrentPlaylistHeightToPrefs()

      // If video is also hidden, do not try to shrink smaller than the control view, which would cause
      // a constraint violation. This is possible due to small imprecisions in various layout calculations.
      newWindowFrame.size.height = max(Constants.Distance.MusicMode.oscHeight, newWindowFrame.size.height - currentDisplayedPlaylistHeight)
    }

    let heightDifference = newWindowFrame.height - window.frame.height
    // adjust window origin to expand downwards
    newWindowFrame.origin.y = newWindowFrame.origin.y - heightDifference

    // Constrain window so that it doesn't expand below bottom of screen, or fall offscreen
    let newMusicModeGeometry = windowController.musicModeGeo.clone(windowFrame: newWindowFrame, screenID: newScreenID, isPlaylistVisible: showPlaylist)
    windowController.applyMusicModeGeoInAnimationPipeline(newMusicModeGeometry)
  }

  @IBAction func toggleVideoView(_ sender: Any) {
    windowController.animationPipeline.submitZeroDuration({ [self] in
      let showVideo = !isVideoVisible
      log.verbose("Toggling videoView visibility from \((!showVideo).yn) to \(showVideo.yn)")

      /// If showing video, call `setVideoTrackEnabled(true)`, then do animations.
      if showVideo {
        player.setVideoTrackEnabled(true, showMiniPlayerVideo: true)
      } else {
        /// If hiding video, do animations first, then call `setVideoTrackEnabled(false)`.
        applyVideoVisibility(to: false)
      }
    })
  }

  func showVideo() {
    applyVideoVisibility(to: true)
  }

  // TODO: develop a nice sliding animation if possible
  private func applyVideoVisibility(to showVideo: Bool) {
    guard let window else { return }
    log.verbose("Applying videoView visibility: \((!showVideo).yn) to \(showVideo.yn)")
    var tasks: [IINAAnimation.Task] = []
    tasks.append(IINAAnimation.zeroDurationTask{ [self] in
      // Hide OSD during animation
      windowController.hideOSD(immediately: true)

      /// Temporarily hide window buttons. Using `isHidden` will conveniently override its alpha value
      windowController.closeButtonView.isHidden = true

      windowController.thumbnailPeekView.isHidden = true

      /// If needing to reactivate this constraint, do it before the toggle animation, so that window doesn't jump.
      /// (See note in `applyMusicModeGeo` for why this constraint needed to be disabled in the first place)
      if showVideo {
        windowController.viewportBottomOffsetFromContentViewBottomConstraint.isActive = true
      }
    })

    tasks.append(IINAAnimation.Task(timing: .easeInEaseOut, { [self] in
      var screenID = windowController.bestScreen.screenID
      let newGeometry = windowController.musicModeGeo.clone(windowFrame: window.frame, screenID: screenID).withVideoViewVisible(showVideo)
      log.verbose("VideoView setting videoViewVisible=\(showVideo), videoHeight=\(newGeometry.videoHeight)")
      windowController.applyMusicModeGeo(newGeometry)
    }))

    tasks.append(IINAAnimation.Task{ [self] in
      // Swap window buttons
      windowController.updateMusicModeButtonsVisibility()

      /// Allow it to show again
      windowController.closeButtonView.isHidden = false
      windowController.videoView.display()

      if !showVideo {
        player.setVideoTrackEnabled(false)
      }
    })

    windowController.animationPipeline.submit(tasks)
  }

  // MARK: - Window size & layout

  /// `windowWillResize`, but specfically applied to window when in music mode
  func resizeWindow(_ window: NSWindow, to requestedSize: NSSize) -> NSSize {
    resetScrollingLabels()

    if requestedSize.width < Constants.Distance.MusicMode.minWindowWidth {
      // Responding with the current size seems to work much better with certain window management tools
      // (e.g. BetterTouchTool's window snapping) than trying to respond with the min size,
      // which seems to result in the window manager retrying with different sizes, which results in flickering.
      log.verbose("WindowWillResize: requestedSize smaller than min \(Constants.Distance.MusicMode.minWindowWidth); returning existing size")
      return window.frame.size
    } else if requestedSize.width > MiniPlayerController.maxWindowWidth {
      log.verbose("WindowWillResize: requestedSize larger than max \(MiniPlayerController.maxWindowWidth); returning existing size")
      return window.frame.size
    }

    let currentGeo = windowController.musicModeGeo
    let requestedWindowFrame = NSRect(origin: window.frame.origin, size: requestedSize)
    var newGeometry = currentGeo.clone(windowFrame: requestedWindowFrame, screenID: windowController.bestScreen.screenID).refit()
    IINAAnimation.disableAnimation {
      /// This will set `windowController.musicModeGeo` after applying any necessary constraints
      newGeometry = windowController.applyMusicModeGeo(newGeometry, setFrame: false, animate: false, updateCache: false)
    }

    return newGeometry.windowFrame.size
  }

  func windowDidResize() {
    loadIfNeeded()
    resetScrollingLabels()
    // Do not save musicModeGeo here! Pinch gesture will handle itself. Drag-to-resize will be handled below.
  }

  func saveCurrentPlaylistHeightToPrefs() {
    guard isPlaylistVisible else { return }

    let playlistHeight = round(currentDisplayedPlaylistHeight)
    guard playlistHeight >= Constants.Distance.MusicMode.minPlaylistHeight else { return }

    // save playlist height
    log.verbose("Saving playlist height: \(playlistHeight)")
    Preference.set(Int(playlistHeight), for: .musicModePlaylistHeight)
  }

  func cleanUpForMusicModeExit() {
    log.verbose("Cleaning up for music mode exit")
    view.removeFromSuperview()

    /// Remove `playlistView` from wrapper. It will be added elsewhere if/when it is needed there
    windowController.playlistView.view.removeFromSuperview()

    /// Hide this until `showControl` is called again
    windowController.closeButtonView.isHidden = true

    // Make sure to restore video
    updateVideoViewVisibilityConstraints(isVideoVisible: true)
    windowController.viewportBottomOffsetFromContentViewBottomConstraint.isActive = true

    windowController.leftLabel.font = NSFont.messageFont(ofSize: 11)
    windowController.rightLabel.font = NSFont.messageFont(ofSize: 11)
    windowController.fragPositionSliderView.removeFromSuperview()

    // Make sure to reset constraints for OSD
    hideControllerButtons()
  }

  func updateVideoViewVisibilityConstraints(isVideoVisible: Bool) {
    log.verbose("Applying videoView visibility constraints, using visible=\(isVideoVisible.yn)")

    if isVideoVisible {
      // Remove zero-height constraint
      if let heightContraint = windowController.viewportViewHeightContraint {
        heightContraint.isActive = false
        windowController.viewportViewHeightContraint = nil
      }
    } else {
      // Add or reactivate zero-height constraint
      if let heightConstraint = windowController.viewportViewHeightContraint {
        heightConstraint.isActive = true
      } else {
        let heightConstraint = windowController.viewportView.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint.isActive = true
        windowController.viewportViewHeightContraint = heightConstraint
      }
    }
  }

  static func buildMusicModeGeometryFromPrefs(screen: NSScreen, videoAspect: CGFloat) -> MusicModeGeometry {
    // Default to left-top of screen. Try to use last-saved playlist height and visibility settings.
    let isPlaylistVisible = Preference.bool(for: .musicModeShowPlaylist)
    let isVideoVisible = Preference.bool(for: .musicModeShowAlbumArt)
    let desiredPlaylistHeight = CGFloat(Preference.float(for: .musicModePlaylistHeight))
    let desiredWindowWidth = Constants.Distance.MusicMode.defaultWindowWidth
    let desiredVideoHeight = isVideoVisible ? round(desiredWindowWidth / videoAspect) : 0
    let desiredWindowHeight = desiredVideoHeight + Constants.Distance.MusicMode.oscHeight + (isPlaylistVisible ? desiredPlaylistHeight : 0)

    let screenFrame = screen.visibleFrame
    let windowSize = NSSize(width: desiredWindowWidth, height: desiredWindowHeight)
    let windowOrigin = NSPoint(x: screenFrame.origin.x, y: screenFrame.maxY - windowSize.height)
    let windowFrame = NSRect(origin: windowOrigin, size: windowSize)
    let desiredGeo = MusicModeGeometry(windowFrame: windowFrame, screenID: screen.screenID, videoAspect: videoAspect,
                                       isVideoVisible: isVideoVisible, isPlaylistVisible: isPlaylistVisible)
    // Resize as needed to fit on screen:
    return desiredGeo.refit()
  }
}
