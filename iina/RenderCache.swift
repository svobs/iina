//
//  RenderCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//  Copyright © 2024 lhc. All rights reserved.
//


class RenderCache {
  static let shared = RenderCache()
  static let scaleFactor: CGFloat = 2.0
  static let imgMarginRadius: CGFloat = 1.0

  enum ImageType: Int {
    case mainKnob = 1
    case mainKnobSelected
    case loopKnob
    case loopKnobSelected
  }

  // Bar
  let barHeight: CGFloat = 3.0
  let barCornerRadius_Scaled: CGFloat = 1.5 * scaleFactor
  var barColorLeft = NSColor.controlAccentColor
  var barColorLeftGlow = NSColor.controlAccentColor
  var barColorPreCache = NSColor(named: .mainSliderBarPreCache)!
  var barColorRight = NSColor(named: .mainSliderBarRight)!
  var chapterStrokeColor = NSColor(named: .mainSliderBarChapterStroke)!

  // Knob
  let mainKnobColorDefault = NSColor(named: .mainSliderKnob)!
  let mainKnobActiveColorDefault = NSColor(named: .mainSliderKnobActive)!
  var mainKnobColor = NSColor(named: .mainSliderKnob)!
  var mainKnobActiveColor = NSColor(named: .mainSliderKnobActive)!
  var loopKnobColor = NSColor(named: .mainSliderLoopKnob)!
  /// Need a tiny amount of margin on all sides to allow for shadow and/or antialiasing
  let scaledMarginRadius = RenderCache.imgMarginRadius * RenderCache.scaleFactor
  let knobCornerRadius: CGFloat = 1
  let shadowColor = NSShadow().shadowColor!.cgColor
  let glowColor = NSColor.white.withAlphaComponent(1.0/3.0).cgColor

  // MARK: - Knob

  func getKnob(darkMode: Bool, knobWidth: CGFloat, mainKnobHeight: CGFloat) -> Knob {
    let knob: Knob
    if let cachedKnob, cachedKnob.isDarkMode == darkMode, cachedKnob.knobWidth == knobWidth, cachedKnob.mainKnobHeight == mainKnobHeight {
      knob = cachedKnob
    } else {
      knob = Knob(isDarkMode: darkMode, knobWidth: knobWidth, mainKnobHeight: mainKnobHeight)
      cachedKnob = knob
    }
    return knob
  }

  func getKnobImage(_ knobType: ImageType, darkMode: Bool,
                    knobWidth: CGFloat, mainKnobHeight: CGFloat) -> CGImage {
    let knob = getKnob(darkMode: darkMode, knobWidth: knobWidth, mainKnobHeight: mainKnobHeight)
    return knob.images[knobType]!
  }

  func drawKnob(_ knobType: ImageType, in knobRect: NSRect, darkMode: Bool,
                knobWidth: CGFloat, mainKnobHeight: CGFloat) {
    let knob = getKnob(darkMode: darkMode, knobWidth: knobWidth, mainKnobHeight: mainKnobHeight)

    let image = knob.images[knobType]!

    let knobHeightAdj = knobType == .loopKnob ? knob.loopKnobHeight : knob.mainKnobHeight
    let knobImageSize = Knob.imageSize(knobWidth: knobWidth, knobHeight: knobHeightAdj)
    let drawRect = NSRect(x: round(knobRect.origin.x) - RenderCache.imgMarginRadius,
                          y: knobRect.origin.y - RenderCache.imgMarginRadius + (0.5 * (knobRect.height - knobHeightAdj)),
                          width: knobImageSize.width, height: knobImageSize.height)
    NSGraphicsContext.current!.cgContext.draw(image, in: drawRect)
  }

  struct Knob {

    /// Percentage of the height of the primary knob to use for the loop knobs when drawing.
    ///
    /// The height of loop knobs is reduced in order to give prominence to the slider's knob that controls the playback position.
    static let loopKnobHeightAdjustment: CGFloat = 0.75

    let images: [ImageType: CGImage]
    let isDarkMode: Bool
    let knobWidth: CGFloat
    let mainKnobHeight: CGFloat

