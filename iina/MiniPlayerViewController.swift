//
//  MiniPlayerViewController.swift
//  iina
//
//  Created by lhc on 30/7/2017.
//  Copyright © 2017 lhc. All rights reserved.
//

import Cocoa

class MiniPlayerViewController: NSViewController, NSPopoverDelegate {

  override var nibName: NSNib.Name {
    return NSNib.Name("MiniPlayerViewController")
  }

  @objc let monospacedFont: NSFont = {
    let fontSize = NSFont.systemFontSize(for: .mini)
    return NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
  }()

  @IBOutlet weak var volumeSlider: ScrollableSlider!
  @IBOutlet weak var muteButton: NSButton!
  
  @IBOutlet weak var playbackBtnsWrapperView: NSView!
  @IBOutlet weak var positionSliderWrapperView: NSView!

  @IBOutlet weak var volumeButton: SymButton!
  @IBOutlet var volumePopover: NSPopover!
  @IBOutlet weak var volumeSliderView: NSView!
  @IBOutlet weak var volumePopoverAlignmentView: NSView!
  @IBOutlet weak var musicModeControlBarView: NSVisualEffectView!
  @IBOutlet weak var playlistWrapperView: NSVisualEffectView!
  @IBOutlet weak var mediaInfoView: NSView!
  @IBOutlet weak var controllerButtonsPanelView: NSView!
  @IBOutlet weak var titleLabel: ScrollingTextField!
  @IBOutlet weak var titleLabelTopConstraint: NSLayoutConstraint!
  @IBOutlet weak var artistAlbumLabel: ScrollingTextField!
  @IBOutlet weak var volumeLabel: NSTextField!
  @IBOutlet weak var togglePlaylistButton: SymButton!
  @IBOutlet weak var toggleAlbumArtButton: SymButton!
  @IBOutlet weak var volumeButtonLeadingConstraint: NSLayoutConstraint!

