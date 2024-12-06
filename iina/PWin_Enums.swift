//
//  PWin_Enums.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-08.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation


/// Each `PlayerWindow` has a session associated with it. The session's state can be saved using `PlayerSaveState`.
/// This class helps keep track of the lifecycle state of the session.
enum PWinSessionState: CustomStringConvertible {

  case noSession

  /// Restoring the session from prior launch.
  /// `playerState`: contains state data needed to restore the UI state from a previous launch, loaded from prefs.
  case restoring(playerState: PlayerSaveState)

  /// Opening window (or reopening closed window) for new session & new file.
  case creatingNew

  /// Reusing an already open window, and discarding its current session, for new session & new file.
  case newReplacingExisting

  /// Existing window & session, but new file (i.e. current media is changing via playlist navigation).
  /// See also: `isChangingVideoTrack`.
  case existingSession_startingNewPlayback

  /// Existing window, session, & file, but current video track was changed.
  case existingSession_videoTrackChangedForSamePlayback

  /// Existing window, session, file.
  case existingSession_continuing

  /// Need to specify this so that `playerState` is not included...
  var description: String {
    switch self {
    case .restoring:
      "restoring"
    case .creatingNew:
      "creatingNew"
    case .newReplacingExisting:
      "newReplacingExisting"
    case .existingSession_startingNewPlayback:
      "existingSession_startingNewPlayback"
    case .existingSession_videoTrackChangedForSamePlayback:
      "existingSession_videoTrackChangedForSamePlayback"
    case .existingSession_continuing:
      "existingSession_continuing"
    case .noSession:
      "noSession"
    }
  }

  /// Changes to a new state based on the current state, assuming the action is to create a new session.
  func newSession() -> PWinSessionState {
    switch self {
    case .existingSession_continuing:
      return .newReplacingExisting
    case .noSession:
      return .creatingNew
    default:
      Logger.fatal("Unexpected sessionState for newSession(): \(self)")
    }
  }

  /// Is `true` only while restore from previous launch is still in progress; `false` otherwise.
  var isRestoring: Bool {
    if case .restoring = self {
      return true
    }
    return false
  }

  /// Returns `true` if session finished its initial load. May be changing tracks or files within the session.
  var hasOpenSession: Bool {
    return !isNone && !isOpeningFileManually
  }

  /// Returns true if starting or resuming a session.
  var isStartingSession: Bool {
    return !isNone && isOpeningFileManually
  }

  /// Most similar to the term "Opening file" in Settings window's UI, but also applies when changing video track
  /// in the same file.
  ///
  /// Note that case `.restoring` is considered to be opening a file and thus returns `true`.
  /// See also: `isOpeningFileManually`.
  var isChangingVideoTrack: Bool {
    switch self {
    case .restoring,
        .creatingNew,
        .newReplacingExisting,
        .existingSession_startingNewPlayback,
        .existingSession_videoTrackChangedForSamePlayback:
      return true
    case .existingSession_continuing,
        .noSession:
      return false
    }
  }

  var isOpeningFile: Bool {
    switch self {
    case .restoring,
        .creatingNew,
        .newReplacingExisting,
        .existingSession_startingNewPlayback:
      return true
    case .existingSession_videoTrackChangedForSamePlayback,
        .existingSession_continuing,
        .noSession:
      return false
    }
  }

  /// Most similar to the term "Opening file manually" in Settings window's UI.
  ///
  /// Note that case `.restoring` is considered to be opening a file and thus returns `true`.
  var isOpeningFileManually: Bool {
    switch self {
    case .restoring,
        .creatingNew,
        .newReplacingExisting:
      return true
    case .existingSession_startingNewPlayback,
        .existingSession_videoTrackChangedForSamePlayback,
        .existingSession_continuing,
        .noSession:
      return false
    }
  }

  var isNone: Bool {
    if case .noSession = self {
      return true
    }
    return false
  }

  var canUseIntendedViewportSize: Bool {
    if case .existingSession_startingNewPlayback = self {
      return true
    }
    return false
  }
}


extension PlayerWindowController {
  enum TrackingArea: Int {
    static let key: String = "area"

    case playerWindow = 0
    case playSlider
    case customTitleBar
  }

  /// Animation state. Used for fadeable views, OSD.
  enum UIAnimationState {
    case shown, hidden, willShow, willHide

    var isInTransition: Bool {
      return self == .willShow || self == .willHide
    }
  }

}  // extension PlayerWindowController


/// Enumeration representing the status of the [mpv](https://mpv.io/manual/stable/) A-B loop command.
///
/// The A-B loop command cycles mpv through these states:
/// - Cleared (looping disabled)
/// - A loop point set
/// - B loop point set (looping enabled)
enum LoopStatus: Int {
  case cleared = 0
  case aSet
  case bSet
}


enum PlayerWindowMode: Int {
  /// Note: both `windowed` & `windowedInteractive` modes are considered windowed"
  case windowedNormal = 1
  case fullScreenNormal
  case musicMode
  case windowedInteractive
  case fullScreenInteractive

  var alwaysLockViewportToVideoSize: Bool {
    switch self {
    case .musicMode:
      return true
    case .fullScreenNormal, .windowedNormal, .windowedInteractive, .fullScreenInteractive:
      return false
    }
  }

  var neverLockViewportToVideoSize: Bool {
    switch self {
    case .fullScreenNormal:
      return true
    case .musicMode, .windowedInteractive, .fullScreenInteractive, .windowedNormal:
      return false
    }
  }

  var isWindowed: Bool {
    return self == .windowedNormal || self == .windowedInteractive
  }

  var isFullScreen: Bool {
    return self == .fullScreenNormal || self == .fullScreenInteractive
  }

  var isInteractiveMode: Bool {
    return self == .windowedInteractive || self == .fullScreenInteractive
  }

  var lockViewportToVideoSize: Bool {
    if alwaysLockViewportToVideoSize {
      return true
    }
    if neverLockViewportToVideoSize {
      return false
    }
    return Preference.bool(for: .lockViewportToVideoSize)
  }
}


/// Represents a visibility mode for a given component in the player window
enum VisibilityMode {
  case hidden
  case showAlways
  case showFadeableTopBar     // fade in as part of the top bar
  case showFadeableNonTopBar  // fade in as a fadeable view which is not top bar

  var isShowable: Bool {
    return self != .hidden
  }

  var isFadeable: Bool {
    switch self {
    case .showFadeableTopBar, .showFadeableNonTopBar:
      return true
    default:
      return false
    }
  }
}


enum InteractiveMode: Int {
  case crop = 1
  case freeSelecting

  func viewController() -> CropBoxViewController {
    var vc: CropBoxViewController
    switch self {
    case .crop:
      vc = CropSettingsViewController()
    case .freeSelecting:
      vc = FreeSelectingViewController()
    }
    return vc
  }
}