    init(isDarkMode: Bool, knobWidth: CGFloat, mainKnobHeight: CGFloat) {
      let loopKnobHeight = Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
      let shadowColor = isDarkMode ? RenderCache.shared.glowColor : RenderCache.shared.shadowColor
      images = [.mainKnobSelected:
                  Knob.makeImage(fill: RenderCache.shared.mainKnobActiveColor, shadow: shadowColor,
                                 knobWidth: knobWidth, knobHeight: mainKnobHeight),
                .mainKnob:
                  Knob.makeImage(fill: RenderCache.shared.mainKnobColor, shadow: isDarkMode ? nil : shadowColor,
                                 knobWidth: knobWidth, knobHeight: mainKnobHeight),
                .loopKnob:
                  Knob.makeImage(fill: RenderCache.shared.loopKnobColor, shadow: nil,
                                 knobWidth: knobWidth, knobHeight: loopKnobHeight),
                .loopKnobSelected:
                  isDarkMode ?
                Knob.makeImage(fill: RenderCache.shared.mainKnobActiveColor, shadow: shadowColor,
                               knobWidth: knobWidth, knobHeight: loopKnobHeight) :
                  Knob.makeImage(fill: RenderCache.shared.loopKnobColor, shadow: nil,
                                 knobWidth: knobWidth, knobHeight: loopKnobHeight)
      ]
      self.isDarkMode = isDarkMode
      self.knobWidth = knobWidth
      self.mainKnobHeight = mainKnobHeight
    }

