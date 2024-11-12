//
//  PWin_OSD.swift
//  iina
//
//  Created by Matt Svoboda on 6/11/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation
import Mustache

/// Encapsulates all of the window's OSD state vars
class OSDState {
  let log: Logger.Subsystem

  /// Whether current OSD needs user interaction to be dismissed.
  var isShowingPersistentOSD = false
  var animationState: PlayerWindowController.UIAnimationState = .hidden
  var hideOSDTimer: Timer?
  var nextSeekIcon: NSImage? = nil
  var currentSeekIcon: NSImage? = nil
  var lastPlaybackPosition: Double? = nil
  var lastPlaybackDuration: Double? = nil
  private var lastDisplayedMsgTS: TimeInterval = 0
  var lastDisplayedMsg: OSDMessage? = nil {
    didSet {
      guard lastDisplayedMsg != nil else { return }
      lastDisplayedMsgTS = Date().timeIntervalSince1970
    }
  }
  var currentlyDisplayedMsg: OSDMessage? {
    return animationState == .shown ? lastDisplayedMsg : nil
  }
  func didShowLastMsgRecently() -> Bool {
    return Date().timeIntervalSince1970 - lastDisplayedMsgTS < 0.25
  }
  // Need to keep a reference to NSViewController here in order for its Objective-C selectors to work
  var context: NSViewController? = nil {
    willSet {
      guard newValue != context else { return }
      if let newValue {
        log.verbose("Updating osd.context to: \(newValue)")
      } else {
        log.verbose("Updating osd.context to: nil")
      }
    }
  }
  var textSizeLast: CGFloat = 0
  let queueLock = Lock()
  var queue = LinkedList<() -> Void>()

  func clearQueuedOSDs() {
    queueLock.withLock {
      queue.clear()
    }
  }

  init(log: Logger.Subsystem) {
    self.log = log
  }
}

// PlayerWindow UI: OSD
extension PlayerWindowController {

  /// Enforces `Preference.Key.osdPosition` pref which allows OSD to be on either left or right
  func updateOSDPosition() {
    guard let contentView = window?.contentView else { return }
    contentView.removeConstraint(leadingSidebarToOSDSpaceConstraint)
    contentView.removeConstraint(trailingSidebarToOSDSpaceConstraint)
    let osdPosition: Preference.OSDPosition = Preference.enum(for: .osdPosition)
    switch osdPosition {
    case .topLeading:
      // OSD on left, AdditionalInfo on right
      leadingSidebarToOSDSpaceConstraint = leadingSidebarView.trailingAnchor.constraint(equalTo: osdVisualEffectView.leadingAnchor, constant: -8.0)
      trailingSidebarToOSDSpaceConstraint = trailingSidebarView.leadingAnchor.constraint(equalTo: additionalInfoView.trailingAnchor, constant: 8.0)
    case .topTrailing:
      // AdditionalInfo on left, OSD on right
      leadingSidebarToOSDSpaceConstraint = leadingSidebarView.trailingAnchor.constraint(equalTo: additionalInfoView.leadingAnchor, constant: -8.0)
      trailingSidebarToOSDSpaceConstraint = trailingSidebarView.leadingAnchor.constraint(equalTo: osdVisualEffectView.trailingAnchor, constant: 8.0)
    }
    
    leadingSidebarToOSDSpaceConstraint.priority = .defaultHigh
    leadingSidebarToOSDSpaceConstraint.isActive = true
    trailingSidebarToOSDSpaceConstraint.isActive = true
    contentView.layoutSubtreeIfNeeded()
  }

