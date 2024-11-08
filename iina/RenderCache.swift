//
//  RenderCache.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//  Copyright © 2024 lhc. All rights reserved.
//


class RenderCache {
  static let shared = RenderCache()

  enum ImageType: Int {
    case mainKnob = 1
    case mainKnobSelected
    case loopKnob
  }

  func drawKnob(_ knobType: ImageType, in knobRect: NSRect, darkMode: Bool, knobWidth: CGFloat, mainKnobHeight: CGFloat) {
    let knob: Knob
    if let cachedKnob, cachedKnob.isDarkMode == darkMode, cachedKnob.knobWidth == knobWidth, cachedKnob.mainKnobHeight == mainKnobHeight {
      knob = cachedKnob
    } else {
      knob = Knob(isDarkMode: darkMode, knobWidth: knobWidth, mainKnobHeight: mainKnobHeight)
      cachedKnob = knob
    }

    let image = knob.images[knobType]!

    let knobHeightAdj = knobType == .loopKnob ? knob.loopKnobHeight : knob.mainKnobHeight
    let knobImageSize = Knob.imageSize(knobWidth: knobWidth, knobHeight: knobHeightAdj)
    let drawRect = NSRect(x: round(knobRect.origin.x) - RenderCache.Knob.imgMarginRadius,
                          y: knobRect.origin.y - RenderCache.Knob.imgMarginRadius + (0.5 * (knobRect.height - knobHeightAdj)),
                          width: knobImageSize.width, height: knobImageSize.height)
    NSGraphicsContext.current!.cgContext.draw(image, in: drawRect)
  }

  struct Knob {
    private static var mainKnobColor = NSColor(named: .mainSliderKnob)!
    private static var mainKnobActiveColor = NSColor(named: .mainSliderKnobActive)!
    static let scaleFactor: CGFloat = 2.0
    /// Need a tiny amount of margin on all sides to allow for shadow and/or antialiasing
    static let imgMarginRadius: CGFloat = 1.0
    static let scaledMarginRadius = imgMarginRadius * scaleFactor
    static let knobStrokeRadius: CGFloat = 1
    static let shadowColor = NSShadow().shadowColor!.cgColor

    let images: [ImageType: CGImage]
    let isDarkMode: Bool
    let knobWidth: CGFloat
    let mainKnobHeight: CGFloat

    init(isDarkMode: Bool, knobWidth: CGFloat, mainKnobHeight: CGFloat) {
      let loopKnobHeight = Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
      images = [.mainKnobSelected:
                  Knob.makeImage(fill: Knob.mainKnobActiveColor, shadow: !isDarkMode, knobWidth: knobWidth, knobHeight: mainKnobHeight),
                .mainKnob:
                  Knob.makeImage(fill: Knob.mainKnobColor, shadow: !isDarkMode, knobWidth: knobWidth, knobHeight: mainKnobHeight),
                .loopKnob:
                  Knob.makeImage(fill: NSColor(named: .mainSliderLoopKnob)!, shadow: false, knobWidth: knobWidth, knobHeight: loopKnobHeight)
      ]
      self.isDarkMode = isDarkMode
      self.knobWidth = knobWidth
      self.mainKnobHeight = mainKnobHeight
    }

    static func makeImage(fill: NSColor, shadow: Bool, knobWidth: CGFloat, knobHeight: CGFloat) -> CGImage {
      let scaleFactor = Knob.scaleFactor
      let knobImageSizeScaled = Knob.imageSizeScaled(knobWidth: knobWidth, knobHeight: knobHeight, scaleFactor: scaleFactor)
      let knobImage = CGImage.buildBitmapImage(width: Int(knobImageSizeScaled.width),
                                               height: Int(knobImageSizeScaled.height),
                                               drawingCalls: { cgContext in
        cgContext.interpolationQuality = .high

        // Round the X position for cleaner drawing
        let pathRect = NSMakeRect(Knob.scaledMarginRadius,
                                  Knob.scaledMarginRadius,
                                  knobWidth * scaleFactor,
                                  knobHeight * scaleFactor)
        let path = CGPath(roundedRect: pathRect, cornerWidth: knobStrokeRadius * scaleFactor,
                          cornerHeight: knobStrokeRadius * scaleFactor, transform: nil)

        if shadow {
          cgContext.setShadow(offset: CGSize(width: 0, height: 0.5 * scaleFactor), blur: 1 * scaleFactor, color: shadowColor)
        }
        cgContext.beginPath()
        cgContext.addPath(path)

        cgContext.setFillColor(fill.cgColor)
        cgContext.fillPath()
        cgContext.closePath()

        if shadow {
          /// According to Apple's docs for `NSShadow`: `The default shadow color is black with an alpha of 1/3`
          cgContext.beginPath()
          cgContext.addPath(path)
          cgContext.setLineWidth(0.4 * scaleFactor)
          cgContext.setStrokeColor(shadowColor)
          cgContext.strokePath()
          cgContext.closePath()
        }
      })!
      return knobImage
    }

    var loopKnobHeight: CGFloat {
      Knob.loopKnobHeight(mainKnobHeight: mainKnobHeight)
    }

    static func loopKnobHeight(mainKnobHeight: CGFloat) -> CGFloat {
      // We want loop knobs to be shorter than the primary knob.
      return round(mainKnobHeight * PlaySliderLoopKnob.knobHeightAdjustment)
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
