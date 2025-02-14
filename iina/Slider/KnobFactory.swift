//
//  KnobFactorying.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-18.
//  Copyright © 2025 lhc. All rights reserved.
//

class KnobFactory {

  enum KnobType: Int {
    case mainKnob = 0
    case mainKnobSelected
    case loopKnob
    case loopKnobSelected
    case volumeKnob
    case volumeKnobSelected

    var isLoopKnob: Bool {
      switch self {
      case .loopKnob, .loopKnobSelected:
        return true
      default:
        return false
      }
    }
  }

  init() {}

  // - Knob Constants

  /// Percentage of the height of the primary knob to use for the loop knobs when drawing.
  ///
  /// The height of loop knobs is reduced in order to give prominence to the slider's knob that controls the playback position.
  let loopKnobHeightAdjustment: CGFloat = 0.75

  /// Need a tiny amount of margin on all sides to allow for shadow and/or antialiasing
  let knobMarginRadius: CGFloat = 1.0

  var mainKnobColor = NSColor.mainSliderKnob
  var mainKnobActiveColor = NSColor.mainSliderKnobActive
  var loopKnobColor = NSColor.mainSliderLoopKnob
  let shadowColor = NSShadow().shadowColor!.cgColor
  let glowColor = NSColor.white.withAlphaComponent(1.0/3.0).cgColor

  // count should equal number of KnobTypes
  var cachedKnobs = [Knob?](repeating: nil, count: 6)

  func invalidateCachedKnobs() {
    for i in 0..<cachedKnobs.count {
      cachedKnobs[i] = nil
    }
  }

  func knobCornerRadius(fromKnobWidth knobWidth: CGFloat) -> CGFloat {
    (knobWidth * 0.33).rounded().clamped(to: 1.0...)
  }

  func getKnob(_ knobType: KnobType, darkMode: Bool, clearBG: Bool,
               knobWidth: CGFloat, mainKnobHeight: CGFloat, scaleFactor: CGFloat) -> Knob {

    if let cachedKnob = cachedKnobs[knobType.rawValue], cachedKnob.isDarkMode == darkMode,
       cachedKnob.knobWidth == knobWidth, cachedKnob.mainKnobHeight == mainKnobHeight,
       cachedKnob.scaleFactor == scaleFactor {
      return cachedKnob
    }
    // There may some minor loss due to races, but it will settle quickly. Don't need lousy locksss
    let knob = Knob(self, knobType, isDarkMode: darkMode, hasClearBG: clearBG,
                    knobWidth: knobWidth, mainKnobHeight: mainKnobHeight, scaleFactor: scaleFactor)
    cachedKnobs[knobType.rawValue] = knob
    return knob
  }

  func getKnobImage(_ knobType: KnobType, darkMode: Bool, clearBG: Bool,
                    knobWidth: CGFloat, mainKnobHeight: CGFloat, scaleFactor: CGFloat) -> CGImage {
    return getKnob(knobType, darkMode: darkMode, clearBG: clearBG,
                   knobWidth: knobWidth, mainKnobHeight: mainKnobHeight, scaleFactor: scaleFactor).image
  }

  func drawKnob(_ knobType: KnobType, in knobRect: NSRect, darkMode: Bool, clearBG: Bool,
                knobWidth: CGFloat, mainKnobHeight: CGFloat, scaleFactor: CGFloat) {
    let knob: Knob = getKnob(knobType, darkMode: darkMode, clearBG: clearBG,
                             knobWidth: knobWidth, mainKnobHeight: mainKnobHeight, scaleFactor: scaleFactor)
    let image = knob.image
    let marginRadius = knobMarginRadius
    let knobHeight = knobType.isLoopKnob ? loopKnobHeight(mainKnobHeight: knob.mainKnobHeight) : knob.mainKnobHeight
    let knobImageSize = imageSize(knobWidth: knobWidth, knobHeight: knobHeight)
    // These use points. The CGImage will be scaled appropriately.
    let drawRect = NSRect(x: round(knobRect.origin.x) - marginRadius,
                          y: knobRect.origin.y - marginRadius + (0.5 * (knobRect.height - knobHeight)),
                          width: knobImageSize.width,
                          height: knobImageSize.height)
    NSGraphicsContext.current!.cgContext.draw(image, in: drawRect)
  }