  private var hideVolumePopoverTimer: Timer?

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
    windowController.musicModeGeo.isPlaylistVisible
  }

  var isVideoVisible: Bool {
    return windowController.musicModeGeo.isVideoVisible
  }

  static var maxWindowWidth: CGFloat {
    return CGFloat(Preference.float(for: .musicModeMaxWidth))
  }

  var currentDisplayedPlaylistHeight: CGFloat {
    // most reliable first-hand source for this is a constraint:
    let bottomBarHeight = -windowController.viewportBtmOffsetFromBtmOfBottomBarConstraint.constant
    return bottomBarHeight - Constants.Distance.MusicMode.oscHeight
  }

  // MARK: - Initialization

  override func viewDidLoad() {
    super.viewDidLoad()

    /// `musicModeControlBarView` is always the same height
    musicModeControlBarView.heightAnchor.constraint(equalToConstant: Constants.Distance.MusicMode.oscHeight).isActive = true
    musicModeControlBarView.identifier = .init("MusicModeControlBarView")

    // Clip scrolling text at the margins so it doesn't touch the sides of the window
    mediaInfoView.clipsToBounds = true

    /// Set up tracking area to show controller when hovering over it
    windowController.viewportView.addTrackingArea(NSTrackingArea(rect: windowController.viewportView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))
    musicModeControlBarView.addTrackingArea(NSTrackingArea(rect: musicModeControlBarView.bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self, userInfo: nil))

    // close button
    windowController.closeButtonVE.action = #selector(windowController.close)
    windowController.closeButtonBox.action = #selector(windowController.close)
    windowController.closeButtonBackgroundViewVE.roundCorners()

    // hide controls initially
    controllerButtonsPanelView.alphaValue = 0
    controllerButtonsPanelView.identifier = .init("ControllerButtonsPanelView")
    mediaInfoView.identifier = .init("MediaInfoView")

    // tool tips
    togglePlaylistButton.identifier = .init("TogglePlaylistButton")
    togglePlaylistButton.toolTip = Preference.ToolBarButton.playlist.description()
    togglePlaylistButton.image = Preference.ToolBarButton.playlist.image()
    togglePlaylistButton.bounceOnClick = true

    toggleAlbumArtButton.identifier = .init("ToggleAlbumArtButton")
    toggleAlbumArtButton.toolTip = NSLocalizedString("mini_player.album_art", comment: "album_art")
    toggleAlbumArtButton.image = Images.toggleAlbumArt
    toggleAlbumArtButton.bounceOnClick = true

    volumeButton.toolTip = NSLocalizedString("mini_player.volume", comment: "volume")
    volumeButton.identifier = .init("VolumeButton")
    volumeButton.bounceOnClick = true
    windowController.closeButtonVE.toolTip = NSLocalizedString("mini_player.close", comment: "close")
    windowController.backButtonVE.toolTip = NSLocalizedString("mini_player.back", comment: "back")

    playlistWrapperView.identifier = .init("PlaylistWrapperView")

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
    windowController.animationPipeline.submitTask(duration: IINAAnimation.MusicModeShowButtonsDuration, { [self] in
      windowController.osdLeadingToMiniPlayerButtonsTrailingConstraint.priority = .required
      windowController.closeButtonView.isHidden = false
      windowController.closeButtonView.animator().alphaValue = 1
      controllerButtonsPanelView.animator().alphaValue = 1
      mediaInfoView.animator().alphaValue = 0
    })
  }

  /// Hides media info, shows OSC controls (runs as async task in animationPipeline)
  private func hideControllerButtonsInPipeline() {
    guard windowController.isInMiniPlayer else { return }
    windowController.animationPipeline.submitTask(duration: IINAAnimation.MusicModeShowButtonsDuration, { [self] in
      hideControllerButtons()
    })
  }

  /// Hides media info, shows OSC controls (synchronous version)
  func hideControllerButtons() {
    windowController.osdLeadingToMiniPlayerButtonsTrailingConstraint.priority = .defaultLow

    windowController.closeButtonView.animator().alphaValue = 0
    controllerButtonsPanelView.animator().alphaValue = 0
    mediaInfoView.animator().alphaValue = 1
  }

  // MARK: - UI: Media Info

  func stepScrollingLabels() {
    windowController.animationPipeline.submitInstantTask { [self] in
      loadIfNeeded()
      // FIXME: update based on TIME, not # of function calls!
      titleLabel.stepNext()
      artistAlbumLabel.stepNext()
    }
  }

  func resetScrollingLabels() {
    windowController.animationPipeline.submitInstantTask { [self] in
      loadIfNeeded()
      titleLabel.reset()
      artistAlbumLabel.reset()
    }
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

  /// Executed when `hideVolumePopoverTimer` fires.
  @objc private func hideVolumePopover() {
    volumePopover.animates = true
    volumePopover.performClose(self)
  }

  /// From `NSPopoverDelegate`: close volume popover
  func popoverWillClose(_ notification: Notification) {
    if NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) != window!.windowNumber {
      hideControllerButtonsInPipeline()
    }
  }

  /// From `NSPopoverDelegate`: open volume popover
  func showVolumePopover() {
    hideVolumePopoverTimer?.invalidate()

    // if it's a mouse, simply show popover then hide after a while when user stops scrolling
    if !volumePopover.isShown {
      volumePopover.animates = false
      volumePopover.show(relativeTo: volumePopoverAlignmentView.bounds, of: volumePopoverAlignmentView,
                         preferredEdge: .minY)
    }

    let timeout = Preference.double(for: .osdAutoHideTimeout)
    hideVolumePopoverTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self,
                                                  selector: #selector(self.hideVolumePopover), userInfo: nil, repeats: false)
  }

  // MARK: - IBActions

  @IBAction func volumeBtnAction(_ sender: NSButton) {
    if volumePopover.isShown {
      volumePopover.performClose(self)
    } else {
      windowController.updateVolumeUI()
      volumePopover.show(relativeTo: volumePopoverAlignmentView.bounds, of: volumePopoverAlignmentView,
                         preferredEdge: .minY)
    }
  }

  /// Action: Show/Hide playlist
  @IBAction func togglePlaylist(_ sender: Any) {
    windowController.animationPipeline.submitInstantTask({ [self] in
      let showPlaylist = !isPlaylistVisible
      log.verbose("Toggling playlist visibility from \((!showPlaylist).yn) to \(showPlaylist.yn)")
      let currentDisplayedPlaylistHeight = currentDisplayedPlaylistHeight

      let currentMusicModeGeo = windowController.musicModeGeoForCurrentFrame()
      var newWindowFrame = currentMusicModeGeo.windowFrame

      if showPlaylist {
        // Try to show playlist using stored height
        let desiredPlaylistHeight = CGFloat(Preference.integer(for: .musicModePlaylistHeight))
        // The window may be in the middle of a previous toggle, so we can't just assume window's current frame
        // represents a state where the playlist is fully shown or fully hidden. Instead, start by computing the height
        // we want to set, and then figure out the changes needed to the window's existing frame.
        let targetHeightToAdd = desiredPlaylistHeight - currentDisplayedPlaylistHeight
        // Fill up screen if needed
        newWindowFrame.size.height += targetHeightToAdd
      } else {
        // Hiding playlist
        let playlistHeightRounded = Int(round(currentDisplayedPlaylistHeight))
        if playlistHeightRounded >= Int(Constants.Distance.MusicMode.minPlaylistHeight) {
          log.verbose{"Saving playlist height: \(playlistHeightRounded)"}
          Preference.set(playlistHeightRounded, for: .musicModePlaylistHeight)
        }

        // If video is also hidden, do not try to shrink smaller than the control view, which would cause
        // a constraint violation. This is possible due to small imprecisions in various layout calculations.
        newWindowFrame.size.height = max(Constants.Distance.MusicMode.oscHeight, newWindowFrame.size.height - currentDisplayedPlaylistHeight)
      }

      let heightDifference = newWindowFrame.height - currentMusicModeGeo.windowFrame.height
      // adjust window origin to expand downwards
      newWindowFrame.origin.y = newWindowFrame.origin.y - heightDifference

      // Constrain window so that it doesn't expand below bottom of screen, or fall offscreen
      let newMusicModeGeometry = currentMusicModeGeo.clone(windowFrame: newWindowFrame, isPlaylistVisible: showPlaylist)
      windowController.buildApplyMusicModeGeoTasks(from: currentMusicModeGeo, to: newMusicModeGeometry, thenRun: true)
    })
  }

  /// Action: Show/Hide `videoView`
  @IBAction func toggleVideoViewVisibleState(_ sender: Any) {
    windowController.animationPipeline.submitInstantTask({ [self] in
      let showVideoView = !isVideoVisible
      log.verbose("MusicMode: user clicked video toggle btn. Changing videoView visibility: \((!showVideoView).yn) → \(showVideoView.yn)")

      if showVideoView {
        /// If showing video, call `setVideoTrackEnabled()`, then do animations, for a nicer effect.
        player.setVideoTrackEnabled(thenShowMiniPlayerVideo: true)
      } else {
        /// If hiding video, do animations first, then call `setVideoTrackDisabled()` (via `applyMusicModeGeo`).
        // TODO: develop a nicer sliding animation if possible. Will need a lot of changes to constraints :/
        windowController.applyVideoGeoTransform("HideVideoView",
                                                video: GeometryTransform.trackChanged,
                                                musicMode: { [self] ctx in
          let oldGeo = ctx.oldGeo.musicMode
          let newGeo = oldGeo.withVideoViewVisible(false)
          log.verbose{"MusicMode: changing videoView visibility: \(oldGeo.isVideoVisible.yesno) → NO, H=\(newGeo.videoHeight)"}
          return newGeo
        })
      }
    })
  }

  // MARK: - Window size & layout

  /// `windowWillResize`, but specfically applied to window while in music mode
  func musicModeWindowWillResize(_ window: NSWindow, to requestedSize: NSSize, isLiveResizingWidth: Bool) -> NSSize {
    resetScrollingLabels()
    let currentGeo = windowController.musicModeGeoForCurrentFrame()
    var newGeo: MusicModeGeometry

    if window.inLiveResize, currentGeo.isVideoVisible && !currentGeo.isPlaylistVisible {
      // Special case when scaling only video: need to treat similar to windowed mode
      let nonViewportAreaSize = currentGeo.windowFrame.size - currentGeo.viewportSize!
      let requestedViewportSize = requestedSize - nonViewportAreaSize

      let scaledViewportSize: NSSize
      if isLiveResizingWidth {
        // Option A: resize height based on requested width
        scaledViewportSize = NSSize(width: requestedViewportSize.width,
                                    height: round(requestedViewportSize.width / currentGeo.video.videoAspectCAR))
      } else {
        // Option B: resize width based on requested height
        scaledViewportSize = NSSize(width: round(requestedViewportSize.height * currentGeo.video.videoAspectCAR),
                                    height: requestedViewportSize.height)
      }
      newGeo = currentGeo.scalingViewport(to: scaledViewportSize)!

    } else {
      // general case
      /// Adjust to satisfy min & max width (height will be constrained in `init` when it is called by `clone`).
      /// Do not just return current windowFrame. While that will work smoother with BetterTouchTool (et al),
      /// it will cause the window to get "hung up" at arbitrary sizes instead of exact min or max, which is annoying.
      var requestedSize = NSSize(width: requestedSize.width.rounded(), height: requestedSize.height.rounded())
      if requestedSize.width < Constants.Distance.MusicMode.minWindowWidth {
        log.verbose{"WindowWillResize: constraining to min width \(Constants.Distance.MusicMode.minWindowWidth)"}
        requestedSize = NSSize(width: Constants.Distance.MusicMode.minWindowWidth, height: requestedSize.height)
      } else if requestedSize.width > MiniPlayerViewController.maxWindowWidth {
        log.verbose{"WindowWillResize: constraining to max width \(MiniPlayerViewController.maxWindowWidth)"}
        requestedSize = NSSize(width: MiniPlayerViewController.maxWindowWidth, height: requestedSize.height)
      }

      let requestedWindowFrame = NSRect(origin: window.frame.origin, size: requestedSize)
      newGeo = currentGeo.clone(windowFrame: requestedWindowFrame, screenID: windowController.bestScreen.screenID)
    }

    /// This call is needed to update any necessary constraints & resize internal views
    newGeo = windowController.applyMusicModeGeo(newGeo, setFrame: false, updateCache: false)
    return newGeo.windowFrame.size
  }

  func updateVideoViewHeightConstraint(isVideoVisible: Bool) {
    log.verbose{"Updating viewportViewHeightContraint using visible=\(isVideoVisible.yn)"}

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
        heightConstraint.identifier = .init("viewportViewHeightContraint")
        heightConstraint.isActive = true
        windowController.viewportViewHeightContraint = heightConstraint
      }
    }
  }

  static func buildMusicModeGeometryFromPrefs(screen: NSScreen, video: VideoGeometry) -> MusicModeGeometry {
    // Default to left-top of screen. Try to use last-saved playlist height and visibility settings.
    let isPlaylistVisible = Preference.bool(for: .musicModeShowPlaylist)
    let isVideoVisible = Preference.bool(for: .musicModeShowAlbumArt)
    let desiredPlaylistHeight = CGFloat(Preference.float(for: .musicModePlaylistHeight))
    let desiredWindowWidth = Constants.Distance.MusicMode.defaultWindowWidth
    let desiredVideoHeight = isVideoVisible ? round(desiredWindowWidth / video.videoAspectCAR) : 0
    let desiredWindowHeight = desiredVideoHeight + Constants.Distance.MusicMode.oscHeight + (isPlaylistVisible ? desiredPlaylistHeight : 0)

    let screenFrame = screen.visibleFrame
    let windowSize = NSSize(width: desiredWindowWidth, height: desiredWindowHeight)
    let windowOrigin = NSPoint(x: screenFrame.origin.x, y: screenFrame.maxY - windowSize.height)
    let windowFrame = NSRect(origin: windowOrigin, size: windowSize)
    let desiredGeo = MusicModeGeometry(windowFrame: windowFrame, screenID: screen.screenID, video: video,
                                       isVideoVisible: isVideoVisible, isPlaylistVisible: isPlaylistVisible)
    // Resize as needed to fit on screen:
    return desiredGeo.refitted()
  }
}
