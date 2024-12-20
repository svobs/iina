//
//  RenderCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//  Copyright © 2024 lhc. All rights reserved.
//


/// In the future, the sliders should be entirely custom, instead of relying on legacy `NSSlider`. Then the knob & slider can be
/// implemented via their own separate `CALayer`s which should enable more optimization opportunities. It's not been tested whether drawing
/// into (possibly cached) `CGImage`s as this class currently does delivers any improved performance (or is even slower)...
class RenderCache {
  static let shared = RenderCache()

  /// This should match `backingScaleFactor` from the current screen. At present
  /// (MacOS 15.1), this will always be `2.0`.
  let scaleFactor: CGFloat = 2.0

  // MARK: - Knob

  enum KnobType: Int {
    case mainKnob = 0
    case mainKnobSelected
    case loopKnob
    case loopKnobSelected
    case volumeKnob
    case volumeKnobSelected
  }

  init() {
    knobMarginRadius_Scaled = knobMarginRadius * scaleFactor
    barCornerRadius_Scaled = barCornerRadius * scaleFactor
    barMarginRadius_Scaled = barMarginRadius * scaleFactor
  }

  // - Knob Constants

  let knobMarginRadius: CGFloat = 1.0
  /// Need a tiny amount of margin on all sides to allow for shadow and/or antialiasing
  var knobMarginRadius_Scaled: CGFloat
  let knobCornerRadius: CGFloat = 1

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

  func getKnob(_ knobType: KnobType, darkMode: Bool, clearBG: Bool,
               knobWidth: CGFloat, mainKnobHeight: CGFloat) -> Knob {
    if let cachedKnob = cachedKnobs[knobType.rawValue], cachedKnob.isDarkMode == darkMode,
       cachedKnob.knobWidth == knobWidth, cachedKnob.mainKnobHeight == mainKnobHeight {
      return cachedKnob
    }
    // There may some minor loss due to races, but it will settle quickly. Don't need lousy locksss
    let knob = Knob(knobType, isDarkMode: darkMode, isClearBG: clearBG,
                    knobWidth: knobWidth, mainKnobHeight: mainKnobHeight)
    cachedKnobs[knobType.rawValue] = knob
    return knob
  }

  func getKnobImage(_ knobType: KnobType, darkMode: Bool, clearBG: Bool,
                    knobWidth: CGFloat, mainKnobHeight: CGFloat) -> CGImage {
    return getKnob(knobType, darkMode: darkMode, clearBG: clearBG,
                   knobWidth: knobWidth, mainKnobHeight: mainKnobHeight).image
  }

  func drawKnob(_ knobType: KnobType, in knobRect: NSRect, darkMode: Bool, clearBG: Bool,
                knobWidth: CGFloat, mainKnobHeight: CGFloat) {
    let knob = getKnob(knobType, darkMode: darkMode, clearBG: clearBG,
                       knobWidth: knobWidth, mainKnobHeight: mainKnobHeight)

    let image = knob.image

    let knobHeightAdj = knobType == .loopKnob ? knob.loopKnobHeight : knob.mainKnobHeight
    let knobImageSize = Knob.imageSize(knobWidth: knobWidth, knobHeight: knobHeightAdj)
    let drawRect = NSRect(x: round(knobRect.origin.x) - RenderCache.shared.knobMarginRadius,
                          y: knobRect.origin.y - RenderCache.shared.knobMarginRadius + (0.5 * (knobRect.height - knobHeightAdj)),
                          width: knobImageSize.width, height: knobImageSize.height)
    NSGraphicsContext.current!.cgContext.draw(image, in: drawRect)
  }

  struct Knob {

    /// Percentage of the height of the primary knob to use for the loop knobs when drawing.
    ///
    /// The height of loop knobs is reduced in order to give prominence to the slider's knob that controls the playback position.
    static let loopKnobHeightAdjustment: CGFloat = 0.75

    let isDarkMode: Bool
    let isClearBG: Bool
    let knobWidth: CGFloat
    let mainKnobHeight: CGFloat
    let image: CGImage

