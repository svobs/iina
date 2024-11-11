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

  enum ImageType: Int {
    case mainKnob = 1
    case mainKnobSelected
    case loopKnob
    case loopKnobSelected
  }

  let barStrokeRadius: CGFloat = 1.5
  var barColorLeft = NSColor.controlAccentColor
  var barColorLeftGlow = NSColor.controlAccentColor
  var barColorPreCache = NSColor(named: .mainSliderBarPreCache)!
  var barColorRight = NSColor(named: .mainSliderBarRight)!
  var chapterStrokeColor = NSColor(named: .mainSliderBarChapterStroke)!

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
    let drawRect = NSRect(x: round(knobRect.origin.x) - RenderCache.Knob.imgMarginRadius,
                          y: knobRect.origin.y - RenderCache.Knob.imgMarginRadius + (0.5 * (knobRect.height - knobHeightAdj)),
                          width: knobImageSize.width, height: knobImageSize.height)
    NSGraphicsContext.current!.cgContext.draw(image, in: drawRect)
  }

  func drawBar(in barRect: NSRect, darkMode: Bool, screen: NSScreen, knobPosX: CGFloat, knobWidth: CGFloat, durationSec: CGFloat, chapters: [MPVChapter]?) {
    let barImageSize = Bar.imageSize(barRect.size)

    var drawRect = NSRect(x: round(barRect.origin.x) - RenderCache.Bar.imgMarginRadius,
                          y: barRect.origin.y - RenderCache.Bar.imgMarginRadius,
                          width: barImageSize.width, height: barImageSize.height)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                               y: drawRect.origin.y + 1,
                               width: drawRect.width,
                               height: drawRect.height - 2)
    }
    let bar = Bar(darkMode: darkMode, barSize: barRect.size, screen: screen, knobPosX: knobPosX, knobWidth: knobWidth, durationSec: durationSec, chapters: chapters)
    NSGraphicsContext.current!.cgContext.draw(bar.image, in: drawRect)
  }

  struct Bar {
    static let imgMarginRadius: CGFloat = 1.0
    static let scaledMarginRadius = imgMarginRadius * RenderCache.scaleFactor
    let image: CGImage

    init(darkMode: Bool, barSize: CGSize, screen: NSScreen, knobPosX: CGFloat, knobWidth: CGFloat,
         durationSec: CGFloat, chapters: [MPVChapter]?) {
      image = Bar.makeImage(barSize, screen: screen, darkMode: darkMode, knobPosX: knobPosX, knobWidth: knobWidth, durationSec: durationSec, chapters)
    }

    static func makeImage(_ barSize: CGSize, screen: NSScreen, darkMode: Bool, knobPosX: CGFloat, knobWidth: CGFloat,
                          durationSec: CGFloat, _ chapters: [MPVChapter]?) -> CGImage {
      let scaleFactor = RenderCache.scaleFactor
      let imageSizeScaled = Bar.imageSizeScaled(barSize, scaleFactor: scaleFactor)
      let knobPosScaledX = knobPosX * scaleFactor
      let barImage = CGImage.buildBitmapImage(width: Int(imageSizeScaled.width),
                                              height: Int(imageSizeScaled.height),
                                              drawingCalls: { cgContext in

        // Round the X position for cleaner drawing
        let pathRect = NSMakeRect(Bar.scaledMarginRadius,
                                  Bar.scaledMarginRadius,
                                  barSize.width * scaleFactor,
                                  barSize.height * scaleFactor)
        let strokeRadius = RenderCache.shared.barStrokeRadius


        let leftBarRect = NSRect(x: Bar.scaledMarginRadius,
                                 y: Bar.scaledMarginRadius,
                                 width: Bar.scaledMarginRadius + knobPosScaledX,
                                 height: barSize.height * scaleFactor)

        let rightBarRect = NSRect(x: Bar.scaledMarginRadius + knobPosScaledX,
                                  y: Bar.scaledMarginRadius,
                                  width: Bar.scaledMarginRadius + (barSize.width * scaleFactor) - knobPosScaledX,
                                  height: barSize.height * scaleFactor)

        var chapterMarkersLeft: [NSRect] = []
        var chapterMarkersRight: [NSRect] = []
        if let chapters, durationSec > 0, chapters.count > 1 {
          let isRetina = screen.backingScaleFactor > 1.0
          let screenScaleFactor = screen.screenScaleFactor
          let chMarkerWidth = scaleFactor * (1.0 / (screenScaleFactor * (isRetina ? 0.5 : 1)))

          RenderCache.shared.chapterStrokeColor.setStroke()
          let barWidthScaled = barSize.width * scaleFactor
          for chapter in chapters[1...] {
            let chapPosX = Bar.scaledMarginRadius + (chapter.startTime / durationSec * barWidthScaled) - (chMarkerWidth * 0.5)
            let markerRect = NSRect(x: chapPosX, y: Bar.scaledMarginRadius, width: chMarkerWidth, height: barSize.height * scaleFactor)
            if chapPosX < knobPosScaledX {
              chapterMarkersLeft.append(markerRect)
            } else {
              chapterMarkersRight.append(markerRect)
            }
          }
        }

        // LEFT

        var noFill: [(CGFloat, CGFloat)] = []
        var leftUnbuffered: [(CGFloat, CGFloat)] = []
        var leftBuffered: [(CGFloat, CGFloat)] = []
        var rightUnbuffered: [(CGFloat, CGFloat)] = []
        var rightBuffered: [(CGFloat, CGFloat)] = []

        for pair in noFill {

        }


        // Clip where the knob will be, including 1px from left & right of the knob
        let knobClipRect = NSRect(x: Bar.scaledMarginRadius + (knobPosX - 1) * scaleFactor,
                                  y: pathRect.origin.y,
                                  width: (knobWidth + 2) * scaleFactor,
                                  height: pathRect.height)
        //        cgContext.addPath(CGPath(rect: knobClipRect, transform: nil))

//        for rect in [knobClipRect] + chapterMarkersLeft + chapterMarkersRight {
//                    cgContext.addPath(CGPath(rect: rect, transform: nil))
//        }
        cgContext.clip(to: [knobClipRect] + chapterMarkersLeft + chapterMarkersRight)
        cgContext.clip(using: .evenOdd)

        cgContext.beginPath()

        // Clip chapters (if configured) from left
        for markerRect in chapterMarkersLeft {
          // Round the image corners by clipping out all drawing which is not in roundedRect (like using a stencil)
//          cgContext.addPath(CGPath(rect: markerRect, transform: nil))
        }


        // Draw LEFT (the "finished" section of the progress bar)
        cgContext.addPath(CGPath(rect: leftBarRect, transform: nil))
        cgContext.setFillColor(RenderCache.shared.barColorLeft.cgColor)
        cgContext.fillPath()
        cgContext.closePath()

        // RIGHT

        cgContext.beginPath()

        // Clip chapters (if configured) from right
        for markerRect in chapterMarkersRight {
          // Round the image corners by clipping out all drawing which is not in roundedRect (like using a stencil)
//          cgContext.addPath(CGPath(rect: markerRect, transform: nil))
        }


        // Draw RIGHT (the "unfinished" section of the progress bar)
        cgContext.addPath(CGPath(rect: rightBarRect, transform: nil))
        cgContext.setFillColor(RenderCache.shared.barColorRight.cgColor)
//////        cgContext.clip(to: rightBarRect)
        cgContext.fillPath()
        cgContext.closePath()

      })!
      return barImage
    }

    static func imageSize(_ barSize: CGSize) -> CGSize {
      return CGSize(width: barSize.width + (2 * Bar.imgMarginRadius),
                    height: barSize.height + (2 * Bar.imgMarginRadius))
    }

    static func imageSizeScaled(_ barSize: CGSize, scaleFactor: CGFloat) -> CGSize {
      let size = imageSize(barSize)
      return size.multiplyThenRound(scaleFactor)
    }
  }

  struct Knob {
    private static var mainKnobColor = NSColor(named: .mainSliderKnob)!
    private static var mainKnobActiveColor = NSColor(named: .mainSliderKnobActive)!
    private static var loopKnobColor = NSColor(named: .mainSliderLoopKnob)!
    /// Need a tiny amount of margin on all sides to allow for shadow and/or antialiasing
    static let imgMarginRadius: CGFloat = 1.0
    static let scaledMarginRadius = imgMarginRadius * RenderCache.scaleFactor
    static let knobStrokeRadius: CGFloat = 1
    static let shadowColor = NSShadow().shadowColor!.cgColor
    static let glowColor = NSColor.white.withAlphaComponent(1.0/3.0).cgColor

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
      let shadowColor = isDarkMode ? Knob.glowColor : Knob.shadowColor
      images = [.mainKnobSelected:
                  Knob.makeImage(fill: Knob.mainKnobActiveColor, shadow: shadowColor, knobWidth: knobWidth, knobHeight: mainKnobHeight),
                .mainKnob:
                  Knob.makeImage(fill: Knob.mainKnobColor, shadow: isDarkMode ? nil : shadowColor, knobWidth: knobWidth, knobHeight: mainKnobHeight),
                .loopKnob:
                  Knob.makeImage(fill: Knob.loopKnobColor, shadow: nil, knobWidth: knobWidth, knobHeight: loopKnobHeight),
                .loopKnobSelected:
                  isDarkMode ?
                Knob.makeImage(fill: Knob.mainKnobActiveColor, shadow: shadowColor, knobWidth: knobWidth, knobHeight: loopKnobHeight) :
                  Knob.makeImage(fill: Knob.loopKnobColor, shadow: nil, knobWidth: knobWidth, knobHeight: loopKnobHeight)
      ]
      self.isDarkMode = isDarkMode
      self.knobWidth = knobWidth
      self.mainKnobHeight = mainKnobHeight
    }

    static func makeImage(fill: NSColor, shadow: CGColor?, knobWidth: CGFloat, knobHeight: CGFloat) -> CGImage {
      let scaleFactor = RenderCache.scaleFactor
      let knobImageSizeScaled = Knob.imageSizeScaled(knobWidth: knobWidth, knobHeight: knobHeight, scaleFactor: scaleFactor)
      let knobImage = CGImage.buildBitmapImage(width: Int(knobImageSizeScaled.width),
                                               height: Int(knobImageSizeScaled.height),
                                               drawingCalls: { cgContext in

        // Round the X position for cleaner drawing
        let pathRect = NSMakeRect(Knob.scaledMarginRadius,
                                  Knob.scaledMarginRadius,
                                  knobWidth * scaleFactor,
                                  knobHeight * scaleFactor)
        let path = CGPath(roundedRect: pathRect, cornerWidth: knobStrokeRadius * scaleFactor,
                          cornerHeight: knobStrokeRadius * scaleFactor, transform: nil)

        if let shadow {
          cgContext.setShadow(offset: CGSize(width: 0, height: 0.5 * scaleFactor), blur: 1 * scaleFactor, color: shadow)
        }
        cgContext.beginPath()
        cgContext.addPath(path)

        cgContext.setFillColor(fill.cgColor)
        cgContext.fillPath()
        cgContext.closePath()

        if let shadow {
          /// According to Apple's docs for `NSShadow`: `The default shadow color is black with an alpha of 1/3`
          cgContext.beginPath()
          cgContext.addPath(path)
          cgContext.setLineWidth(0.4 * scaleFactor)
          cgContext.setStrokeColor(shadow)
          cgContext.strokePath()
          cgContext.closePath()
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
      return CGSize(width: knobWidth + (2 * Knob.imgMarginRadius),
                    height: knobHeight + (2 * Knob.imgMarginRadius))
    }

    static func imageSizeScaled(knobWidth: CGFloat, knobHeight: CGFloat, scaleFactor: CGFloat) -> CGSize {
      let size = imageSize(knobWidth: knobWidth, knobHeight: knobHeight)
      return size.multiplyThenRound(scaleFactor)
    }
  }  // end struct Knob

  var cachedKnob: Knob? = nil

}
