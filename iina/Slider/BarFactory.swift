//
//  BarFactory.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//


/// In the future, the sliders should be entirely custom, instead of relying on legacy `NSSlider`. Then the knob & slider can be
/// implemented via their own separate `CALayer`s which should enable more optimization opportunities. It's not been tested whether drawing
/// into (possibly cached) `CGImage`s as this class currently does delivers any improved performance (or is even slower)...
class BarFactory {
  static let shared = BarFactory()
  // MARK: - Bar

  // - Bar Constants

  // Make sure these are even numbers! Otherwise bar will be antialiased on non-Retina displays
  let barHeight: CGFloat = 4.0
  let volBarGreaterThanMaxHeight: CGFloat = 4.0

  let baseChapterGapWidth: CGFloat = 1.5

  lazy var maxVolBarHeightNeeded: CGFloat = {
    max(barHeight, volBarGreaterThanMaxHeight)
  }()
  let leftBarHeightWhileSeeking: CGFloat = 9.0
  let rightBarHeightWhileSeeking: CGFloat = 6.0
  lazy var maxPlayBarHeightNeeded: CGFloat = {
    max(barHeight, leftBarHeightWhileSeeking, rightBarHeightWhileSeeking)
  }()

  let barCornerRadius: CGFloat = 2.0
  var barColorLeft = NSColor.controlAccentColor.cgColor {
    didSet {
      leftCachedColor = BarFactory.exaggerateColor(barColorLeft)
    }
  }
  var barColorRight = NSColor.mainSliderBarRight.cgColor {
    didSet {
      rightCachedColor = BarFactory.exaggerateColor(barColorRight)
    }
  }

  var leftCachedColor = exaggerateColor(NSColor.controlAccentColor.cgColor)
  var rightCachedColor = exaggerateColor(NSColor.mainSliderBarRight.cgColor)
  let barMarginRadius: CGFloat = 1.0
  let colorRightBarGreaterThanMaxVol = false

  func updateBarColorsFromPrefs() {
    let userSetting: Preference.SliderBarLeftColor = Preference.enum(for: .playSliderBarLeftColor)
    switch userSetting {
    case .gray:
      barColorLeft = NSColor.mainSliderBarLeft.cgColor
    default:
      barColorLeft = NSColor.controlAccentColor.cgColor
    }
  }

  func drawPlayBar(in barRect: NSRect, barHeight: CGFloat,
                   darkMode: Bool, clearBG: Bool, screen: NSScreen,
                   knobMinX: CGFloat, knobWidth: CGFloat,
                   progressRatio: CGFloat, durationSec: CGFloat, chapters: [MPVChapter], cachedRanges: [(Double, Double)],
                   isShowingSeekPreview: Bool) {
    assert(barHeight <= barRect.height, "barHeight \(barHeight) > barRect.height \(barRect.height)")
    var drawRect = imageRect(in: barRect, tallestBarHeight: maxPlayBarHeightNeeded)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }

