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

  func drawBar(in barRect: NSRect, darkMode: Bool, clearBG: Bool, screen: NSScreen, knobMinX: CGFloat, knobWidth: CGFloat,
               progressRatio: CGFloat, durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)]) {
    var drawRect = Bar.imageRect(in: barRect)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }
    let bar = Bar(darkMode: darkMode, clearBG: clearBG, barWidth: barRect.width, screen: screen,
                  knobMinX: knobMinX, knobWidth: knobWidth, progressRatio: progressRatio,
                  durationSec: durationSec, chapters: chapters, cachedRanges: cachedRanges)
    NSGraphicsContext.current!.cgContext.draw(bar.image, in: drawRect)
  }

  struct Bar {
    static let baseChapterWidth: CGFloat = 3.0
    let image: CGImage

    /// `barWidth` does not include added leading or trailing margin
    init(darkMode: Bool, clearBG: Bool, barWidth: CGFloat, screen: NSScreen, knobMinX: CGFloat, knobWidth: CGFloat,
         progressRatio: CGFloat, durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)]) {
      image = Bar.makeImage(barWidth, screen: screen, darkMode: darkMode, clearBG: clearBG,
                            knobMinX: knobMinX, knobWidth: knobWidth, progressRatio: progressRatio,
                            durationSec: durationSec, chapters, cachedRanges: cachedRanges)
    }

    static func makeImage(_ barWidth: CGFloat, screen: NSScreen, darkMode: Bool, clearBG: Bool,
                          knobMinX: CGFloat, knobWidth: CGFloat, progressRatio: CGFloat,
                          durationSec: CGFloat, _ chapters: [MPVChapter], cachedRanges: [(Double, Double)]) -> CGImage {
      // - Set up calculations
      let scaleFactor = RenderCache.shared.scaleFactor
      let imgSizeScaled = Bar.imgSizeScaled(barWidth, scaleFactor: scaleFactor)
      let barWidth_Scaled = barWidth * scaleFactor
      let barHeight_Scaled = RenderCache.shared.barHeight * scaleFactor
      let cornerRadius_Scaled = RenderCache.shared.barCornerRadius_Scaled
      let leftColor = RenderCache.shared.barColorLeft.cgColor
      let rightColor = RenderCache.shared.barColorRight.cgColor
      let chapterGapWidth = Bar.baseChapterWidth * max(1.0, screen.screenScaleFactor * 0.5)
      let halfChapterGapWidth: CGFloat = chapterGapWidth * 0.5

      // - Will clip out the knob
      let leftClipMaxX = (knobMinX - 1) * scaleFactor
      let rightClipMinX = leftClipMaxX + (knobWidth * scaleFactor)
      assert(cornerRadius_Scaled * 2 <= knobWidth * scaleFactor, "Play bar corner radius is too wide: cannot clip using knob")

      let leftClip = CGRect(x: 0, y: 0,
                            width: leftClipMaxX,
                            height: imgSizeScaled.height)
      let rightClip = CGRect(x: rightClipMinX, y: 0,
                             width: imgSizeScaled.width - rightClipMinX,
                             height: imgSizeScaled.height)

      let barImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in
        // Apply clip (pixel whitelist)
        let minClippingWidth = cornerRadius_Scaled + RenderCache.shared.barMarginRadius_Scaled
        if !clearBG || (leftClip.width > minClippingWidth && rightClip.width > minClippingWidth) {
          if clearBG {
            // Knob is not drawn. Need to fill in the gap which was clipped out.
            cgc.resetClip()
            // Draw square bar(s). For some reason the CGPath below does not include the first & last pixels in CGRect,
            // so start on the clip boundary.
            let startX = leftClipMaxX
            let dividingPointX = RenderCache.shared.barMarginRadius_Scaled + (progressRatio * barWidth_Scaled)
            let endX = rightClipMinX
            let leftWidth = dividingPointX - startX
            if leftWidth > 0.0 {
              cgc.beginPath()
              let segment = CGRect(x: startX, y: RenderCache.shared.barMarginRadius_Scaled,
                                   width: leftWidth, height: barHeight_Scaled)
              cgc.addPath(CGPath(rect: segment, transform: nil))
              cgc.setFillColor(RenderCache.shared.barColorLeft.cgColor)
              cgc.fillPath()
            }
            let rightWidth = endX - dividingPointX
            if rightWidth > 0.0 {
              cgc.beginPath()
              let segment = CGRect(x: dividingPointX, y: RenderCache.shared.barMarginRadius_Scaled,
                                   width: rightWidth, height: barHeight_Scaled)
              cgc.addPath(CGPath(rect: segment, transform: nil))
              cgc.setFillColor(RenderCache.shared.barColorRight.cgColor)
              cgc.fillPath()
            }
          }

          cgc.clip(to: [leftClip, rightClip])
        }

        // Draw bar segments, with gaps to exclude knob & chapter markers
        func drawSeg(_ barColor: CGColor, minX: CGFloat, maxX: CGFloat) {
          cgc.beginPath()
          let adjMinX: CGFloat = minX + halfChapterGapWidth
          let adjMaxX: CGFloat = maxX - halfChapterGapWidth
          let segment = CGRect(x: adjMinX, y: RenderCache.shared.barMarginRadius_Scaled,
                               width: adjMaxX - adjMinX, height: barHeight_Scaled)
          cgc.addPath(CGPath(roundedRect: segment, cornerWidth:  cornerRadius_Scaled, cornerHeight:  cornerRadius_Scaled, transform: nil))
          cgc.setFillColor(barColor)
          cgc.fillPath()
        }

        // Note that nothing is drawn for leading knobMarginRadius_Scaled or trailing knobMarginRadius_Scaled.
        // The empty space exists to make image offset calculations consistent (thus easier) between knob & bar images.
        var segsMaxX: [Double]
        if chapters.count > 0, durationSec > 0 {
          segsMaxX = chapters[1...].map{ $0.startTime / durationSec * barWidth_Scaled }
        } else {
          segsMaxX = []
        }
        // Add right end of bar (don't forget to subtract left & right padding from img)
        let lastSegMaxX = imgSizeScaled.width - (RenderCache.shared.barMarginRadius_Scaled * 2)
        segsMaxX.append(lastSegMaxX)

        // Draw all rounded bar segments
        var isRightOfKnob = false
        var segMinX = RenderCache.shared.barMarginRadius_Scaled
        for segMaxX in segsMaxX {
          if isRightOfKnob {
            drawSeg(rightColor, minX: segMinX, maxX: segMaxX)
            segMinX = segMaxX  // for next loop
          } else if segMaxX > knobMinX {
            // (Check corner case: don't draw if no segment at all)
            if leftClipMaxX - segMinX > cornerRadius_Scaled {
              // Knob at least partially overlaps segment. Chop off segment at start of knob
              let finalCutoff = lastSegMaxX - (cornerRadius_Scaled * 3)
              if leftClipMaxX > finalCutoff {
                // Corner case: too close to right side. Drawing a rounded segment won't fit. Just fill to end.
                drawSeg(leftColor, minX: segMinX, maxX: lastSegMaxX)
                break
              }
              drawSeg(leftColor, minX: segMinX, maxX: leftClipMaxX + scaleFactor + scaleFactor)
            }
            isRightOfKnob = true
            segMinX = leftClipMaxX // for below

            // Any segment left over after the knob?
            if segMaxX > rightClipMinX {
              drawSeg(rightColor, minX: segMinX, maxX: segMaxX)
              segMinX = segMaxX  // for next loop
            }
          } else {
            // Left of knob
            drawSeg(leftColor, minX: segMinX, maxX: segMaxX)
            segMinX = segMaxX  // for next loop
          }
        }
      }  // end first img

      guard !cachedRanges.isEmpty else { return barImg }

      // Show cached ranges (if enabled)
      // Not sure how efficient this is...

      let cacheImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in
        if !clearBG {
          // Apply clip (pixel whitelist) to avoid drawing over the knob
          cgc.clip(to: [leftClip, rightClip])
        }

        let leftCachedColor = leftColor
        let rightCachedColor = exaggerateColor(rightColor)

        var isRightOfKnob = false
        var rectsLeft: [NSRect] = []
        var rectsRight: [NSRect] = []
        for cachedRange in cachedRanges.sorted(by: { $0.0 < $1.0 }) {
          let startX: CGFloat = cachedRange.0 / durationSec * barWidth_Scaled
          let endX: CGFloat = cachedRange.1 / durationSec * barWidth_Scaled
          if isRightOfKnob || startX > leftClipMaxX {
            isRightOfKnob = true
            rectsRight.append(CGRect(x: startX, y: RenderCache.shared.barMarginRadius_Scaled,
                                     width: endX - startX, height: barHeight_Scaled))
          } else if endX > leftClipMaxX {
            isRightOfKnob = true
            rectsLeft.append(CGRect(x: startX, y: RenderCache.shared.barMarginRadius_Scaled,
                                    width: leftClipMaxX - startX, height: barHeight_Scaled))

            let start2ndX = leftClipMaxX
            rectsRight.append(CGRect(x: start2ndX, y: RenderCache.shared.barMarginRadius_Scaled,
                                     width: endX - start2ndX, height: barHeight_Scaled))
          } else {
            rectsLeft.append(CGRect(x: startX, y: RenderCache.shared.barMarginRadius_Scaled,
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