  /// If `newMessage` is provided, the OSD will be updated to display it. Otherwise if the OSD is
  /// already shown and is displaying one of the message types which requires live updates, it will be updated.
  func setOSDViews(fromMessage newMessage: OSDMessage? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    let message: OSDMessage?

    if let newMessage {
      message = newMessage

    } else if let currentMsg = osd.currentlyDisplayedMsg,
              let position = player.info.playbackPositionSec,
              let duration = player.info.playbackDurationSec {
      // If the OSD is visible and is showing playback position, keep its displayed time up to date:
      switch currentMsg {
      case .pause:
        message = .pause(playbackPositionSec: position, playbackDurationSec: duration)
      case .resume:
        message = .resume(playbackPositionSec: position, playbackDurationSec: duration)
      case .seek(_, _):
        message = .seek(playbackPositionSec: position, playbackDurationSec: duration)
      default:
        message = nil
      }
    } else {
      message = nil
    }

    guard let message else {
      // Often this method was called in response to a layout change.
      // For some reason the text wrap of the following is not recomputed or the text may be smashed/stretched,
      // so mark it expclitly as needing redisplay here:
      osdLabel.needsDisplay = true
      osdAccessoryText.needsDisplay = true
      return
    }

    defer {
      osdVisualEffectView.layout()
    }

    updateOSDIcon(from: message)

    let (osdText, osdType) = message.details()
    osdLabel.stringValue = osdText

    // Most OSD messages are displayed based on the configured language direction.
    osdAccessoryProgress.userInterfaceLayoutDirection = osdVStackView.userInterfaceLayoutDirection
    osdAccessoryText.baseWritingDirection = .natural
    osdLabel.baseWritingDirection = .natural
    switch osdType {
    case .normal:
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)
    case .withLeftToRightProgress(let value):
      // OSD messages displaying the playback position must always be displayed left to right.
      osdAccessoryProgress.userInterfaceLayoutDirection = .leftToRight
      osdLabel.baseWritingDirection = .leftToRight
      fallthrough
    case .withProgress(let value):
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryProgress)
      osdAccessoryProgress.doubleValue = value
    case .withLeftToRightText(let text):
      // OSD messages displaying the playback position must always be displayed left to right.
      osdAccessoryText.baseWritingDirection = .leftToRight
      fallthrough
    case .withText(let text):
      guard !player.isStopping else { return }  /// prevent crash when `mpv.getInt()` is used below
      osdVStackView.setVisibilityPriority(.mustHold, for: osdAccessoryText)
      osdVStackView.setVisibilityPriority(.notVisible, for: osdAccessoryProgress)

