//
//  BarFactory.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//

// Constants. All in pts (not scaled).
// Make sure these are even numbers! Otherwise bar will be antialiased on non-Retina displays

fileprivate let barHeight_Normal: CGFloat = 3.0
fileprivate let barCornerRadius_Normal: CGFloat = 1.5

fileprivate let barHeight_FocusedCurrChapter: CGFloat = 6.0
fileprivate let barCornerRadius_FocusedCurrChapter: CGFloat = 3.0

fileprivate let barHeight_FocusedNonCurrChapter: CGFloat = 4.0
fileprivate let barCornerRadius_FocusedNonCurrChapter: CGFloat = 3.0

fileprivate let barHeight_VolumeAbove100_Left: CGFloat = 3.0
fileprivate let barHeight_VolumeAbove100_Right: CGFloat = 2.0

fileprivate let barImgPadding: CGFloat = 1.0
fileprivate let chapterGapWidth: CGFloat = 1.5

// MARK: - Support Classes

struct BarConf {
  let scaleFactor: CGFloat

  let imgPadding: CGFloat
  /// `imgHeight` is independent of `barHeight`
  let imgHeight: CGFloat
  let barHeight: CGFloat
  let interPillGapWidth: CGFloat

  let fillColor: CGColor
  let pillCornerRadius: CGFloat

  var barMinX: CGFloat { imgPadding }

  init(scaleFactor: CGFloat, imgPadding: CGFloat, imgHeight: CGFloat, barHeight: CGFloat, interPillGapWidth: CGFloat,
       fillColor: CGColor, pillCornerRadius: CGFloat) {
    self.scaleFactor = scaleFactor
    self.imgPadding = imgPadding
    self.imgHeight = imgHeight
    self.barHeight = barHeight
    self.interPillGapWidth = interPillGapWidth
    self.fillColor = fillColor
    self.pillCornerRadius = pillCornerRadius
  }

  func rescaled(to newScaleFactor: CGFloat) -> BarConf {
    let scaleRatio = newScaleFactor / scaleFactor
    return BarConf(
      scaleFactor: newScaleFactor,
      imgPadding: imgPadding * scaleRatio,
      imgHeight: imgHeight * scaleRatio,
      barHeight: barHeight * scaleRatio,
      interPillGapWidth: interPillGapWidth * scaleRatio,
      fillColor: fillColor,
      pillCornerRadius: pillCornerRadius * scaleRatio
    )
  }

  func cloned(imgPadding: CGFloat? = nil,
              imgHeight: CGFloat? = nil,
              barHeight: CGFloat? = nil,
              interPillGapWidth: CGFloat? = nil,
              fillColor: CGColor? = nil,
              pillCornerRadius: CGFloat? = nil) -> BarConf {
    BarConf(
      scaleFactor: scaleFactor,
      imgPadding: imgPadding ?? self.imgPadding,
      imgHeight: imgHeight ?? self.imgHeight,
      barHeight: barHeight ?? self.barHeight,
      interPillGapWidth: interPillGapWidth ?? self.interPillGapWidth,
      fillColor: fillColor ?? self.fillColor,
      pillCornerRadius: pillCornerRadius ?? self.pillCornerRadius)
  }
}

struct BarConfScaleSet {
  let x1: BarConf
  let x2: BarConf

  init(x1: BarConf, x2: BarConf) {
    self.x1 = x1
    self.x2 = x2
  }

  init(imgPadding: CGFloat, imgHeight: CGFloat, barHeight: CGFloat, interPillGapWidth: CGFloat,
       fillColor: CGColor, pillCornerRadius: CGFloat) {
    let x1 = BarConf(scaleFactor: 1.0, imgPadding: imgPadding, imgHeight: imgHeight, barHeight: barHeight, interPillGapWidth: interPillGapWidth, fillColor: fillColor, pillCornerRadius: pillCornerRadius)
    self.x1 = x1
    self.x2 = x1.rescaled(to: 2.0)
  }

