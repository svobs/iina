//
//  Aspect.swift
//  iina
//
//  Created by lhc on 2/9/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa

class Aspect: NSObject {
  // Used internally as identifier when communicating with mpv. Should not be displayed because it is not localized:
  static let defaultIdentifier = "Default"

  /// Used to generate aspect and crop options in menu. Does not include `Default`, `None`, or `Custom`
  static let aspectsInMenu: [String] = ["4:3", "5:4", "16:9", "16:10", "1:1", "3:2", "2.21:1", "2.35:1", "2.39:1",
                                        "3:4", "4:5", "9:16", "10:16", "2:3", "1:2.35", "1:2.39", "21:9"]

  static var allKnownLabels: [String] = {
    var all: Set<String> = Set<String>()
    for ratio in aspectsInMenu {
      all.insert(ratio)
    }
    for ratio in mpvNameDict.values {
      all.insert(ratio)
    }
    return Array(all)
  }()

  static let mpvNameDict: [String: String] = [
    "Vertical": "9:16",
    "Square": "1:1",
    "Movietone Ratio": "19:16",
    "Academy Ratio": "11:8",
    "IMAX Ratio": "1.43",
    "VistaVision Ratio": "3:2",
    "35mm Widescreen Ratio": "5:3",
    "Early 35mm Widescreen Ratio": "7:4",
    "Academy Flat": "1.85",
    "SMPTE/DCI Ratio": "256:135",
    "Univisium": "2.0",
    "70mm film": "2.208",
    "Scope": "2.35",
    "Panavision": "2.39",
    "Original CinemaScope": "2.55",
    "Full-frame Cinerama": "2.59",
    "Full-frame Super 16mm": "24:9",
    "Ultra Panavision 70": "2.76",
    "Ultra-WideScreen 3.6": "3.6",
    "Polyvision": "4.0",
    "Circle-Vision 360°": "12.0",
  ]

  static func mpvPrecision(of aspectRatio: CGFloat) -> CGFloat {
    // Assume 6 digits of precision. We are motivated to use lower precision to improve the odds of
    // matching a known aspect name, but we also don't want our calculations to stray too far from mpv's
    return Double(aspectRatio).roundedTo6()
  }

  static func isValid(_ string: String) -> Bool {
    return Aspect(string: string) != nil
  }

  static func looselyEquals(_ lhs: Double, _ rhs: Double) -> Bool {
    return (lhs - rhs).magnitude < 0.01
  }

  static func resolvingMpvName(_ string: String) -> String {
    let ratioLabel = mpvNameDict[string]
    return ratioLabel ?? string
  }

  /// This includes crop presets, because at present, all crop presets are aspect ratios.
  static func findLabelForAspectRatio(_ aspectRatio: Double, strict: Bool = true) -> String? {
    let mpvAspect = strict ? mpvPrecision(of: aspectRatio) : aspectRatio
    let userAspectPresets = Preference.csvStringArray(for: .aspectRatioPanelPresets) ?? []
    let userCropPresets = Preference.csvStringArray(for: .cropPanelPresets) ?? []
    for knownAspectRatio in allKnownLabels + userAspectPresets + userCropPresets {
      if let knownAspect = Aspect(string: knownAspectRatio) {
        if strict {
          if knownAspect.mpvAspect == mpvAspect {
            return knownAspectRatio
          }
        } else if looselyEquals(knownAspect.mpvAspect, mpvAspect) {
          // Matches a known aspect. Use its colon notation (X:Y) instead of decimal value
          return knownAspectRatio
        }
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
      if let knownAspectRatio = findLabelForAspectRatio(aspectDouble) {
        aspectLabel = knownAspectRatio
      } else {
        aspectLabel = aspectDouble.mpvAspectString
      }
    } else {
      aspectLabel = defaultIdentifier
      // -1, Default, "no", or unrecognized
      // (do not allow "no")
    }
    return aspectLabel
  }

  /// See: https://mpv.io/manual/stable/#options-video-aspect-override
  /// First use: `let aspectLabel = bestLabelFor(aspectString)`
  static func mpvVideoAspectOverride(fromAspectLabel aspectLabel: String) -> String {
    switch aspectLabel {
    case defaultIdentifier:
      return "-1"
    default:
      return aspectLabel
    }
  }

  // MARK: - Instance

  private var size: NSSize!

  var value: CGFloat {
    return size.aspect
  }

  var doubleValue: Double {
    return Double(value)
  }

  var mpvAspect: CGFloat {
    return size.mpvAspect
  }

  init(size: NSSize) {
    self.size = size
  }

  init?(ratio: CGFloat) {
    guard ratio > 0.0 else { return nil }
    self.size = NSMakeSize(CGFloat(ratio), CGFloat(1))
  }

  init?(string: String) {
    guard string != Aspect.defaultIdentifier else { return nil }
    
    // Look up mpv name and translate it to ratio (if applicable)
    let string = Aspect.resolvingMpvName(string)

    if Regex.aspect.matches(string) {
      let wh = string.components(separatedBy: ":")
      if let cropW = Float(wh[0]), let cropH = Float(wh[1]) {
        self.size = NSMakeSize(CGFloat(cropW), CGFloat(cropH))
      }
    } else if let ratio = Double(string), ratio > 0.0 {
      self.size = NSMakeSize(CGFloat(ratio), CGFloat(1))
    } else {
      return nil
    }
  }
}