      // data for mustache rendering
      let osdData: [String: String] = [
        "duration": VideoTime.string(from: player.info.playbackDurationSec),
        "position": VideoTime.string(from: player.info.playbackPositionSec),
        "currChapter": (player.mpv.getInt(MPVProperty.chapter) + 1).description,
        "chapterCount": player.info.chapters.count.description
      ]
      osdAccessoryText.stringValue = try! (try! Template(string: text)).render(osdData)
    }
  }

  private func updateOSDIcon(from message: OSDMessage) {
    guard #available(macOS 11.0, *) else { return }

    var icon: NSImage? = nil
    var isIconGrayedOut = false

    if message.isSoundRelated {
      // Add sound icon which indicates current audio status.
      // Gray color == disabled. Slash == muted. Can be combined

      let isAudioDisabled = !player.info.isAudioTrackSelected
      let currentVolume = player.info.volume
      let isMuted = player.info.isMuted
      isIconGrayedOut = isAudioDisabled
      if isAudioDisabled {
        icon = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "No audio track is selected")!
      } else {
        icon = volumeIcon(volume: currentVolume, isMuted: isMuted)
      }
    } else {
      switch message {
      case .resume:
        icon = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")!
      case .pause:
        icon = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause")!
      case .stop:
        icon = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")!
      case .seek:
        icon = osd.currentSeekIcon
      default:
        break
      }
    }

    if let icon {
      let finalheight = osdIconHeightConstraint.constant
      let finalWidth = round(icon.size.aspect * finalheight)
      osdIconWidthConstraint.constant = finalWidth

      osdIconImageView.image =  icon
      osdIconImageView.contentTintColor = isIconGrayedOut ? .disabledControlTextColor : .controlTextColor
    }
    let isIconVisible = icon != nil
    // Need this only for OSD messages which use the icon
    osdIconImageView.isHidden = !isIconVisible
    if log.isTraceEnabled {
      log.trace("OSD icon=\(isIconVisible.yn) for msg: \(message)")
    }
  }

  /// If `position` and `duration` are different than their previously cached values, overwrites the cached values and
  /// returns `true`. Returns `false` if the same or one of the values is `nil`.
  ///
  /// Lots of redundant `seek` messages which are emitted at all sorts of different times, and each triggers a call to show
  /// a `seek` OSD. To prevent duplicate OSDs, call this method to compare against the previous seek position.
  private func compareAndSetIfNewPlaybackTime(position: Double?, duration: Double?) -> Bool {
    guard let position, let duration else {
      log.verbose("Ignoring request for OSD seek: position or duration is missing")
      return false
    }
    // There seem to be precision errors which break equality when comparing values beyond 6 decimal places.
    // Just round to nearest 1/1000000 sec for comparison.
    let newPosRounded = round(position * AppData.osdSeekSubSecPrecisionComparison)
    let newDurRounded = round(duration * AppData.osdSeekSubSecPrecisionComparison)
    let oldPosRounded = round((osd.lastPlaybackPosition ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    let oldDurRounded = round((osd.lastPlaybackDuration ?? -1) * AppData.osdSeekSubSecPrecisionComparison)
    guard newPosRounded != oldPosRounded || newDurRounded != oldDurRounded else {
      log.verbose("Ignoring request for OSD seek; position/duration has not changed")
      return false
    }
    osd.lastPlaybackPosition = position
    osd.lastPlaybackDuration = duration
    return true
  }

  /// Do not call `displayOSD` directly. Call `PlayerCore.sendOSD` instead.
  ///
  /// There is a timing issue that can occur when the user holds down a key to rapidly repeat a key binding or menu item equivalent,
  /// which should result in an OSD being displayed for each keypress. But for some reason, the task to update the OSD,
  /// which is enqueued via `DispatchQueue.main.async` (or even `sync`), does not run at all while the key events continue to come in.
  /// To work around this issue, we instead enqueue the tasks to display OSD using a simple LinkedList and Lock. Then we call
  /// `updateUI()` both from here (as before), and inside the key event callbacks in `PlayerWindow` so that that the key events
  /// themselves process the display of any enqueued OSD messages.
  func displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                  accessoryViewController: NSViewController? = nil, isExternal: Bool = false) {
    guard player.canShowOSD() || msg.alwaysEnabled else { return }
    guard !msg.isDisabled else { return }
    
    // Enqueue first, in case main queue is blocked
    osd.queueLock.withLock {
      osd.queue.append({ [self] in
        // DO NOT use animation pipeline here. It is not needed, and will cause OSD to block
        _displayOSD(msg, autoHide: autoHide, forcedTimeout: forcedTimeout, accessoryViewController: accessoryViewController)
      })
    }
    // Need to do the UI sync in the main queue
    DispatchQueue.main.async { [self] in
      updateUI()
    }
  }

  private func _displayOSD(_ msg: OSDMessage, autoHide: Bool = true, forcedTimeout: Double? = nil,
                           accessoryViewController: NSViewController? = nil) {
    assert(DispatchQueue.isExecutingIn(.main))

    // Check again. May have been enqueued a while
    guard player.canShowOSD() else { return }

    // Filter out unwanted OSDs first
    guard !osd.isShowingPersistentOSD || accessoryViewController != nil else { return }

    // If showing debug OSD, do not allow any other OSD type to replace it
    if case .debug = osd.currentlyDisplayedMsg {
      if case .debug = msg {
      } else {
        log.verbose("Discarding OSD '\(msg)' because a debug msg is visible")
        return
      }
    }

    var msg = msg
    switch msg {
    case .seek(_, _):
      // Many redundant messages are sent from mpv. Try to filter them out here
      if osd.didShowLastMsgRecently() {
        if case .speed = osd.lastDisplayedMsg { return }
        if case .frameStep = osd.lastDisplayedMsg { return }
        if case .frameStepBack = osd.lastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.playbackPositionSec, info.playbackDurationSec
      guard compareAndSetIfNewPlaybackTime(position: player.info.playbackPositionSec, duration: player.info.playbackDurationSec) else {
        // Is redundant msg; discard
        return
      }
    case .pause, .resume:
      if osd.didShowLastMsgRecently() {
        if case .speed = osd.lastDisplayedMsg, case .resume = msg { return }
        if case .frameStep = osd.lastDisplayedMsg { return }
        if case .frameStepBack = osd.lastDisplayedMsg { return }
      }
      player.updatePlaybackTimeInfo()  // need to call this to update info.playbackPositionSec, info.playbackDurationSec
      osd.lastPlaybackPosition = player.info.playbackPositionSec
      osd.lastPlaybackDuration = player.info.playbackDurationSec
    case .crop(let newCropLabel):
      if newCropLabel == AppData.noneCropIdentifier && !isInInteractiveMode && player.info.videoFiltersDisabled[Constants.FilterLabel.crop] != nil {
        log.verbose("Ignoring request to show OSD crop 'None': looks like user starting to edit an existing crop")
        return
      }
    case .resumeFromWatchLater:
      if case .fileStart(let filename, _) = osd.lastDisplayedMsg {
        // Append details msg indicating restore state to existing msg
        let detailsMsg = msg.details().0
        msg = .fileStart(filename, detailsMsg)
      }

    default:
      break
    }

    // End filtering

    osd.lastDisplayedMsg = msg

    if #available(macOS 11.0, *) {

      /// The pseudo-OSDMessage `seekRelative`, if present, contains the step time for a relative seek.
      /// But because it needs to be parsed from the mpv log, it is sent as a separate msg which arrives immediately
      /// prior to the `seek` msg. With some smart logic, the info from the two messages can be combined to display
      /// the most appropriate "jump" icon in the OSD in addition to the time display & progress bar.
      if case .seekRelative(let stepString) = msg, let step = Double(stepString) {
        log.verbose("Got OSD '\(msg)'")

        let isBackward = step < 0
        let accDescription = "Relative Seek \(isBackward ? "Backward" : "Forward")"
        var name: String
        switch abs(step) {
        case 5, 10, 15, 30, 45, 60, 75, 90:
          let absStep = Int(abs(step))
          name = isBackward ? "gobackward.\(absStep)" : "goforward.\(absStep)"
        default:
          name = isBackward ? "gobackward.minus" : "goforward.plus"
        }
        /// Set icon for next msg, which is expected to be a `seek`
        osd.nextSeekIcon = NSImage(systemSymbolName: name, accessibilityDescription: accDescription)!
        /// Done with `seekRelative` msg. It is not used for display.
        return
      } else if case .seek(_, _) = msg {
        /// Shift next icon into current icon, which will be used until the next call to `displayOSD()`
        /// (although note that there can be subsequent calls to `setOSDViews()` to update the OSD's displayed time while playing,
        /// but those do not count as "new" OSD messages, and thus will continue to use `osd.currentSeekIcon`).
        if isInScrollWheelSeek {
          // give up on fancy OSD for scroll wheel seek (for now)
          osd.currentSeekIcon = nil
          osd.nextSeekIcon = nil
        } else if osd.nextSeekIcon != nil {
          osd.currentSeekIcon = osd.nextSeekIcon
          osd.nextSeekIcon = nil
        }
      } else {
        osd.currentSeekIcon = nil
      }
    }

    // Restart timer
    osd.hideOSDTimer?.invalidate()
    if osd.animationState != .shown {
      osd.animationState = .shown  /// set this before calling `refreshSyncUITimer()`
      DispatchQueue.main.async { [self] in  /// launch async task to avoid recursion, which `osdQueueLock` doesn't like
        player.refreshSyncUITimer()
      }
    } else {
      osd.animationState = .shown
    }

    if autoHide {
      let timeout: Double
      if let forcedTimeout = forcedTimeout {
        timeout = forcedTimeout
        log.verbose("Showing OSD '\(msg)' forcedTimeout=\(timeout)")
      } else {
        // Timer and animation APIs require Double, but we must support legacy prefs, which store as Float
        timeout = max(IINAAnimation.OSDAnimationDuration, Double(Preference.float(for: .osdAutoHideTimeout)))
        log.verbose("Showing OSD '\(msg)' timeout=\(timeout)")
      }
      osd.hideOSDTimer = Timer.scheduledTimer(timeInterval: TimeInterval(timeout), target: self, selector: #selector(self.hideOSD), userInfo: nil, repeats: false)
    } else {
      log.verbose("Showing OSD '\(msg)', no timeout")
    }

    updateOSDTextSize()
    setOSDViews(fromMessage: msg)

    let existingAccessoryViews = osdVStackView.views(in: .bottom)
    if !existingAccessoryViews.isEmpty {
      for subview in osdVStackView.views(in: .bottom) {
        osdVStackView.removeView(subview)
      }
    }
    if let accessoryViewController {  // e.g., ScreenshootOSDView
      let accessoryView = accessoryViewController.view
      osd.context = accessoryViewController
      osd.isShowingPersistentOSD = true

      osdVStackView.addView(accessoryView, in: .bottom)
    }

    osdVisualEffectView.layoutSubtreeIfNeeded()
    osdVisualEffectView.alphaValue = 1
    osdVisualEffectView.isHidden = false
    fadeableViews.remove(osdVisualEffectView)
  }

  @objc
  func hideOSD(immediately: Bool = false, refreshSyncUITimer: Bool = true) {
    assert(DispatchQueue.isExecutingIn(.main))
    guard loaded else { return }
    if osd.animationState != .hidden {
      log.trace("Hiding OSD")
    }
    osd.animationState = .willHide
    osd.isShowingPersistentOSD = false
    osd.context = nil
    osd.hideOSDTimer?.invalidate()

    if refreshSyncUITimer {
      player.refreshSyncUITimer()
    }

    IINAAnimation.runAsync(IINAAnimation.Task(duration: immediately ? 0 : IINAAnimation.OSDAnimationDuration, { [self] in
      osdVisualEffectView.alphaValue = 0

    }), then: { [self] in
      if osd.animationState == .willHide {
        osd.animationState = .hidden
        osdVisualEffectView.isHidden = true
        osdVStackView.views(in: .bottom).forEach { self.osdVStackView.removeView($0) }
      }
    })
  }

  func updateOSDTextSize(from geo: PWinGeometry? = nil) {
    guard player.info.isFileLoadedAndSized else { return }

    let pwGeo: PWinGeometry
    if let geo {
      pwGeo = geo
    } else {
      switch currentLayout.mode {
      case .windowedNormal, .windowedInteractive:
        pwGeo = windowedGeoForCurrentFrame()
      case .fullScreenNormal, .fullScreenInteractive:
        pwGeo = currentLayout.buildFullScreenGeometry(inScreenID: bestScreen.screenID, video: self.geo.video)
      case .musicMode:
        pwGeo = musicModeGeoForCurrentFrame().toPWinGeometry()
      }
    }

    let availableSpaceForOSD = pwGeo.widthBetweenInsideSidebars

    // Reduce text size if horizontal space is tight
    var osdTextSize = max(8.0, CGFloat(Preference.float(for: .osdTextSize)))
    switch availableSpaceForOSD {
    case ..<300:
      osdTextSize = min(osdTextSize, 18)
    case 300..<400:
      osdTextSize = min(osdTextSize, 28)
    case 400..<500:
      osdTextSize = min(osdTextSize, 36)
    case 500..<700:
      osdTextSize = min(osdTextSize, 50)
    case 700..<900:
      osdTextSize = min(osdTextSize, 72)
    case 900..<1200:
      osdTextSize = min(osdTextSize, 96)
    case 1200..<1500:
      osdTextSize = min(osdTextSize, 120)
    default:
      osdTextSize = min(osdTextSize, 150)
    }

    guard osdTextSize != osd.textSizeLast else { return }

    log.verbose("Changing OSD textSize: \(osd.textSizeLast) → \(osdTextSize)")

    let osdAccessoryTextSize = (osdTextSize * 0.75).clamped(to: 11...25)
    osdAccessoryText.font = NSFont.monospacedDigitSystemFont(ofSize: osdAccessoryTextSize, weight: .regular)
    osdVisualEffectView.roundCorners()

    let marginScaled = 8 + (osdTextSize * 0.06)
    osdTopMarginConstraint.animateToConstant(marginScaled)
    osdBottomMarginConstraint.animateToConstant(marginScaled)
    osdTrailingMarginConstraint.animateToConstant(marginScaled)
    osdLeadingMarginConstraint.animateToConstant(marginScaled)

    let osdLabelFont = NSFont.monospacedDigitSystemFont(ofSize: osdTextSize, weight: .regular)
    osdLabel.font = osdLabelFont

    if #available(macOS 11.0, *) {
      switch osdTextSize {
      case 32...:
        osdAccessoryProgress.controlSize = .regular
      default:
        osdAccessoryProgress.controlSize = .small
      }
    }

    if #available(macOS 11.0, *) {
      // Use dimensions of a dummy image to keep the height fixed. Because all the components are vertically aligned
      // and each icon has a different height, this is needed to prevent the progress bar from jumping up and down
      // each time the OSD message changes.
      let attachment = NSTextAttachment()
      attachment.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "")!
      let iconString = NSMutableAttributedString(attachment: attachment)
      let osdIconTextSize = osdTextSize + (osdAccessoryProgress.fittingSize.height)
      let osdIconFont = NSFont.monospacedDigitSystemFont(ofSize: osdIconTextSize, weight: .regular)
      iconString.addAttribute(.font, value: osdIconFont, range: NSRange(location: 0, length: iconString.length))
      let iconHeight = iconString.size().height

      osdIconHeightConstraint.constant = iconHeight
    }
    osd.textSizeLast = osdTextSize
  }
}