  func cloned(imgPadding: CGFloat? = nil,
              imgHeight: CGFloat? = nil,
              barHeight: CGFloat? = nil,
              interPillGapWidth: CGFloat? = nil,
              fillColor: CGColor? = nil,
              pillCornerRadius: CGFloat? = nil) -> BarConfScaleSet {
    let x1New = x1.cloned(imgPadding: imgPadding, imgHeight: imgHeight, barHeight: barHeight, interPillGapWidth: interPillGapWidth,
                          fillColor: fillColor, pillCornerRadius: pillCornerRadius)
    let x2New = x1New.rescaled(to: 2.0)
    return BarConfScaleSet(x1: x1New, x2: x2New)
  }

  var fillColor: CGColor { x1.fillColor }

  func getScale(_ scale: CGFloat) -> BarConf {
    switch scale {
    case 1.0:
      return x1
    case 2.0:
      return x2
    default:
      fatalError("Unimplemented scale: \(scale)")
    }
  }
}

/// - Current vs Other Chapter?
/// - Focused vs Not Focused?
struct PlayBarConfScaleSet {
  let currentChapter_Left: BarConfScaleSet
  let currentChapter_Right: BarConfScaleSet

  let nonCurrentChapter_Left: BarConfScaleSet
  let nonCurrentChapter_Right: BarConfScaleSet

  /// `scale` should match `backingScaleFactor` from the current screen.
  /// This will either be `2.0` for Retina displays, or `1.0` for traditional displays.
  func forImg(scale: CGFloat, barWidth: CGFloat) -> PlayBarImgConf {
    let scaledConf = currentChapter_Left.getScale(scale)
    let imgWidth = (barWidth * scale) + (2 * scaledConf.imgPadding)
    let imgSize = CGSize(width: imgWidth, height: scaledConf.imgHeight)
    return PlayBarImgConf(currentChapter_Left: scaledConf,
                          currentChapter_Right: currentChapter_Right.getScale(scale),
                          nonCurrentChapter_Left: nonCurrentChapter_Left.getScale(scale),
                          nonCurrentChapter_Right: nonCurrentChapter_Right.getScale(scale),
                          imgSize: imgSize)
  }
}

struct PlayBarImgConf {
  let currentChapter_Left: BarConf
  let currentChapter_Right: BarConf

  let nonCurrentChapter_Left: BarConf
  let nonCurrentChapter_Right: BarConf

  let imgSize: CGSize

  var barWidth: CGFloat {
    imgWidth - (2 * imgPadding)
  }
  var imgPadding: CGFloat { currentChapter_Left.imgPadding }
  var imgHeight: CGFloat { imgSize.height }
  var imgWidth: CGFloat { imgSize.width }
}

/// - Current vs Other Chapter?
/// - Focused vs Not Focused?
struct VolBarImgConf {
  let below100_Left: BarConf
  let below100_Right: BarConf

  let above100_Left: BarConf
  let above100_Right: BarConf

  let imgSize: CGSize

  var barWidth: CGFloat {
    imgWidth - (2 * imgPadding)
  }
  var imgPadding: CGFloat { below100_Left.imgPadding }
  var imgHeight: CGFloat { imgSize.height }
  var imgWidth: CGFloat { imgSize.width }

  var barMinX: CGFloat { imgPadding }
  var barMaxX: CGFloat { imgWidth - (imgPadding * 2) }
}


/// Draws slider bars, e.g., play slider & volume slider.
/// 
/// In the future, the sliders should be entirely custom, instead of relying on legacy `NSSlider`. Then the knob & slider can be
/// implemented via their own separate `CALayer`s which should enable more optimization opportunities. It's not been tested whether drawing
/// into (possibly cached) `CGImage`s as this class currently does delivers any improved performance (or is even slower)...
class BarFactory {
  static var shared = BarFactory()