    init(_ knobType: KnobType, isDarkMode: Bool, isClearBG: Bool, knobWidth: CGFloat, mainKnobHeight: CGFloat) {
      let loopKnobHeight = Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
      let shadowOrGlowColor = isDarkMode ? RenderCache.shared.glowColor : RenderCache.shared.shadowColor
      switch knobType {
      case .mainKnobSelected, .volumeKnobSelected:
        image = Knob.makeImage(fill: RenderCache.shared.mainKnobActiveColor, shadow: shadowOrGlowColor,
                                knobWidth: knobWidth, knobHeight: mainKnobHeight)
      case .mainKnob, .volumeKnob:
        let shadowColor = isClearBG ? RenderCache.shared.shadowColor : (isDarkMode ? nil : RenderCache.shared.shadowColor)
        image = Knob.makeImage(fill: RenderCache.shared.mainKnobColor, shadow: shadowColor,
                                   knobWidth: knobWidth, knobHeight: mainKnobHeight)
      case .loopKnob:
        image = Knob.makeImage(fill: RenderCache.shared.loopKnobColor, shadow: nil,
                                         knobWidth: knobWidth, knobHeight: loopKnobHeight)
      case .loopKnobSelected:
        image = isDarkMode ?
        Knob.makeImage(fill: RenderCache.shared.mainKnobActiveColor, shadow: shadowOrGlowColor,
                       knobWidth: knobWidth, knobHeight: loopKnobHeight) :
        Knob.makeImage(fill: RenderCache.shared.loopKnobColor, shadow: nil,
                       knobWidth: knobWidth, knobHeight: loopKnobHeight)
      }
      self.isDarkMode = isDarkMode
      self.isClearBG = isClearBG
      self.knobWidth = knobWidth
      self.mainKnobHeight = mainKnobHeight
    }

    static func makeImage(fill: NSColor, shadow: CGColor?, knobWidth: CGFloat, knobHeight: CGFloat) -> CGImage {
      let scaleFactor = RenderCache.shared.scaleFactor
      let knobImageSizeScaled = Knob.imgSizeScaled(knobWidth: knobWidth, knobHeight: knobHeight, scaleFactor: scaleFactor)
      let knobImage = CGImage.buildBitmapImage(width: knobImageSizeScaled.widthInt,
                                               height: knobImageSizeScaled.heightInt) { cgContext in

        // Round the X position for cleaner drawing
        let pathRect = NSMakeRect(RenderCache.shared.knobMarginRadius_Scaled,
                                  RenderCache.shared.knobMarginRadius_Scaled,
                                  knobWidth * scaleFactor,
                                  knobHeight * scaleFactor)
        let path = CGPath(roundedRect: pathRect, cornerWidth: RenderCache.shared.knobCornerRadius * scaleFactor,
                          cornerHeight: RenderCache.shared.knobCornerRadius * scaleFactor, transform: nil)

        if let shadow {
          cgContext.setShadow(offset: CGSize(width: 0, height: 0.5 * scaleFactor), blur: 1 * scaleFactor, color: shadow)
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

    var loopKnobHeight: CGFloat {
      Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
    }

    func imageSize(_ knobType: KnobType) -> CGSize {
      switch knobType {
      case .mainKnob, .mainKnobSelected, .volumeKnob, .volumeKnobSelected:
        return Knob.imageSize(knobWidth: knobWidth, knobHeight: mainKnobHeight)
      case .loopKnob, .loopKnobSelected:
        let loopKnobHeight = Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
        return Knob.imageSize(knobWidth: knobWidth, knobHeight: loopKnobHeight)
      }
    }

    static func loopKnobHeight(mainKnobHeight: CGFloat) -> CGFloat {
      // We want loop knobs to be shorter than the primary knob.
      return round(mainKnobHeight * Knob.loopKnobHeightAdjustment)
    }

    static func imageSize(knobWidth: CGFloat, knobHeight: CGFloat) -> CGSize {
      return CGSize(width: knobWidth + (2 * RenderCache.shared.knobMarginRadius),
                    height: knobHeight + (2 * RenderCache.shared.knobMarginRadius))
    }

    static func imgSizeScaled(knobWidth: CGFloat, knobHeight: CGFloat, scaleFactor: CGFloat) -> CGSize {
      let size = imageSize(knobWidth: knobWidth, knobHeight: knobHeight)
      return size.multiplyThenRound(scaleFactor)
    }
  }  // end struct Knob

  // MARK: - Bar

  // Bar
  let barHeight: CGFloat = 3.0
  let barCornerRadius: CGFloat = 1.5
  var barCornerRadius_Scaled: CGFloat
  var barColorLeft = NSColor.controlAccentColor
  var barColorRight = NSColor.mainSliderBarRight
  let barMarginRadius: CGFloat = 1.0
  var barMarginRadius_Scaled: CGFloat

  func updateBarColorsFromPrefs() {
    let userSetting: Preference.SliderBarLeftColor = Preference.enum(for: .playSliderBarLeftColor)
    switch userSetting {
    case .gray:
      barColorLeft = NSColor.mainSliderBarLeft
    default:
      barColorLeft = NSColor.controlAccentColor
    }
  }

  func drawPlayBar(in barRect: NSRect, barHeight: CGFloat,
                   darkMode: Bool, clearBG: Bool, screen: NSScreen,
                   knobMinX: CGFloat, knobWidth: CGFloat,
                   progressRatio: CGFloat, durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)]) {
//    assert(barHeight <= barRect.height, "barHeight \(barHeight) > barRect.height \(barRect.height)")
    var drawRect = Bar.imageRect(in: barRect)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }
    let bar = Bar(darkMode: darkMode, clearBG: clearBG, barWidth: barRect.width, barHeight: barHeight, screen: screen,
                  knobMinX: knobMinX, knobWidth: knobWidth, progressRatio: progressRatio,
                  durationSec: durationSec, chapters: chapters, cachedRanges: cachedRanges)
    NSGraphicsContext.current!.cgContext.draw(bar.image, in: drawRect)
  }

