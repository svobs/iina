//
//  PWin_Enums.swift
//  iina
//
//  Created by Matt Svoboda on 2024-10-08.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

extension PlayerWindowController {
  enum TrackingArea: Int {
    static let key: String = "area"

    case playerWindow = 0
    case playSlider
    case customTitleBar
  }

  enum PIPStatus {
    case notInPIP
    case inPIP
    case intermediate
  }

  /// Animation state. Used for fadeable views, OSD.
  enum UIAnimationState {
    case shown, hidden, willShow, willHide

    var isInTransition: Bool {
      return self == .willShow || self == .willHide
    }
  }

}  // extension PlayerWindowController



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