  // MARK: - Init / Config

  var playBar_Normal:  PlayBarConfScaleSet
  var playBar_Focused:  PlayBarConfScaleSet

  var volumeBelow100_Left: BarConfScaleSet
  var volumeBelow100_Right: BarConfScaleSet

  var volumeAbove100_Left: BarConfScaleSet
  var volumeAbove100_Right: BarConfScaleSet

  let maxPlayBarHeightNeeded = max(barHeight_Normal, barHeight_FocusedCurrChapter, barHeight_FocusedNonCurrChapter)
  let maxVolBarHeightNeeded = max(barHeight_Normal, barHeight_VolumeAbove100_Left, barHeight_VolumeAbove100_Right)

  private var leftCachedColor: CGColor
  private var rightCachedColor: CGColor

  init() {
    let barColorLeft = BarFactory.barColorLeftFromPrefs()
    leftCachedColor = BarFactory.exaggerateColor(barColorLeft)

    let barColorRight = NSColor.mainSliderBarRight.cgColor
    rightCachedColor = BarFactory.exaggerateColor(barColorRight)

    let verticalPaddingTotal = barImgPadding * 2
    let playNormalLeft = BarConfScaleSet(imgPadding: barImgPadding, imgHeight: verticalPaddingTotal + maxPlayBarHeightNeeded,
                                         barHeight: barHeight_Normal, interPillGapWidth: chapterGapWidth,
                                         fillColor: barColorLeft, pillCornerRadius: barCornerRadius_Normal)
    let playNormalRight = playNormalLeft.cloned(fillColor: barColorRight)
    rightCachedColor = BarFactory.exaggerateColor(barColorRight)

    playBar_Normal =  PlayBarConfScaleSet(currentChapter_Left: playNormalLeft, currentChapter_Right: playNormalRight,
                                          nonCurrentChapter_Left: playNormalLeft, nonCurrentChapter_Right: playNormalRight)

    let focusedCurrChapterLeft = playNormalLeft.cloned(barHeight: barHeight_FocusedCurrChapter,
                                                       pillCornerRadius: barCornerRadius_FocusedCurrChapter)
    let focusedCurrChapterRight = playNormalRight.cloned(barHeight: barHeight_FocusedCurrChapter,
                                                         pillCornerRadius: barCornerRadius_FocusedCurrChapter)
    let nonCurrChapterLeft = playNormalLeft.cloned(barHeight: barHeight_FocusedNonCurrChapter,
                                                   pillCornerRadius: barCornerRadius_FocusedNonCurrChapter)
    let nonCurrChapterRight = playNormalRight.cloned(barHeight: barHeight_FocusedNonCurrChapter,
                                                     pillCornerRadius: barCornerRadius_FocusedNonCurrChapter)
    playBar_Focused =  PlayBarConfScaleSet(currentChapter_Left: focusedCurrChapterLeft, currentChapter_Right: focusedCurrChapterRight,
                                           nonCurrentChapter_Left: nonCurrChapterLeft, nonCurrentChapter_Right: nonCurrChapterRight)

    let volumeBelow100_Left = BarConfScaleSet(imgPadding: barImgPadding, imgHeight: verticalPaddingTotal + maxVolBarHeightNeeded,
                                              barHeight: barHeight_Normal, interPillGapWidth: 0.0,
                                              fillColor: barColorLeft, pillCornerRadius: barCornerRadius_Normal)
    self.volumeBelow100_Left = volumeBelow100_Left
    let volumeBelow100_Right = volumeBelow100_Left.cloned(fillColor: barColorRight)
    self.volumeBelow100_Right = volumeBelow100_Right

    let volAbove100_Left_FillColor = BarFactory.exaggerateColor(volumeBelow100_Left.fillColor)
    let volAbove100_Right_FillColor = volumeBelow100_Right.fillColor //BarFactory.exaggerateColor(volumeBelow100_Right.fillColor)
    volumeAbove100_Left = volumeBelow100_Left.cloned(barHeight: barHeight_VolumeAbove100_Left,
                                                     fillColor: volAbove100_Left_FillColor)
    volumeAbove100_Right = volumeBelow100_Right.cloned(barHeight: barHeight_VolumeAbove100_Right,
                                                       fillColor: volAbove100_Right_FillColor)
  }