  func drawVolumeBar(in barRect: NSRect, barHeight: CGFloat,
                     darkMode: Bool, clearBG: Bool, knobMinX: CGFloat, knobWidth: CGFloat,
                     currentValue: CGFloat, maxValue: CGFloat) {
//    assert(barHeight <= barRect.height, "barHeight \(barHeight) > barRect.height \(barRect.height)")
    var drawRect = Bar.imageRect(in: barRect)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }
    let volBar = VolumeBar(darkMode: darkMode, clearBG: clearBG, barWidth: barRect.width, barHeight: barHeight,
                           knobMinX: knobMinX, knobWidth: knobWidth,
                           currentValue: currentValue, maxValue: maxValue)
    NSGraphicsContext.current!.cgContext.draw(volBar.image, in: drawRect)
  }

  struct VolumeBar {
    let image: CGImage

    /// `barWidth` does not include added leading or trailing margin
    init(darkMode: Bool, clearBG: Bool, barWidth: CGFloat, barHeight: CGFloat,
         knobMinX: CGFloat, knobWidth: CGFloat,
         currentValue: Double, maxValue: Double) {
      image = VolumeBar.makeImage(darkMode: darkMode, clearBG: clearBG, barWidth: barWidth, barHeight: barHeight,
                                  knobMinX: knobMinX, knobWidth: knobWidth,
                                  currentValue: currentValue, maxValue: maxValue)
    }

    static func makeImage(darkMode: Bool, clearBG: Bool,
                          barWidth: CGFloat, barHeight: CGFloat,
                          knobMinX: CGFloat, knobWidth: CGFloat,
                          currentValue: Double, maxValue: Double) -> CGImage {
      // - Set up calculations
      let rc = RenderCache.shared
      let scaleFactor = rc.scaleFactor
      let imgSizeScaled = Bar.imgSizeScaled(barWidth, scaleFactor: scaleFactor)
      let barWidth_Scaled = barWidth * scaleFactor
      let barHeight_Scaled = barHeight * scaleFactor
      let outerPaddingScaled = rc.barMarginRadius_Scaled
      let leftColor = rc.barColorLeft.cgColor
      let rightColor = rc.barColorRight.cgColor
      let barMinX = outerPaddingScaled
      let barMaxX = imgSizeScaled.width - (outerPaddingScaled * 2)

      let currentValueRatio = currentValue / maxValue
      let dividingPointX = (outerPaddingScaled + (currentValueRatio * barWidth_Scaled)).rounded()

      // Determine clipping rects (pixel whitelists)
      let leftClipMaxX: CGFloat
      let rightClipMinX: CGFloat
      if clearBG {
        leftClipMaxX = dividingPointX
        rightClipMinX = dividingPointX
      } else {
        // - Will clip out the knob
        leftClipMaxX = (knobMinX - 1) * scaleFactor
        rightClipMinX = leftClipMaxX + (knobWidth * scaleFactor)
      }

      let hasLeft = leftClipMaxX - outerPaddingScaled > 0.0
      let hasRight = rightClipMinX + outerPaddingScaled < imgSizeScaled.width

      let barImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in
        if hasLeft {
          let leftClipRect = CGRect(x: 0, y: 0,
                                    width: leftClipMaxX,
                                    height: imgSizeScaled.height)
          // Left of knob
          cgc.resetClip()
          cgc.clip(to: leftClipRect)
          rc.addPillPath(cgc, minX: barMinX,
                         maxX: barMaxX,
                         interPillGapWidth: 0,
                         height: barHeight_Scaled,
                         leftEdge: .noBorderingPill,
                         rightEdge: .noBorderingPill)
          cgc.clip()

          rc.drawPill(cgc, leftColor,
                      minX: barMinX,
                      maxX: barMaxX,
                      interPillGapWidth: 0,
                      height: barHeight_Scaled,
                      leftEdge: .noBorderingPill,
                      rightEdge: .noBorderingPill)
        }

        if hasRight {
          let rightClipRect = CGRect(x: rightClipMinX, y: 0,
                                     width: imgSizeScaled.width - rightClipMinX,
                                     height: imgSizeScaled.height)
          cgc.resetClip()
          cgc.clip(to: rightClipRect)
          rc.addPillPath(cgc, minX: barMinX,
                         maxX: barMaxX,
                         interPillGapWidth: 0,
                         height: barHeight_Scaled,
                         leftEdge: .noBorderingPill,
                         rightEdge: .noBorderingPill)
          cgc.clip()

          rc.drawPill(cgc, rightColor,
                      minX: barMinX,
                      maxX: barMaxX,
                      interPillGapWidth: 0,
                      height: barHeight_Scaled,
                      leftEdge: .noBorderingPill,
                      rightEdge: .noBorderingPill)
        }
      }

      return barImg
    }
  }  /// end `struct VolumeBar`

  struct Bar {
    static let baseChapterWidth: CGFloat = 3.0
    let image: CGImage

    /// `barWidth` does not include added leading or trailing margin
    init(darkMode: Bool, clearBG: Bool, barWidth: CGFloat, barHeight: CGFloat,
         screen: NSScreen, knobMinX: CGFloat, knobWidth: CGFloat,
         progressRatio: CGFloat, durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)]) {
      image = Bar.makeImage(barWidth: barWidth, barHeight: barHeight,
                            screen: screen, darkMode: darkMode, clearBG: clearBG,
                            knobMinX: knobMinX, knobWidth: knobWidth, currentValueRatio: progressRatio,
                            durationSec: durationSec, chapters, cachedRanges: cachedRanges)
    }

    static func makeImage(barWidth: CGFloat, barHeight: CGFloat,
                          screen: NSScreen, darkMode: Bool, clearBG: Bool,
                          knobMinX: CGFloat, knobWidth: CGFloat, currentValueRatio: CGFloat,
                          durationSec: CGFloat, _ chapters: [MPVChapter], cachedRanges: [(Double, Double)]) -> CGImage {
      // - Set up calculations
      let rc = RenderCache.shared
      let scaleFactor = rc.scaleFactor
      let imgSizeScaled = Bar.imgSizeScaled(barWidth, scaleFactor: scaleFactor)
      let barWidth_Scaled = barWidth * scaleFactor
      let barHeight_Scaled = barHeight * scaleFactor
      let outerPaddingScaled = rc.barMarginRadius_Scaled
      let leftColor = rc.barColorLeft.cgColor
      let rightColor = rc.barColorRight.cgColor
      let chapterGapWidth = (Bar.baseChapterWidth * max(1.0, screen.screenScaleFactor * 0.5)).rounded()
      let dividingPointX = (outerPaddingScaled + (currentValueRatio * barWidth_Scaled)).rounded()

      // Determine clipping rects (pixel whitelists)
      let leftClipMaxX: CGFloat
      let rightClipMinX: CGFloat
      if clearBG {
        leftClipMaxX = dividingPointX
        rightClipMinX = dividingPointX
      } else {
        // - Will clip out the knob
        leftClipMaxX = (knobMinX - 1) * scaleFactor
        rightClipMinX = leftClipMaxX + (knobWidth * scaleFactor)
      }

      let hasLeft = leftClipMaxX - outerPaddingScaled > 0.0
      let hasRight = rightClipMinX + outerPaddingScaled < imgSizeScaled.width

      let leftClipRect = CGRect(x: 0, y: 0,
                                width: leftClipMaxX,
                                height: imgSizeScaled.height)

      let rightClipRect = CGRect(x: rightClipMinX, y: 0,
                                 width: imgSizeScaled.width - rightClipMinX,
                                 height: imgSizeScaled.height)

      let barImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in

        // Note that nothing is drawn for leading knobMarginRadius_Scaled or trailing knobMarginRadius_Scaled.
        // The empty space exists to make image offset calculations consistent (thus easier) between knob & bar images.
        var segsMaxX: [Double]
        if chapters.count > 0, durationSec > 0 {
          segsMaxX = chapters[1...].map{ $0.startTime / durationSec * barWidth_Scaled }
        } else {
          segsMaxX = []
        }
        // Add right end of bar (don't forget to subtract left & right padding from img)
        let lastSegMaxX = imgSizeScaled.width - (outerPaddingScaled * 2)
        segsMaxX.append(lastSegMaxX)

        var segIndex = 0
        var segMinX = outerPaddingScaled

        var leftEdge: PillEdgeType = .noBorderingPill
        var rightEdge: PillEdgeType = .bordersAnotherPill

        if hasLeft {
          // Left of knob
          cgc.resetClip()
          cgc.clip(to: leftClipRect)

          var done = false
          while !done && segIndex < segsMaxX.count {
            let segMaxX = segsMaxX[segIndex]

            if segIndex == segsMaxX.count - 1 {
              // Is last pill
              rightEdge = .noBorderingPill
              done = true
            } else if segMaxX > leftClipMaxX || segMinX > leftClipMaxX {
              // Round the image corners by clipping out all drawing which is not in roundedRect (like using a stencil)
              rc.addPillPath(cgc, minX: segMinX,
                             maxX: segMaxX,
                             interPillGapWidth: chapterGapWidth,
                             height: barHeight_Scaled,
                             leftEdge: leftEdge,
                             rightEdge: rightEdge)
              cgc.clip()
              done = true
            }
            rc.drawPill(cgc, leftColor,
                        minX: segMinX, maxX: segMaxX,
                        interPillGapWidth: chapterGapWidth,
                        height: barHeight_Scaled,
                        leftEdge: leftEdge,
                        rightEdge: rightEdge)

            // Set for all but first pill
            leftEdge = .bordersAnotherPill

            if !done {
              // Advance for next loop
              segMinX = segMaxX
              segIndex += 1
            }
          }
        }

        if hasRight {
          // Right of knob (or just unfinished progress, if no knob)
          cgc.resetClip()
          cgc.clip(to: rightClipRect)

          while segIndex < segsMaxX.count {
            let segMaxX = segsMaxX[segIndex]

            if segIndex == segsMaxX.count - 1 {
              rightEdge = .noBorderingPill
            }

            rc.drawPill(cgc, rightColor,
                        minX: segMinX, maxX: segMaxX,
                        interPillGapWidth: chapterGapWidth,
                        height: barHeight_Scaled,
                        leftEdge: leftEdge,
                        rightEdge: rightEdge)

            segIndex += 1
            // For next loop
            segMinX = segMaxX
            leftEdge = .bordersAnotherPill
          }
        }

      }  // end first img

      guard !cachedRanges.isEmpty else { return barImg }

      // Show cached ranges (if enabled)
      // Not sure how efficient this is...

      let cacheImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in
        if !clearBG {
          // Apply clip (pixel whitelist) to avoid drawing over the knob
          cgc.clip(to: [leftClipRect, rightClipRect])
        }

        let leftCachedColor = exaggerateColor(leftColor)
        let rightCachedColor = exaggerateColor(rightColor)

        var rectsLeft: [NSRect] = []
        var rectsRight: [NSRect] = []
        for cachedRange in cachedRanges.sorted(by: { $0.0 < $1.0 }) {
          let startX: CGFloat = cachedRange.0 / durationSec * barWidth_Scaled
          let endX: CGFloat = cachedRange.1 / durationSec * barWidth_Scaled
          if startX > leftClipMaxX {
            rectsRight.append(CGRect(x: startX, y: outerPaddingScaled,
                                     width: endX - startX, height: barHeight_Scaled))
          } else if endX > leftClipMaxX {
            rectsLeft.append(CGRect(x: startX, y: outerPaddingScaled,
                                    width: leftClipMaxX - startX, height: barHeight_Scaled))

            let start2ndX = leftClipMaxX
            rectsRight.append(CGRect(x: start2ndX, y: outerPaddingScaled,
                                     width: endX - start2ndX, height: barHeight_Scaled))
          } else {
            rectsLeft.append(CGRect(x: startX, y: outerPaddingScaled,
                                    width: endX - startX, height: barHeight_Scaled))
          }
        }

        cgc.setFillColor(leftCachedColor)
        cgc.fill(rectsLeft)
        cgc.setFillColor(rightCachedColor)
        cgc.fill(rectsRight)

        cgc.setBlendMode(.destinationIn)
        cgc.draw(barImg, in: CGRect(origin: .zero, size: imgSizeScaled))
      }

      let compositeImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt,
                                                  height: imgSizeScaled.heightInt) { cgc in
        cgc.setBlendMode(.normal)
        cgc.draw(barImg, in: CGRect(origin: .zero, size: imgSizeScaled))
        cgc.setBlendMode(.overlay)
        cgc.draw(cacheImg, in: CGRect(origin: .zero, size: imgSizeScaled))
        cgc.setBlendMode(.normal)
      }
      return compositeImg
    }

    private static func exaggerateColor(_ baseColor: CGColor) -> CGColor {
      var leftCacheComps: [CGFloat] = []
      let numComponents = min(baseColor.numberOfComponents, 3)
      for i in 0..<numComponents {
        leftCacheComps.append(min(1.0, baseColor.components![i] * 1.8))
      }
      leftCacheComps.append(1.0)
      let colorSpace = baseColor.colorSpace ?? CGColorSpaceCreateDeviceRGB()
      return CGColor(colorSpace: colorSpace, components: leftCacheComps)!
    }

    /// Measured in points, not pixels!
    static func imageRect(in drawRect: CGRect) -> CGRect {
      let margin = RenderCache.shared.barMarginRadius
      let imgHeight = (2 * margin) + RenderCache.shared.barHeight
      // can be negative:
      let spareHeight = drawRect.height - imgHeight
      let y = drawRect.origin.y + (spareHeight * 0.5)
      return CGRect(x: drawRect.origin.x - margin, y: y,
                    width: drawRect.width + (2 * margin), height: imgHeight)
    }

    static func imgSizeScaled(_ barWidth: CGFloat, scaleFactor: CGFloat) -> CGSize {
      let marginPairSum = (2 * RenderCache.shared.barMarginRadius)
      let size = CGSize(width: barWidth + marginPairSum, height: marginPairSum + RenderCache.shared.barHeight)
      return size.multiplyThenRound(scaleFactor)
    }
  }  /// end `struct Bar`

}