    static func makeImage(fill: NSColor, shadow: CGColor?, knobWidth: CGFloat, knobHeight: CGFloat) -> CGImage {
      let scaleFactor = RenderCache.scaleFactor
      let knobImageSizeScaled = Knob.imgSizeScaled(knobWidth: knobWidth, knobHeight: knobHeight, scaleFactor: scaleFactor)
      let knobImage = CGImage.buildBitmapImage(width: knobImageSizeScaled.widthInt,
                                               height: knobImageSizeScaled.heightInt,
                                               drawingCalls: { cgContext in

        // Round the X position for cleaner drawing
        let pathRect = NSMakeRect(RenderCache.shared.scaledMarginRadius,
                                  RenderCache.shared.scaledMarginRadius,
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
      })!
      return knobImage
    }

    var loopKnobHeight: CGFloat {
      Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
    }

    func imageSize(_ knobType: ImageType) -> CGSize {
      switch knobType {
      case .mainKnob, .mainKnobSelected:
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
      return CGSize(width: knobWidth + (2 * RenderCache.imgMarginRadius),
                    height: knobHeight + (2 * RenderCache.imgMarginRadius))
    }

    static func imgSizeScaled(knobWidth: CGFloat, knobHeight: CGFloat, scaleFactor: CGFloat) -> CGSize {
      let size = imageSize(knobWidth: knobWidth, knobHeight: knobHeight)
      return size.multiplyThenRound(scaleFactor)
    }
  }  // end struct Knob

  var cachedKnob: Knob? = nil

  // MARK: - Bar

  func updateBarColorsFromPrefs() {
    let userSetting: Preference.SliderBarLeftColor = Preference.enum(for: .playSliderBarLeftColor)
    switch userSetting {
    case .gray:
      barColorLeft = NSColor(named: .mainSliderBarLeft)!
    default:
      barColorLeft = NSColor.controlAccentColor
    }
    barColorLeftGlow = barColorLeft.withAlphaComponent(0.5)
  }

  func drawBar(in barRect: NSRect, darkMode: Bool, screen: NSScreen, knobMinX: CGFloat, knobWidth: CGFloat,
               durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)]) {
    var drawRect = Bar.imageRect(in: barRect)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }
    let bar = Bar(darkMode: darkMode, barWidth: barRect.width, screen: screen, knobMinX: knobMinX, knobWidth: knobWidth,
                  durationSec: durationSec, chapters: chapters, cachedRanges: cachedRanges)
    NSGraphicsContext.current!.cgContext.draw(bar.image, in: drawRect)
  }

  struct Bar {
    static let baseChapterWidth: CGFloat = 3.0
    static let imgMarginRadius: CGFloat = 1.0
    static let scaledMarginRadius = imgMarginRadius * RenderCache.scaleFactor
    let image: CGImage

    /// `barWidth` does not include added leading or trailing margin
    init(darkMode: Bool, barWidth: CGFloat, screen: NSScreen, knobMinX: CGFloat, knobWidth: CGFloat,
         durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)]) {
      image = Bar.makeImage(barWidth, screen: screen, darkMode: darkMode, knobMinX: knobMinX, knobWidth: knobWidth,
                            durationSec: durationSec, chapters, cachedRanges: cachedRanges)
    }

    static func makeImage(_ barWidth: CGFloat, screen: NSScreen, darkMode: Bool, knobMinX: CGFloat, knobWidth: CGFloat,
                          durationSec: CGFloat, _ chapters: [MPVChapter], cachedRanges: [(Double, Double)]) -> CGImage {
      let scaleFactor = RenderCache.scaleFactor
      let imgSizeScaled = Bar.imgSizeScaled(barWidth, scaleFactor: scaleFactor)

      return CGImage.buildBitmapImage(width: imgSizeScaled.widthInt,
                                      height: imgSizeScaled.heightInt,
                                      drawingCalls: { cgc in

        // - Set up calculations
        let barWidth_Scaled = barWidth * scaleFactor
        let barHeight_Scaled = RenderCache.shared.barHeight * scaleFactor
        let cornerRadius_Scaled = RenderCache.shared.barCornerRadius_Scaled
        let leftColor = RenderCache.shared.barColorLeft.cgColor
        let rightColor = RenderCache.shared.barColorRight.cgColor
        let chapterGapWidth = Bar.baseChapterWidth * max(1.0, screen.screenScaleFactor * 0.5)
        let halfChapterGapWidth = chapterGapWidth * 0.5
//        let baseChapterStartOffset = (chapterGapWidth * 0.5)
//        let baseChapterEndOffset = (chapterGapWidth * 0.5)

//        var cachedRects: [CGRect] = []
//        for cachedRange in cachedRanges {
//          let startX = baseChapterStartOffset + (cachedRange.0 / durationSec * barWidth_Scaled)
//          let endX = baseChapterEndOffset + (cachedRange.1 / durationSec * barWidth_Scaled)
//          cachedRects.append(CGRect(x: startX, y: Bar.scaledMarginRadius, width: endX - startX, height: barHeight_Scaled))
//        }

        // Clip where the knob will be
        let leftClipMaxX = knobMinX * scaleFactor
        let knobWidth_Scaled = knobWidth * scaleFactor
        let rightClipMinX = leftClipMaxX + knobWidth_Scaled - (2 * scaleFactor)
        assert(cornerRadius_Scaled * 2 <= knobWidth_Scaled, "BarStrokeRadius too thick to clip around knob!")
        var isRightOfKnob = false
        // Apply clip (pixel whitelist)
        let barClipLeft = CGRect(x: 0, y: 0,
                                 width: leftClipMaxX, height: imgSizeScaled.height)
        let barClipRight = CGRect(x: rightClipMinX, y: 0,
                                  width: imgSizeScaled.width - rightClipMinX, height: imgSizeScaled.height)
        cgc.clip(to: [barClipLeft, barClipRight])

        // Draw bar segments, with gaps to exclude knob & chapter markers
        func drawSeg(_ barColor: CGColor, minX: CGFloat, maxX: CGFloat) {
          cgc.beginPath()
          let adjMinX = minX + halfChapterGapWidth
          let adjMaxX = maxX - halfChapterGapWidth
          let segment = CGRect(x: adjMinX, y: Bar.scaledMarginRadius, width: adjMaxX - adjMinX, height: barHeight_Scaled)
          cgc.addPath(CGPath(roundedRect: segment, cornerWidth:  cornerRadius_Scaled, cornerHeight:  cornerRadius_Scaled, transform: nil))
          cgc.setFillColor(barColor)
          cgc.fillPath()
        }

        // Note that nothing is drawn in leading or trailing Bar.scaledMarginRadius in image.
        // This is done only to make image offset calculations consistent (thus easier) between knob & bar images.
        var segsMaxX: [Double]
        if chapters.count > 0, durationSec > 0 {
          segsMaxX = chapters[1...].map{ $0.startTime / durationSec * barWidth_Scaled }
        } else {
          segsMaxX = []
        }
        segsMaxX.append(imgSizeScaled.width)  // add right end of bar

        var segMinX = Bar.scaledMarginRadius
        for segMaxX in segsMaxX {
          if isRightOfKnob {
            drawSeg(rightColor, minX: segMinX, maxX: segMaxX)
            segMinX = segMaxX  // for next loop
          } else if segMaxX > leftClipMaxX {
            // Knob at least partially overlaps segment. Chop off segment at start of knob
            isRightOfKnob = true
            drawSeg(leftColor, minX: segMinX, maxX: leftClipMaxX + scaleFactor)
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

        cgc.setBlendMode(.sourceAtop)
//        cgc.setBlendMode(.multiply)

//        for cachedRect in cachedRects {
//          cgc.beginPath()
//          cgc.addPath(CGPath(rect: cachedRect, transform: nil))
//
//          cgc.setFillColor(RenderCache.shared.barColorPreCache.cgColor)
//          cgc.fillPath()
//        }
      })!
    }

    static func imageRect(in drawRect: CGRect) -> CGRect {
      let imgHeight = (2 * Bar.imgMarginRadius) + RenderCache.shared.barHeight
      // can be negative:
      let spareHeight = drawRect.height - imgHeight
      let y = drawRect.origin.y + (spareHeight * 0.5)
      return CGRect(x: drawRect.origin.x - Bar.imgMarginRadius, y: y,
                    width: drawRect.width + (2 * Bar.imgMarginRadius), height: imgHeight)
    }

    static func imgSizeScaled(_ barWidth: CGFloat, scaleFactor: CGFloat) -> CGSize {
      let marginPairSum = (2 * Bar.imgMarginRadius)
      let size = CGSize(width: barWidth + marginPairSum, height: marginPairSum + RenderCache.shared.barHeight)
      return size.multiplyThenRound(scaleFactor)
    }
  }

}