  func updateBarColorsFromPrefs() {
    BarFactory.shared = BarFactory()
  }

  /// `scale` should match `backingScaleFactor` from the current screen.
  /// This will either be `2.0` for Retina displays, or `1.0` for traditional displays.
  func volBarImgConf(scale: CGFloat, barWidth: CGFloat) -> VolBarImgConf {
    let below100Left = volumeBelow100_Left.getScale(scale)
    let imgWidth = (barWidth * scale) + (2 * below100Left.imgPadding)
    let imgSize = CGSize(width: imgWidth, height: below100Left.imgHeight)
    return VolBarImgConf(below100_Left: below100Left,
                         below100_Right: volumeBelow100_Right.getScale(scale),
                         above100_Left: volumeAbove100_Left.getScale(scale),
                         above100_Right: volumeAbove100_Right.getScale(scale),
                         imgSize: imgSize)
  }

  private static func barColorLeftFromPrefs() -> CGColor {
    let userSetting: Preference.SliderBarLeftColor = Preference.enum(for: .playSliderBarLeftColor)
    switch userSetting {
    case .gray:
      return NSColor.mainSliderBarLeft.cgColor
    default:
      return NSColor.controlAccentColor.cgColor
    }
  }

  // MARK: - Volume Bar

  func buildVolumeBarImage(darkMode: Bool, clearBG: Bool,
                           barWidth: CGFloat,
                           screen: NSScreen,
                           knobMinX: CGFloat, knobWidth: CGFloat,
                           currentValue: Double, maxValue: Double) -> CGImage {

    // - Set up calculations
    let scaleFactor = screen.backingScaleFactor
    let conf = volBarImgConf(scale: scaleFactor, barWidth: barWidth)

    let currentValueRatio = currentValue / maxValue
    let currentValuePointX = (conf.imgPadding + (currentValueRatio * conf.barWidth)).rounded()

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

    let hasLeft = leftClipMaxX - conf.imgPadding > 0.0
    let hasRight = rightClipMinX + conf.imgPadding < conf.imgWidth

    // If volume can exceed 100%, let's draw the part of the bar which is >100% differently
    let vol100PercentPointX = (conf.imgPadding + ((100.0 / maxValue) * conf.barWidth)).rounded()
    let barMaxX = conf.barMaxX

    let barImg = CGImage.buildBitmapImage(width: Int(conf.imgWidth), height: Int(conf.imgHeight)) { cgc in

      func drawEntireBar(_ barConf: BarConf, clipMinX: CGFloat, clipMaxX: CGFloat) {
        cgc.resetClip()
        cgc.clip(to: CGRect(x: clipMinX, y: 0,
                            width: clipMaxX - clipMinX,
                            height: barConf.imgHeight))

        addPillPath(cgc, minX: barConf.barMinX,
                    maxX: barMaxX,
                    barConf,
                    leftEdge: .noBorderingPill,
                    rightEdge: .noBorderingPill)
        cgc.clip()

        drawPill(cgc,
                 minX: barConf.barMinX,
                 maxX: barMaxX,
                 barConf,
                 leftEdge: .noBorderingPill,
                 rightEdge: .noBorderingPill)
      }

      var barConf = conf.below100_Left

      if hasLeft {  // Left of knob (i.e. "completed" section of bar)
        var minX = 0.0

        if vol100PercentPointX < leftClipMaxX {
          // Current volume > 100%. Finish drawing (< 100%) first.
          drawEntireBar(barConf, clipMinX: minX, clipMaxX: vol100PercentPointX)
          // Update for next segment:
          minX = vol100PercentPointX
          barConf = conf.above100_Left
        }

        drawEntireBar(barConf, clipMinX: minX, clipMaxX: leftClipMaxX)
      }

      if hasRight {  // Right of knob
        var minX = rightClipMinX
        if vol100PercentPointX <= rightClipMinX {
          barConf = conf.above100_Right
        } else {
          barConf = conf.below100_Right

          if vol100PercentPointX > rightClipMinX && vol100PercentPointX < conf.imgWidth {
            drawEntireBar(barConf, clipMinX: minX, clipMaxX: vol100PercentPointX)
            // Update for next segment:
            minX = vol100PercentPointX
            barConf = conf.above100_Right
          }
        }

        drawEntireBar(barConf, clipMinX: minX, clipMaxX: conf.imgWidth)
      }
    }
    
    return barImg
  }  // end func buildVolumeBarImage

