//
//  VideoView.swift
//  iina
//
//  Created by lhc on 8/7/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa


class VideoView: NSView {

  weak var player: PlayerCore!
  var link: CVDisplayLink?

  lazy var videoLayer: ViewLayer = {
    let layer = ViewLayer()
    layer.videoView = self
    return layer
  }()

  var videoSize: NSSize?

  var isUninited = false

  var draggingTimer: Timer?

  // whether auto show playlist is triggered
  var playlistShown: Bool = false

  // variable for tracing mouse position when dragging in the view
  var lastMousePosition: NSPoint?

  var hasPlayableFiles: Bool = false

  // cached indicator to prevent unnecessary updates of DisplayLink
  var currentDisplay: UInt32?

  var pendingRedrawsAfterEnteringPIP = 0;

  lazy var hdrSubsystem = Logger.Subsystem(rawValue: "hdr")

  // MARK: - Attributes

  override var mouseDownCanMoveWindow: Bool {
    return true
  }

  override var isOpaque: Bool {
    return true
  }

  // MARK: - Init

  override init(frame: CGRect) {
    super.init(frame: frame)

    // set up layer
    layer = videoLayer
    videoLayer.contentsScale = NSScreen.main!.backingScaleFactor
    wantsLayer = true

    // other settings
    autoresizingMask = [.width, .height]
    wantsBestResolutionOpenGLSurface = true
    wantsExtendedDynamicRangeOpenGLSurface = true

    // dragging init
    registerForDraggedTypes([.nsFilenames, .nsURL, .string])
  }