  func makeImage(fill: NSColor, shadow: CGColor?, knobWidth: CGFloat, knobHeight: CGFloat, scaleFactor: CGFloat) -> CGImage {
    let knobImageSizeScaled = imgSizeScaled(knobWidth: knobWidth, knobHeight: knobHeight,
                                            scaleFactor: scaleFactor)

    let knobMarginRadius_Scaled = knobMarginRadius * scaleFactor
    let knobCornerRadius_Scaled = knobCornerRadius(fromKnobWidth: knobWidth) * scaleFactor
    let knobImage = CGImage.buildBitmapImage(width: knobImageSizeScaled.widthInt,
                                             height: knobImageSizeScaled.heightInt) { cgContext in

      // Round the X position for cleaner drawing
      let pathRect = NSMakeRect(knobMarginRadius_Scaled,
                                knobMarginRadius_Scaled,
                                knobWidth * scaleFactor,
                                knobHeight * scaleFactor)
      let path = CGPath(roundedRect: pathRect, cornerWidth: knobCornerRadius_Scaled,
                        cornerHeight: knobCornerRadius_Scaled, transform: nil)

      if let shadow {
        cgContext.setShadow(offset: CGSize(width: 0, height: 0.5 * scaleFactor),
                            blur: 1 * scaleFactor, color: shadow)
      }
      cgContext.beginPath()
      cgContext.addPath(path)

      cgContext.setFillColor(fill.cgColor)
      cgContext.fillPath()

      if let shadow {
        /// According to Apple's docs for `NSShadow`: `The default shadow color is black with an alpha of 1/3`
        cgContext.beginPath()
        cgContext.addPath(path)
        cgContext.setLineWidth(0.4 * scaleFactor)
        cgContext.setStrokeColor(shadow)
        cgContext.strokePath()
      }
    }
    return knobImage
  }

  func loopKnobWidth(mainKnobWidth: CGFloat) -> CGFloat {
    return mainKnobWidth
  }

  func loopKnobHeight(mainKnobHeight: CGFloat) -> CGFloat {
    // We want loop knobs to be shorter than the primary knob.
    return round(mainKnobHeight * loopKnobHeightAdjustment)
  }

  func imageSize(knobWidth: CGFloat, knobHeight: CGFloat) -> CGSize {
    return CGSize(width: knobWidth + (2 * knobMarginRadius),
                  height: knobHeight + (2 * knobMarginRadius))
  }

  func imageSize(_ knob: Knob, _ knobType: KnobType) -> CGSize {
    switch knobType {
    case .mainKnob, .mainKnobSelected, .volumeKnob, .volumeKnobSelected:
      return imageSize(knobWidth: knob.knobWidth, knobHeight: knob.mainKnobHeight)
    case .loopKnob, .loopKnobSelected:
      let loopKnobHeight = loopKnobHeight(mainKnobHeight: knob.mainKnobHeight)
      return imageSize(knobWidth: knob.knobWidth, knobHeight: loopKnobHeight)
    }
  }

  func imgSizeScaled(knobWidth: CGFloat, knobHeight: CGFloat, scaleFactor: CGFloat) -> CGSize {
    let size = imageSize(knobWidth: knobWidth, knobHeight: knobHeight)
    return size.multiplyThenRound(scaleFactor)
  }

  struct Knob {
    let isDarkMode: Bool
    let hasClearBG: Bool
    let knobWidth: CGFloat
    let mainKnobHeight: CGFloat
    let image: CGImage
    let scaleFactor: CGFloat

    init(_ kf: KnobFactory, _ knobType: KnobType, isDarkMode: Bool, hasClearBG: Bool,
         knobWidth: CGFloat, mainKnobHeight: CGFloat, scaleFactor: CGFloat) {
      let loopKnobHeight = kf.loopKnobHeight(mainKnobHeight: mainKnobHeight)
      let shadowOrGlowColor = isDarkMode ? kf.glowColor : kf.shadowColor
      switch knobType {
      case .mainKnobSelected, .volumeKnobSelected:
        image = kf.makeImage(fill: kf.mainKnobActiveColor, shadow: shadowOrGlowColor,
                             knobWidth: knobWidth, knobHeight: mainKnobHeight, scaleFactor: scaleFactor)
      case .mainKnob, .volumeKnob:
        let shadowColor = hasClearBG ? kf.shadowColor : ((hasClearBG || !isDarkMode) ? kf.shadowColor : nil)
        image = kf.makeImage(fill: kf.mainKnobColor, shadow: shadowColor,
                             knobWidth: knobWidth, knobHeight: mainKnobHeight, scaleFactor: scaleFactor)
      case .loopKnob:
        image = kf.makeImage(fill: kf.loopKnobColor, shadow: nil,
                             knobWidth: knobWidth, knobHeight: loopKnobHeight, scaleFactor: scaleFactor)
      case .loopKnobSelected:
        image = isDarkMode ?
        kf.makeImage(fill: kf.mainKnobActiveColor, shadow: shadowOrGlowColor,
                     knobWidth: knobWidth, knobHeight: loopKnobHeight, scaleFactor: scaleFactor) :
        kf.makeImage(fill: kf.loopKnobColor, shadow: nil,
                     knobWidth: knobWidth, knobHeight: loopKnobHeight, scaleFactor: scaleFactor)
      }
      self.isDarkMode = isDarkMode
      self.hasClearBG = hasClearBG
      self.knobWidth = knobWidth
      self.mainKnobHeight = mainKnobHeight
      self.scaleFactor = scaleFactor
    }

  }  // end struct Knob

}