  // MARK: - Play Bar

  /// `barWidth` does not include added leading or trailing margin
  func buildPlayBarImage(barWidth: CGFloat,
                         screen: NSScreen, darkMode: Bool, clearBG: Bool,
                         knobMinX: CGFloat, knobWidth: CGFloat, currentValueRatio: CGFloat,
                         durationSec: CGFloat, _ chapters: [MPVChapter], cachedRanges: [(Double, Double)],
                         currentPreviewTimeSec: Double?) -> CGImage {
    // - Set up calculations
    let scaleFactor = screen.backingScaleFactor

    let confSet = (currentPreviewTimeSec != nil ? playBar_Focused : playBar_Normal).forImg(scale: scaleFactor, barWidth: barWidth)

    let currentHoverX: CGFloat?
    if let currentPreviewTimeSec {
      currentHoverX = currentPreviewTimeSec / durationSec * confSet.barWidth
    } else {
      currentHoverX = nil
    }

    let currentValuePointX = (confSet.imgPadding + (currentValueRatio * confSet.barWidth)).rounded()

    // Determine clipping rects (pixel whitelists)
    let leftClipMaxX: CGFloat
    let rightClipMinX: CGFloat
    let hasSpaceForKnob = knobWidth > 0.0
    if hasSpaceForKnob {
      // - Will clip out the knob
      leftClipMaxX = (knobMinX - 1) * scaleFactor
      rightClipMinX = leftClipMaxX + (knobWidth * scaleFactor)
    } else {
      leftClipMaxX = currentValuePointX
      rightClipMinX = currentValuePointX
    }

    let hasLeft = leftClipMaxX - confSet.imgPadding > 0.0
    let hasRight = rightClipMinX + confSet.imgPadding < confSet.imgWidth

    let leftClipRect = CGRect(x: 0, y: 0,
                              width: leftClipMaxX,
                              height: confSet.imgHeight)

    let rightClipRect = CGRect(x: rightClipMinX, y: 0,
                               width: confSet.imgWidth - rightClipMinX,
                               height: confSet.imgHeight)

    let barImg = CGImage.buildBitmapImage(width: Int(confSet.imgWidth), height: Int(confSet.imgHeight)) { cgc in

      // Note that nothing is drawn for leading knobMarginRadius_Scaled or trailing knobMarginRadius_Scaled.
      // The empty space exists to make image offset calculations consistent (thus easier) between knob & bar images.
      var segsMaxX: [Double]
      if chapters.count > 0, durationSec > 0 {
        segsMaxX = chapters[1...].map{ $0.startTime / durationSec * confSet.barWidth }
      } else {
        segsMaxX = []
      }
      // Add right end of bar (don't forget to subtract left & right padding from img)
      let lastSegMaxX = confSet.imgWidth - (confSet.imgPadding * 2)
      segsMaxX.append(lastSegMaxX)

      var segIndex = 0
      var segMinX = confSet.imgPadding

      var leftEdge: PillEdgeType = .noBorderingPill
      var rightEdge: PillEdgeType = .bordersAnotherPill

      if hasLeft {
        // Left of knob
        cgc.resetClip()
        cgc.clip(to: leftClipRect)

        var done = false
        while !done && segIndex < segsMaxX.count {
          let segMaxX = segsMaxX[segIndex]
          if let currentHoverX, currentHoverX < segMaxX {
            // Is hovering in chapter
          }

          if segIndex == segsMaxX.count - 1 {
            // Is last pill
            rightEdge = .noBorderingPill
            done = true
          } else if segMaxX > leftClipMaxX || segMinX > leftClipMaxX {
            // Round the image corners by clipping out all drawing which is not in roundedRect (like using a stencil)
            addPillPath(cgc, minX: segMinX,
                        maxX: segMaxX,
                        confSet.currentChapter_Left,
                        leftEdge: leftEdge,
                        rightEdge: rightEdge)
            cgc.clip()
            done = true
          }
          drawPill(cgc, minX: segMinX, maxX: segMaxX,
                   confSet.currentChapter_Left,
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

          drawPill(cgc,
                   minX: segMinX, maxX: segMaxX,
                   confSet.currentChapter_Right,
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

    let cacheImg = CGImage.buildBitmapImage(width: Int(confSet.imgWidth), height: Int(confSet.imgHeight)) { cgc in
      if hasSpaceForKnob {
        // Apply clip (pixel whitelist) to avoid drawing over the knob
        cgc.clip(to: [leftClipRect, rightClipRect])
      }

      var rectsLeft: [NSRect] = []
      var rectsRight: [NSRect] = []
      for cachedRange in cachedRanges.sorted(by: { $0.0 < $1.0 }) {
        let startX: CGFloat = cachedRange.0 / durationSec * confSet.barWidth
        let endX: CGFloat = cachedRange.1 / durationSec * confSet.barWidth
        if startX > leftClipMaxX {
          rectsRight.append(CGRect(x: startX, y: confSet.imgPadding,
                                   width: endX - startX, height: confSet.currentChapter_Left.barHeight))
        } else if endX > leftClipMaxX {
          rectsLeft.append(CGRect(x: startX, y: confSet.imgPadding,
                                  width: leftClipMaxX - startX, height: confSet.currentChapter_Left.barHeight))

          let start2ndX = leftClipMaxX
          rectsRight.append(CGRect(x: start2ndX, y: confSet.imgPadding,
                                   width: endX - start2ndX, height: confSet.currentChapter_Right.barHeight))
        } else {
          rectsLeft.append(CGRect(x: startX, y: confSet.imgPadding,
                                  width: endX - startX, height: confSet.currentChapter_Right.barHeight))
        }
      }

      cgc.setFillColor(leftCachedColor)
      cgc.fill(rectsLeft)
      cgc.setFillColor(rightCachedColor)
      cgc.fill(rectsRight)

      cgc.setBlendMode(.destinationIn)
      cgc.draw(barImg, in: CGRect(origin: .zero, size: confSet.imgSize))
    }

    return makeCompositeBarImg(barImg: barImg, highlightOverlayImg: cacheImg)
  }

  func heightNeeded(tallestBarHeight: CGFloat) -> CGFloat {
    return (2 * barImgPadding) + tallestBarHeight
  }

  /// Measured in points, not pixels!
  func imageRect(in drawRect: CGRect, tallestBarHeight: CGFloat) -> CGRect {
    let imgHeight = heightNeeded(tallestBarHeight: tallestBarHeight)
    // can be negative:
    let spareHeight = drawRect.height - imgHeight
    let y = drawRect.origin.y + (spareHeight * 0.5)
    return CGRect(x: drawRect.origin.x - barImgPadding, y: y,
                  width: drawRect.width + (2 * barImgPadding), height: imgHeight)
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