  convenience init(frame: CGRect, player: PlayerCore) {
    self.init(frame: frame)
    self.player = player
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func uninit() {
    player.mpv.lockAndSetOpenGLContext()
    defer { player.mpv.unlockOpenGLContext() }

    guard !isUninited else { return }

    player.mpv.mpvUninitRendering()
    isUninited = true
  }

  deinit {
    uninit()
  }

  override func layout() {
    super.layout()
    if pendingRedrawsAfterEnteringPIP != 0 && superview != nil {
      pendingRedrawsAfterEnteringPIP -= 1
      videoLayer.draw(forced: true)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    // do nothing
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  /// Workaround for issue #3211, Legacy fullscreen is broken (11.0.1)
  ///
  /// Changes in Big Sur broke the legacy full screen feature. The `MainWindowController` method `legacyAnimateToWindowed`
  /// had to be changed to get this feature working again. Under Big Sur that method now calls the AppKit method
  /// `window.styleMask.insert(.titled)`. This is a part of restoring the window's style mask to the way it was before entering
  /// full screen mode. A side effect of restoring the window's title is that AppKit stops calling `MainWindowController.mouseUp`.
  /// This appears to be a defect in the Cocoa framework. See the issue for details. As a workaround the mouse up event is caught in
  /// the view which then calls the window controller's method.
  override func mouseUp(with event: NSEvent) {
    // Only check for Big Sur or greater, not if the preference use legacy full screen is enabled as
    // that can be changed while running and once the window title has been removed and added back
    // AppKit malfunctions from then on. The check for running under Big Sur or later isn't really
    // needed as it would be fine to always call the controller. The check merely makes it clear
    // that this is only needed due to macOS changes starting with Big Sur.
    if #available(macOS 11, *) {
      player.mainWindow.mouseUp(with: event)
    } else {
      super.mouseUp(with: event)
    }
  }

  // MARK: Drag and drop

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    hasPlayableFiles = (player.acceptFromPasteboard(sender, isPlaylist: true) == .copy)
    return player.acceptFromPasteboard(sender)
  }

  @objc func showPlaylist() {
    player.mainWindow.menuShowPlaylistPanel(.dummy)
    playlistShown = true
  }

  private func createTimer() {
    draggingTimer = Timer.scheduledTimer(timeInterval: TimeInterval(0.3), target: self,
                                         selector: #selector(showPlaylist), userInfo: nil, repeats: false)
  }

  private func destroyTimer() {
    if let draggingTimer = draggingTimer {
      draggingTimer.invalidate()
    }
    draggingTimer = nil
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {

    guard !player.isInMiniPlayer && !playlistShown && hasPlayableFiles else { return super.draggingUpdated(sender) }

    func inTriggerArea(_ point: NSPoint?) -> Bool {
      guard let point = point, let frame = player.mainWindow.window?.frame else { return false }
      return point.x > (frame.maxX - frame.width * 0.2)
    }

    let position = NSEvent.mouseLocation

    if position != lastMousePosition {
      if inTriggerArea(lastMousePosition) {
        destroyTimer()
      }
      if inTriggerArea(position) {
        createTimer()
      }
      lastMousePosition = position
    }

    return super.draggingUpdated(sender)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    destroyTimer()
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return player.openFromPasteboard(sender)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    if playlistShown {
      player.mainWindow.hideSideBar()
    }
    playlistShown = false
    lastMousePosition = nil
  }

  // MARK: Display link

  func startDisplayLink() {
    if link == nil {
      CVDisplayLinkCreateWithActiveCGDisplays(&link)
    }
    guard let link = link else {
      Logger.fatal("Cannot Create display link!")
    }
    updateDisplayLink()
    CVDisplayLinkSetOutputCallback(link, displayLinkCallback, mutableRawPointerOf(obj: player.mpv))
    CVDisplayLinkStart(link)
  }

  func stopDisplayLink() {
    guard let link = link, CVDisplayLinkIsRunning(link) else { return }
    CVDisplayLinkStop(link)
  }

  // This should only be called if the window has changed displays
  func updateDisplayLink() {
    guard let window = window, let link = link, let screen = window.screen else { return }
    let displayId = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32

    // Do nothing if on the same display
    if (currentDisplay == displayId) { return }
    currentDisplay = displayId

    CVDisplayLinkSetCurrentCGDisplay(link, displayId)
    let actualData = CVDisplayLinkGetActualOutputVideoRefreshPeriod(link)
    let nominalData = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link)
    var actualFps: Double = 0;

    if (nominalData.flags & Int32(CVTimeFlags.isIndefinite.rawValue)) < 1 {
      let nominalFps = Double(nominalData.timeScale) / Double(nominalData.timeValue)

      if actualData > 0 {
        actualFps = 1/actualData
      }

      if abs(actualFps - nominalFps) > 1 {
        Logger.log("Falling back to nominal display refresh rate: \(nominalFps) from \(actualFps)")
        actualFps = nominalFps;
      }
    } else {
      Logger.log("Falling back to standard display refresh rate: 60 from \(actualFps)")
      actualFps = 60;
    }
    player.mpv.setDouble(MPVOption.Video.overrideDisplayFps, actualFps)

    if #available(macOS 10.15, *) {
      refreshEdrMode()
    } else {
      setICCProfile(displayId)
    }
  }

  func setICCProfile(_ displayId: UInt32) {
    if !Preference.bool(for: .loadIccProfile) {
      Logger.log("Not using ICC due to user preference", subsystem: hdrSubsystem)
      player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, "")
    } else {
      Logger.log("Loading ICC profile", subsystem: hdrSubsystem)
      typealias ProfileData = (uuid: CFUUID, profileUrl: URL?)
      guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayId)?.takeRetainedValue() else { return }

      var argResult: ProfileData = (uuid, nil)
      withUnsafeMutablePointer(to: &argResult) { data in
        ColorSyncIterateDeviceProfiles({ (dict: CFDictionary?, ptr: UnsafeMutableRawPointer?) -> Bool in
          if let info = dict as? [String: Any], let current = info["DeviceProfileIsCurrent"] as? Int {
            let deviceID = info["DeviceID"] as! CFUUID
            let ptr = ptr!.bindMemory(to: ProfileData.self, capacity: 1)
            let uuid = ptr.pointee.uuid

            if current == 1, deviceID == uuid {
              let profileURL = info["DeviceProfileURL"] as! URL
              ptr.pointee.profileUrl = profileURL
              return false
            }
          }
          return true
        }, data)
      }

      if let iccProfilePath = argResult.profileUrl?.path, FileManager.default.fileExists(atPath: iccProfilePath) {
        player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, iccProfilePath)
      }
    }

    if videoLayer.colorspace != nil {
      Logger.log("Nilling out colorspace", subsystem: hdrSubsystem)
      videoLayer.colorspace = nil;
      videoLayer.wantsExtendedDynamicRangeContent = false
      player.mpv.setString(MPVOption.GPURendererOptions.targetTrc, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.targetPrim, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.targetPeak, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.toneMapping, "")
      player.mpv.setFlag(MPVOption.Screenshot.screenshotTagColorspace, false)
    }
  }
}

// MARK: - HDR

@available(macOS 10.15, *)
extension VideoView {
  private struct VideoHDRInfo {
    let colorspaceName: CFString
    let isHdr: Bool
    let gamma: String
    let primaries: String
  }

  func refreshEdrMode() {
    guard player.mainWindow.loaded else { return }
    guard player.mpv.fileLoaded else { return }
    guard let displayId = currentDisplay else { return };
    if let screen = self.window?.screen {
      NSScreen.log("Refreshing HDR for \(player.subsystem.rawValue) @ display\(displayId)", screen)
    }

    let isHDRWanted: Bool
    // Must decide between either SDR or HDR: always one or the other.
    if let videoHdrInfo = getVideoHDRInfo() {
      isHDRWanted = shouldEnableHDR(videoHdrInfo.isHdr)

      if isHDRWanted {
        activateHDR(videoHdrInfo)  // Use HDR
      }
    } else {
      isHDRWanted = false
    }

    if !isHDRWanted {
      setICCProfile(displayId)  // Use SDR
    }

    if isHDRWanted != player.info.hdrAvailable {
      player.mainWindow.quickSettingView.setHdrAvailability(to: isHDRWanted)
    }
  }

