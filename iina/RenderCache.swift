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

  let barHeight: CGFloat = 3.0
  let barStrokeRadius: CGFloat = 1.5
  var barColorLeft = NSColor.controlAccentColor
  var barColorLeftGlow = NSColor.controlAccentColor
  var barColorPreCache = NSColor(named: .mainSliderBarPreCache)!
  var barColorRight = NSColor(named: .mainSliderBarRight)!
  var chapterStrokeColor = NSColor(named: .mainSliderBarChapterStroke)!

  private var mainKnobColor = NSColor(named: .mainSliderKnob)!
  private var mainKnobActiveColor = NSColor(named: .mainSliderKnobActive)!
  private var loopKnobColor = NSColor(named: .mainSliderLoopKnob)!
  /// Need a tiny amount of margin on all sides to allow for shadow and/or antialiasing
  let scaledMarginRadius = RenderCache.imgMarginRadius * RenderCache.scaleFactor
  let knobStrokeRadius: CGFloat = 1
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
      let knobImageSizeScaled = Knob.imageSizeScaled(knobWidth: knobWidth, knobHeight: knobHeight, scaleFactor: scaleFactor)
      let knobImage = CGImage.buildBitmapImage(width: knobImageSizeScaled.widthInt,
                                               height: knobImageSizeScaled.heightInt,
                                               drawingCalls: { cgContext in

        // Round the X position for cleaner drawing
        let pathRect = NSMakeRect(RenderCache.shared.scaledMarginRadius,
                                  RenderCache.shared.scaledMarginRadius,
                                  knobWidth * scaleFactor,
                                  knobHeight * scaleFactor)
        let path = CGPath(roundedRect: pathRect, cornerWidth: RenderCache.shared.knobStrokeRadius * scaleFactor,
                          cornerHeight: RenderCache.shared.knobStrokeRadius * scaleFactor, transform: nil)

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

    static func imageSizeScaled(knobWidth: CGFloat, knobHeight: CGFloat, scaleFactor: CGFloat) -> CGSize {
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

  func drawBar(in barRect: NSRect, darkMode: Bool, screen: NSScreen, knobPosX: CGFloat, knobWidth: CGFloat,
               durationSec: CGFloat, chapters: [MPVChapter]?) {
    var drawRect = Bar.imageRect(in: barRect)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }
    let bar = Bar(darkMode: darkMode, barWidth: barRect.width, screen: screen, knobPosX: knobPosX, knobWidth: knobWidth,
                  durationSec: durationSec, chapters: chapters)
    NSGraphicsContext.current!.cgContext.draw(bar.image, in: drawRect)
  }

  struct Bar {
    static let baseChapterWidth: CGFloat = 3.0
    static let imgMarginRadius: CGFloat = 1.0
    static let scaledMarginRadius = imgMarginRadius * RenderCache.scaleFactor
    let image: CGImage

    /// `barWidth` does not include added leading or trailing margin
    init(darkMode: Bool, barWidth: CGFloat, screen: NSScreen, knobPosX: CGFloat, knobWidth: CGFloat,
         durationSec: CGFloat, chapters: [MPVChapter]?) {
      image = Bar.makeImage(barWidth, screen: screen, darkMode: darkMode, knobPosX: knobPosX, knobWidth: knobWidth,
                            durationSec: durationSec, chapters)
    }

    static func makeImage(_ barWidth: CGFloat, screen: NSScreen, darkMode: Bool, knobPosX: CGFloat, knobWidth: CGFloat,
                          durationSec: CGFloat, _ chapters: [MPVChapter]?) -> CGImage {
      let scaleFactor = RenderCache.scaleFactor
      let imageSizeScaled = Bar.imageSizeScaled(barWidth, scaleFactor: scaleFactor)

      return CGImage.buildBitmapImage(width: imageSizeScaled.widthInt,
                                              height: imageSizeScaled.heightInt,
                                              drawingCalls: { cgContext in

        // - Set up calculations

        let barWidthScaled = barWidth * scaleFactor
        let barHeightScaled = RenderCache.shared.barHeight * scaleFactor
        let strokeRadiusScaled = RenderCache.shared.barStrokeRadius * scaleFactor
        let knobPosScaledX = knobPosX * scaleFactor

        // Set up clipping regions
        var clipSegments: [(CGFloat, CGFloat)] = []

        // Clip where the knob will be
        let knobClipStartX = Bar.scaledMarginRadius + (knobPosX - 2) * scaleFactor
        let knobClipEndX = knobClipStartX + (knobWidth) * scaleFactor
        var didIncludeKnob = false

        var segmentStartX = 0.0
        if let chapters, durationSec > 0, chapters.count > 1 {
          let screenScaleFactor = screen.screenScaleFactor
          let chMarkerWidth = Bar.baseChapterWidth * max(1.0, screenScaleFactor * 0.5)

          for chapter in chapters[1...] {
            /// chapter start == segment end
            var segmentEndX = Bar.scaledMarginRadius + (chapter.startTime / durationSec * barWidthScaled) - chMarkerWidth
            if segmentEndX <= knobClipStartX {
              if !didIncludeKnob && segmentEndX + chMarkerWidth > knobClipStartX {
                didIncludeKnob = true
                clipSegments.append((segmentStartX, knobClipStartX))  // knob
                segmentStartX = knobClipEndX  // next loop
              } else {
                clipSegments.append((segmentStartX, segmentEndX))
                segmentStartX = segmentEndX + chMarkerWidth  // next loop
              }
            } else if !didIncludeKnob {
              didIncludeKnob = true
              clipSegments.append((segmentStartX, knobClipStartX))  // knob
              segmentStartX = knobClipEndX  // next loop
            }
            
            if segmentEndX > knobClipEndX {
              clipSegments.append((segmentStartX, segmentEndX))
              segmentStartX = segmentEndX + chMarkerWidth  // next loop
              segmentEndX = knobClipStartX
            }
          }
        }

        if !didIncludeKnob {
          didIncludeKnob = true
          clipSegments.append((segmentStartX, knobClipStartX))  // knob
          segmentStartX = knobClipEndX  // next loop
        }
        let barEndX = imageSizeScaled.width
        if segmentStartX < barEndX {
          clipSegments.append((segmentStartX, barEndX))
        }

        // Apply clip to exclude knob & chapter markers
        let clipRects = clipSegments.map{ NSRect(x: $0.0, y: Bar.scaledMarginRadius, width: $0.1 - $0.0, height: barHeightScaled) }
        cgContext.clip(to: clipRects)

        // LEFT

        let leftBarRect = NSRect(x: Bar.scaledMarginRadius,
                                 y: Bar.scaledMarginRadius,
                                 width: knobPosScaledX - Bar.scaledMarginRadius,
                                 height: barHeightScaled)

        // Draw LEFT (the "finished" section of the progress bar)
        cgContext.beginPath()
        cgContext.addPath(CGPath(roundedRect: leftBarRect, cornerWidth:  strokeRadiusScaled, cornerHeight:  strokeRadiusScaled, transform: nil))
        cgContext.setFillColor(RenderCache.shared.barColorLeft.cgColor)
        cgContext.fillPath()

        // RIGHT

        let rightBarRect = NSRect(x: Bar.scaledMarginRadius + knobPosScaledX,
                                  y: Bar.scaledMarginRadius,
                                  width: Bar.scaledMarginRadius + barWidthScaled - knobPosScaledX,
                                  height: barHeightScaled)

        cgContext.beginPath()
        // Draw RIGHT (the "unfinished" section of the progress bar)
        cgContext.addPath(CGPath(roundedRect: rightBarRect, cornerWidth:  strokeRadiusScaled, cornerHeight:  strokeRadiusScaled, transform: nil))
        cgContext.setFillColor(RenderCache.shared.barColorRight.cgColor)
        cgContext.fillPath()

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

    static func imageSizeScaled(_ barWidth: CGFloat, scaleFactor: CGFloat) -> CGSize {
      let marginPairSum = (2 * Bar.imgMarginRadius)
      let size = CGSize(width: barWidth + marginPairSum, height: marginPairSum + RenderCache.shared.barHeight)
      return size.multiplyThenRound(scaleFactor)
    }
  }

}