    let barImg = buildBarImage(barWidth: barRect.width, barHeight: barHeight,
                               screen: screen, darkMode: darkMode, clearBG: clearBG,
                               knobMinX: knobMinX, knobWidth: knobWidth, currentValueRatio: progressRatio,
                               durationSec: durationSec, chapters, cachedRanges: cachedRanges, isShowingSeekPreview: isShowingSeekPreview)
    NSGraphicsContext.current!.cgContext.draw(barImg, in: drawRect)
  }

  // MARK: - Volume Bar

  func drawVolumeBar(in barRect: NSRect, barHeight: CGFloat, screen: NSScreen,
                     darkMode: Bool, clearBG: Bool, knobMinX: CGFloat, knobWidth: CGFloat,
                     currentValue: CGFloat, maxValue: CGFloat) {
    assert(barHeight <= barRect.height, "barHeight \(barHeight) > barRect.height \(barRect.height)")
    var drawRect = imageRect(in: barRect, tallestBarHeight: maxVolBarHeightNeeded)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }
    let volBarImg = buildVolumeBarImage(darkMode: darkMode, clearBG: clearBG, barWidth: barRect.width, barHeight: barHeight,
                                        screen: screen,
                                        knobMinX: knobMinX, knobWidth: knobWidth,
                                        currentValue: currentValue, maxValue: maxValue)
    NSGraphicsContext.current!.cgContext.draw(volBarImg, in: drawRect)
  }

  func buildVolumeBarImage(darkMode: Bool, clearBG: Bool,
                           barWidth: CGFloat, barHeight: CGFloat,
                           screen: NSScreen,
                           knobMinX: CGFloat, knobWidth: CGFloat,
                           currentValue: Double, maxValue: Double) -> CGImage {
    // - Set up calculations
    let rc = BarFactory.shared
    let scaleFactor = screen.backingScaleFactor
    let imgSizeScaled = imgSizeScaled(barWidth: barWidth, tallestBarHeight: rc.maxVolBarHeightNeeded, scaleFactor: scaleFactor)
    let barWidth_Scaled = barWidth * scaleFactor
    let barHeight_Scaled = barHeight * scaleFactor
    let volBarGreaterThanMaxHeight_Scaled = rc.volBarGreaterThanMaxHeight * scaleFactor
    let outerPadding_Scaled = rc.barMarginRadius * scaleFactor
    let cornerRadius_Scaled = rc.barCornerRadius * scaleFactor
    let leftColor = rc.barColorLeft
    let rightColor = rc.barColorRight
    let barMinX = outerPadding_Scaled
    let barMaxX = imgSizeScaled.width - (outerPadding_Scaled * 2)

    let currentValueRatio = currentValue / maxValue
    let currentValuePointX = (outerPadding_Scaled + (currentValueRatio * barWidth_Scaled)).rounded()

    // Determine clipping rects (pixel whitelists)
    let leftClipMaxX: CGFloat
    let rightClipMinX: CGFloat
    if clearBG || knobWidth < 1.0 {
      leftClipMaxX = currentValuePointX
      rightClipMinX = currentValuePointX
    } else {
      // - Will clip out the knob
      leftClipMaxX = (knobMinX - 1) * scaleFactor
      rightClipMinX = leftClipMaxX + (knobWidth * scaleFactor)
    }

    let hasLeft = leftClipMaxX - outerPadding_Scaled > 0.0
    let hasRight = rightClipMinX + outerPadding_Scaled < imgSizeScaled.width

    // If volume can exceed 100%, let's draw the part of the bar which is >100% differently
    let vol100PercentPointX = (outerPadding_Scaled + ((100.0 / maxValue) * barWidth_Scaled)).rounded()

    let barImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in

      func drawEntireBar(color: CGColor, pillHeight: CGFloat, clipMinX: CGFloat, clipMaxX: CGFloat) {
        cgc.resetClip()
        cgc.clip(to: CGRect(x: clipMinX, y: 0,
                            width: clipMaxX - clipMinX,
                            height: imgSizeScaled.height))

        rc.addPillPath(cgc, minX: barMinX,
                       maxX: barMaxX,
                       interPillGapWidth: 0,
                       height: pillHeight,
                       outerPadding_Scaled: outerPadding_Scaled,
                       cornerRadius_Scaled: cornerRadius_Scaled,
                       leftEdge: .noBorderingPill,
                       rightEdge: .noBorderingPill)
        cgc.clip()

        rc.drawPill(cgc, color,
                    minX: barMinX,
                    maxX: barMaxX,
                    interPillGapWidth: 0,
                    height: pillHeight,
                    outerPadding_Scaled: outerPadding_Scaled,
                    cornerRadius_Scaled: cornerRadius_Scaled,
                    leftEdge: .noBorderingPill,
                    rightEdge: .noBorderingPill)
      }

      var pillHeight = barHeight_Scaled

      if hasLeft {  // Left of knob (i.e. "completed" section of bar)
        var minX = 0.0

        if vol100PercentPointX < leftClipMaxX {
          drawEntireBar(color: leftColor, pillHeight: pillHeight, clipMinX: minX, clipMaxX: vol100PercentPointX)
          // Update for next segment:
          minX = vol100PercentPointX
          pillHeight = volBarGreaterThanMaxHeight_Scaled
        }

        drawEntireBar(color: leftColor, pillHeight: pillHeight, clipMinX: minX, clipMaxX: leftClipMaxX)
      }

      if hasRight {  // Right of knob
        var minX = rightClipMinX

        if vol100PercentPointX > rightClipMinX && vol100PercentPointX < imgSizeScaled.width {
          drawEntireBar(color: rightColor, pillHeight: pillHeight, clipMinX: minX, clipMaxX: vol100PercentPointX)
          // Update for next segment:
          minX = vol100PercentPointX
          pillHeight = volBarGreaterThanMaxHeight_Scaled
        }

        drawEntireBar(color: rightColor, pillHeight: pillHeight, clipMinX: minX, clipMaxX: imgSizeScaled.width)
      }
    }


    // If volume can exceed 100%, draw that section in special color
    guard maxValue > 100.0 else { return barImg }
    let highlightOverlayImg = CGImage.buildBitmapImage(width: imgSizeScaled.widthInt, height: imgSizeScaled.heightInt) { cgc in

      let y = (CGFloat(cgc.height) - volBarGreaterThanMaxHeight_Scaled) * 0.5  // y should include outerPadding_Scaled here

      let leftMaxBar: CGRect?
      let rightMaxBar: CGRect?
      if leftClipMaxX < vol100PercentPointX {
        // Volume is lower than 100%: only need to draw the part of bar which is > 100%
        leftMaxBar = nil
        if rc.colorRightBarGreaterThanMaxVol {
          rightMaxBar = CGRect(x: vol100PercentPointX, y: y,
                               width: barMaxX - vol100PercentPointX, height: volBarGreaterThanMaxHeight_Scaled)
        } else {
          rightMaxBar = nil
        }
      } else {
        leftMaxBar = CGRect(x: vol100PercentPointX, y: y,
                            width: leftClipMaxX - vol100PercentPointX, height: volBarGreaterThanMaxHeight_Scaled)
        if rc.colorRightBarGreaterThanMaxVol {
          rightMaxBar = CGRect(x: leftClipMaxX, y: y,
                               width: barMaxX - leftClipMaxX, height: volBarGreaterThanMaxHeight_Scaled)
        } else {
          rightMaxBar = nil
        }
      }

      if let leftMaxBar {
        let leftMaxColor = rc.leftCachedColor
        cgc.setFillColor(leftMaxColor)
        cgc.fill(leftMaxBar)
      }
      if let rightMaxBar {
        let rightMaxColor = rc.rightCachedColor
        cgc.setFillColor(rightMaxColor)
        cgc.fill(rightMaxBar)
      }

      cgc.setBlendMode(.destinationIn)
      cgc.draw(barImg, in: CGRect(origin: .zero, size: imgSizeScaled))
    }

    return rc.makeCompositeBarImg(barImg: barImg, highlightOverlayImg: highlightOverlayImg)
  }  // end func buildVolumeBarImage

  /// `barWidth` does not include added leading or trailing margin
  func buildBarImage(barWidth: CGFloat, barHeight: CGFloat,
                     screen: NSScreen, darkMode: Bool, clearBG: Bool,
                     knobMinX: CGFloat, knobWidth: CGFloat, currentValueRatio: CGFloat,
                     durationSec: CGFloat, _ chapters: [MPVChapter], cachedRanges: [(Double, Double)],
                     isShowingSeekPreview: Bool) -> CGImage {
    // - Set up calculations
    let rc = BarFactory.shared
    let scaleFactor = screen.backingScaleFactor
    let imgSizeScaled = imgSizeScaled(barWidth: barWidth, tallestBarHeight: rc.maxPlayBarHeightNeeded, scaleFactor: scaleFactor)
    let barWidth_Scaled = barWidth * scaleFactor
    let barHeight_Scaled = barHeight * scaleFactor
    let outerPadding_Scaled = rc.barMarginRadius * scaleFactor
    let cornerRadius_Scaled = rc.barCornerRadius * scaleFactor
    let leftColor = rc.barColorLeft
    let rightColor = rc.barColorRight
    let chapterGapWidth = (baseChapterGapWidth * scaleFactor).rounded()
    let currentValuePointX = (outerPadding_Scaled + (currentValueRatio * barWidth_Scaled)).rounded()
    let hasSpaceForKnob = knobWidth > 0.0

    // Determine clipping rects (pixel whitelists)
    let leftClipMaxX: CGFloat
    let rightClipMinX: CGFloat
    if hasSpaceForKnob {
      // - Will clip out the knob
      leftClipMaxX = (knobMinX - 1) * scaleFactor
      rightClipMinX = leftClipMaxX + (knobWidth * scaleFactor)
    } else {
      leftClipMaxX = currentValuePointX
      rightClipMinX = currentValuePointX
    }

    let hasLeft = leftClipMaxX - outerPadding_Scaled > 0.0
    let hasRight = rightClipMinX + outerPadding_Scaled < imgSizeScaled.width

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
      let lastSegMaxX = imgSizeScaled.width - (outerPadding_Scaled * 2)
      segsMaxX.append(lastSegMaxX)

      var segIndex = 0
      var segMinX = outerPadding_Scaled

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
                           outerPadding_Scaled: outerPadding_Scaled,
                           cornerRadius_Scaled: cornerRadius_Scaled,
                           leftEdge: leftEdge,
                           rightEdge: rightEdge)
            cgc.clip()
            done = true
          }
          rc.drawPill(cgc, leftColor,
                      minX: segMinX, maxX: segMaxX,
                      interPillGapWidth: chapterGapWidth,
                      height: isShowingSeekPreview ? rc.leftBarHeightWhileSeeking * scaleFactor : barHeight_Scaled,
                      outerPadding_Scaled: outerPadding_Scaled,
                      cornerRadius_Scaled: cornerRadius_Scaled,
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
                      height: isShowingSeekPreview ? rc.rightBarHeightWhileSeeking * scaleFactor : barHeight_Scaled,
                      outerPadding_Scaled: outerPadding_Scaled,
                      cornerRadius_Scaled: cornerRadius_Scaled,
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
      if hasSpaceForKnob {
        // Apply clip (pixel whitelist) to avoid drawing over the knob
        cgc.clip(to: [leftClipRect, rightClipRect])
      }

      var rectsLeft: [NSRect] = []
      var rectsRight: [NSRect] = []
      for cachedRange in cachedRanges.sorted(by: { $0.0 < $1.0 }) {
        let startX: CGFloat = cachedRange.0 / durationSec * barWidth_Scaled
        let endX: CGFloat = cachedRange.1 / durationSec * barWidth_Scaled
        if startX > leftClipMaxX {
          rectsRight.append(CGRect(x: startX, y: outerPadding_Scaled,
                                   width: endX - startX, height: barHeight_Scaled))
        } else if endX > leftClipMaxX {
          rectsLeft.append(CGRect(x: startX, y: outerPadding_Scaled,
                                  width: leftClipMaxX - startX, height: barHeight_Scaled))

          let start2ndX = leftClipMaxX
          rectsRight.append(CGRect(x: start2ndX, y: outerPadding_Scaled,
                                   width: endX - start2ndX, height: barHeight_Scaled))
        } else {
          rectsLeft.append(CGRect(x: startX, y: outerPadding_Scaled,
                                  width: endX - startX, height: barHeight_Scaled))
        }
      }

      cgc.setFillColor(rc.leftCachedColor)
      cgc.fill(rectsLeft)
      cgc.setFillColor(rc.rightCachedColor)
      cgc.fill(rectsRight)

      cgc.setBlendMode(.destinationIn)
      cgc.draw(barImg, in: CGRect(origin: .zero, size: imgSizeScaled))
    }

    return rc.makeCompositeBarImg(barImg: barImg, highlightOverlayImg: cacheImg)
  }

  /// Measured in points, not pixels!
  func imageRect(in drawRect: CGRect, tallestBarHeight: CGFloat) -> CGRect {
    let margin = BarFactory.shared.barMarginRadius
    let imgHeight = (2 * margin) + tallestBarHeight
    // can be negative:
    let spareHeight = drawRect.height - imgHeight
    let y = drawRect.origin.y + (spareHeight * 0.5)
    return CGRect(x: drawRect.origin.x - margin, y: y,
                  width: drawRect.width + (2 * margin), height: imgHeight)
  }

  /// `scaleFactor` should match `backingScaleFactor` from the current screen.
  /// This will either be `2.0` for Retina displays, or `1.0` for traditional displays.
  func imgSizeScaled(barWidth: CGFloat, tallestBarHeight: CGFloat, scaleFactor: CGFloat) -> CGSize {
    let marginPairSum = (2 * BarFactory.shared.barMarginRadius)
    let size = CGSize(width: barWidth + marginPairSum, height: marginPairSum + tallestBarHeight)
    return size.multiplyThenRound(scaleFactor)
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

}