  private func shouldEnableHDR(_ isVideoHDR: Bool) -> Bool {
    if !player.info.hdrEnabled {
      Logger.log("User disabled HDR in the player window", subsystem: hdrSubsystem)
      return false
    }

    if isVideoHDR {
      if !isEDRSupportedByDisplay() {
        Logger.log("HDR video was found but the display does not support EDR mode", subsystem: hdrSubsystem)
        return false
      }
      // fallthrough

    } else if !Preference.bool(for: .allowHdrModeForSdrVideos) {
      Logger.log("HDR video not allowed for SDR videos", subsystem: hdrSubsystem)
      return false
    }

    return true
  }

  private func isEDRSupportedByDisplay() -> Bool {
    (window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0
  }

  private func getVideoHDRInfo() -> VideoHDRInfo? {
    guard let primaries = player.mpv.getString(MPVProperty.videoParamsPrimaries), let gamma = player.mpv.getString(MPVProperty.videoParamsGamma) else {
      Logger.log("HDR primaries and gamma not available", subsystem: hdrSubsystem)
      return nil
    }

    var name: CFString
    var isHdr = false
    switch primaries {
      case "display-p3":
        switch gamma {
          case "pq":
            if #available(macOS 10.15.4, *) {
              name = CGColorSpace.displayP3_PQ
            } else {
              name = CGColorSpace.displayP3_PQ_EOTF
            }
          case "hlg":
            name = CGColorSpace.displayP3_HLG
          default:
            name = CGColorSpace.displayP3
        }
        isHdr = true

      case "bt.2020":
        switch gamma {
          case "pq":
            if #available(macOS 11.0, *) {
              name = CGColorSpace.itur_2100_PQ
            } else if #available(macOS 10.15.4, *) {
              name = CGColorSpace.itur_2020_PQ
            } else {
              name = CGColorSpace.itur_2020_PQ_EOTF
            }
          case "hlg":
            if #available(macOS 11.0, *) {
              name = CGColorSpace.itur_2100_HLG
            } else if #available(macOS 10.15.6, *) {
              name = CGColorSpace.itur_2020_HLG
            } else {
              fallthrough
            }
          default:
            name = CGColorSpace.itur_2020
        }
        isHdr = true

      case "bt.709":
        switch gamma {
          case "pq":
            if #available(macOS 12.0, *) {
              name = CGColorSpace.itur_709_PQ;
            } else {
              fallthrough
            }
          default:
            name = CGColorSpace.itur_709
        }

      default:
        Logger.log("Unknown HDR color space information gamma=\(gamma) primaries=\(primaries)", subsystem: hdrSubsystem)
        return nil
    }

    return VideoHDRInfo(colorspaceName: name, isHdr: isHdr, gamma: gamma, primaries: primaries)
  }

  private func activateHDR(_ videoInfo: VideoHDRInfo) {
    Logger.log("Setting HDR colorspace=\"\(videoInfo.colorspaceName)\" isHDR=\(videoInfo.isHdr) gamma=\"\(videoInfo.gamma)\" primaries=\"\(videoInfo.primaries)\"")

    guard videoLayer.colorspace?.name != videoInfo.colorspaceName else {
      Logger.log("HDR mode already enabled, skipping", subsystem: hdrSubsystem)
      return
    }

    Logger.log("Will activate HDR color space instead of using ICC profile", subsystem: hdrSubsystem)
    videoLayer.wantsExtendedDynamicRangeContent = true

    videoLayer.colorspace = CGColorSpace(name: videoInfo.colorspaceName)
    player.mpv.setString(MPVOption.GPURendererOptions.iccProfile, "")
    player.mpv.setString(MPVOption.GPURendererOptions.targetTrc, videoInfo.gamma)
    player.mpv.setString(MPVOption.GPURendererOptions.targetPrim, videoInfo.primaries)
    player.mpv.setFlag(MPVOption.Screenshot.screenshotTagColorspace, true)

    if Preference.bool(for: .enableToneMapping) {
      let targetPeak = Preference.integer(for: .toneMappingTargetPeak)
      let algorithm = Preference.ToneMappingAlgorithmOption(rawValue: Preference.integer(for: .toneMappingAlgorithm))!.mpvString

      Logger.log("Will enable tone mapping target-peak=\(targetPeak) algorithm=\(algorithm)", subsystem: hdrSubsystem)
      player.mpv.setInt(MPVOption.GPURendererOptions.targetPeak, targetPeak)
      player.mpv.setString(MPVOption.GPURendererOptions.toneMapping, algorithm)
    } else {
      player.mpv.setString(MPVOption.GPURendererOptions.targetPeak, "auto")
      player.mpv.setString(MPVOption.GPURendererOptions.toneMapping, "")
    }
  }
}

fileprivate func displayLinkCallback(
  _ displayLink: CVDisplayLink, _ inNow: UnsafePointer<CVTimeStamp>,
  _ inOutputTime: UnsafePointer<CVTimeStamp>,
  _ flagsIn: CVOptionFlags,
  _ flagsOut: UnsafeMutablePointer<CVOptionFlags>,
  _ context: UnsafeMutableRawPointer?) -> CVReturn {
    let mpv = unsafeBitCast(context, to: MPVController.self)
    mpv.mpvReportSwap()
    return kCVReturnSuccess
  }
