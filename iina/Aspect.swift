//
//  Aspect.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class Aspect: NSObject {
  static func mpvPrecision(of aspectRatio: CGFloat) -> CGFloat {
    // Assume 6 digits of precision. We are motivated to use lower precision to improve the odds of
    // matching a known aspect name, but we also don't want our calculations to stray too far from mpv's
    return Double(aspectRatio).roundedTo6()
  }

  static func isValid(_ string: String) -> Bool {
    return Aspect(string: string) != nil
  }

  // TODO: incorporate mpv aspect-name
  static func findLabelForAspectRatio(_ aspectRatio: Double) -> String? {
    let mpvAspect = Aspect.mpvPrecision(of: aspectRatio)
    let userPresets = Preference.csvStringArray(for: .aspectRatioPanelPresets) ?? []
    for knownAspectRatio in AppData.aspectsInMenu + userPresets {
      if let knownAspect = Aspect(string: knownAspectRatio), knownAspect.value == mpvAspect {
        // Matches a known aspect. Use its colon notation (X:Y) instead of decimal value
        return knownAspectRatio
      }
    }
    // Not found
    return nil
  }

  static func bestLabelFor(_ aspectString: String) -> String {
    let aspectLabel: String
    if aspectString.contains(":"), Aspect(string: aspectString) != nil {
      // Aspect is in colon notation (X:Y)
      aspectLabel = aspectString
    } else if let aspectDouble = Double(aspectString), aspectDouble > 0 {
      /// Aspect is a decimal number, but is not default (`-1` or video default)
      /// Try to match to known aspect by comparing their decimal values to the new aspect.
      /// Note that mpv seems to do its calculations to only 2 decimal places of precision, so use that for comparison.
      if let knownAspectRatio = Aspect.findLabelForAspectRatio(aspectDouble) {
        aspectLabel = knownAspectRatio
      } else {
        aspectLabel = aspectDouble.mpvAspectString
      }
    } else {
      aspectLabel = AppData.defaultAspectIdentifier
      // -1, Default, "no", or unrecognized
      // (do not allow "no")
    }
    return aspectLabel
  }

  /// See: https://mpv.io/manual/stable/#options-video-aspect-override
  /// First use: `let aspectLabel = bestLabelFor(aspectString)`
  static func mpvVideoAspectOverride(fromAspectLabel aspectLabel: String) -> String {
    switch aspectLabel {
    case AppData.defaultAspectIdentifier:
      return "-1"
    default:
      return aspectLabel
    }
  }

  private var size: NSSize!

  var width: CGFloat {
    get {
      return size.width
    }
    set {
      size.width = newValue
    }
  }

  var height: CGFloat {
    get {
      return size.height
    }
    set {
      size.height = newValue
    }
  }

  var value: CGFloat {
    get {
      return Aspect.mpvPrecision(of: size.width / size.height)
    }
  }

  init(size: NSSize) {
    self.size = size
  }

  init?(string: String) {
    if Regex.aspect.matches(string) {
      let wh = string.components(separatedBy: ":")
      if let cropW = Float(wh[0]), let cropH = Float(wh[1]) {
        self.size = NSMakeSize(CGFloat(cropW), CGFloat(cropH))
      }
    } else if let ratio = Float(string), ratio > 0.0 {
      self.size = NSMakeSize(CGFloat(ratio), CGFloat(1))
    } else {
      return nil
    }
  }
}
