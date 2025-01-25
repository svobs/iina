//
//  BarFactory.swift
//  iina
//
//  Created by Matt Svoboda on 2024-11-07.
//

/// In points, not pixels
fileprivate let barImgPadding: CGFloat = 1.0
fileprivate let barVerticalPaddingTotal = barImgPadding * 2

fileprivate extension CGColor {
  func exaggerated() -> CGColor {
    var leftCacheComps: [CGFloat] = []
    let numComponents = min(self.numberOfComponents, 3)
    for i in 0..<numComponents {
      leftCacheComps.append(min(1.0, self.components![i] * 1.8))
    }
    leftCacheComps.append(1.0)
    let colorSpace = self.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    return CGColor(colorSpace: colorSpace, components: leftCacheComps)!
  }
}

/// Draws slider bars, e.g., play slider & volume slider.
/// 
/// In the future, the sliders should be entirely custom, instead of relying on legacy `NSSlider`. Then the knob & slider can be
/// implemented via their own separate `CALayer`s which should enable more optimization opportunities. It's not been tested whether drawing
/// into (possibly cached) `CGImage`s as this class currently does delivers any improved performance (or is even slower)...
class BarFactory {
  /// The current configuration for drawing bars, based on prefs.
  static var current = BarFactory()

  // MARK: - Init / Config

  var playBar_Normal:  PlayBarConfScaleSet
  var playBar_Focused:  PlayBarConfScaleSet

  var volBar_Normal: VolBarConfScaleSet
  var volBar_Focused: VolBarConfScaleSet

  let maxPlayBarHeightNeeded: CGFloat
  let maxVolBarHeightNeeded: CGFloat

  private var leftCachedColor: CGColor
  private var rightCachedColor: CGColor

  init() {
    let disableRoundedCorners = !Preference.bool(for: .roundCornersInSliders)
    func cornerRadius(for barHeight: CGFloat) -> CGFloat {
      guard disableRoundedCorners else { return 0.0 }
      return barHeight * 0.5
    }

    // CONSTANTS: All in points (not pixels).
    // Make sure these are even numbers! Otherwise bar will be antialiased on non-Retina displays

    // - PlaySlider & VolumeSlider both:

    let barHeight_Normal: CGFloat = 3.0
    let barCornerRadius_Normal = cornerRadius(for: barHeight_Normal)

    let barColorLeft = BarFactory.barColorLeftFromPrefs()
    leftCachedColor = barColorLeft.exaggerated()

    let barColorRight = NSColor.mainSliderBarRight.cgColor
    rightCachedColor = barColorRight.exaggerated()

    // - PlaySlider:

    let chapterGapWidth: CGFloat = 1.5

    let barHeight_FocusedCurrChapter: CGFloat = 9.0
    let barCornerRadius_FocusedCurrChapter = cornerRadius(for: barHeight_FocusedCurrChapter)

    /// Focused AND [(has more than 1 chapter, but not the current chapter) OR (only one chapter)]:
    let barHeight_FocusedNonCurrChapter: CGFloat = 5.0
    let barCornerRadius_FocusedNonCurrChapter = cornerRadius(for: barHeight_FocusedNonCurrChapter)

    let maxPlayBarHeightNeeded = max(barHeight_Normal, barHeight_FocusedCurrChapter, barHeight_FocusedNonCurrChapter)
    self.maxPlayBarHeightNeeded = maxPlayBarHeightNeeded

    // - VolumeSlider:

    let barHeight_VolumeAbove100_Left: CGFloat = barHeight_Normal
    let barHeight_VolumeAbove100_Right: CGFloat = barHeight_VolumeAbove100_Left * 0.5
    let barCornerRadius_VolumeAbove100_Left = cornerRadius(for: barHeight_VolumeAbove100_Left)
    let barCornerRadius_VolumeAbove100_Right = cornerRadius(for: barHeight_VolumeAbove100_Right)

    let barHeight_Volume_Focused: CGFloat = 5.0
    let barHeight_Focused_VolumeAbove100_Left: CGFloat = 7.0
    let barHeight_Focused_VolumeAbove100_Right: CGFloat = barHeight_Normal
    let barCornerRadius_Volume_Focused = cornerRadius(for: barHeight_Volume_Focused)
    let barCornerRadius_Focused_VolumeAbove100_Left = cornerRadius(for: barHeight_Focused_VolumeAbove100_Left)
    let barCornerRadius_Focused_VolumeAbove100_Right = cornerRadius(for: barHeight_Focused_VolumeAbove100_Right)

    let maxVolBarHeightNeeded = max(barHeight_Normal, barHeight_VolumeAbove100_Left, barHeight_VolumeAbove100_Right,
                                    barHeight_Volume_Focused, barHeight_Focused_VolumeAbove100_Left, barHeight_Focused_VolumeAbove100_Right)
    self.maxVolBarHeightNeeded = maxVolBarHeightNeeded

    // - PlaySlider config sets

    let playNormalLeft = BarConfScaleSet(imgPadding: barImgPadding, imgHeight: barVerticalPaddingTotal + maxPlayBarHeightNeeded,
                                         barHeight: barHeight_Normal, interPillGapWidth: chapterGapWidth,
                                         fillColor: barColorLeft, pillCornerRadius: barCornerRadius_Normal)
    let playNormalRight = playNormalLeft.cloned(fillColor: barColorRight)
    rightCachedColor = barColorRight.exaggerated()

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

    // - VolumeSlider config sets

    let volumeBelow100_Left = BarConfScaleSet(imgPadding: barImgPadding, imgHeight: barVerticalPaddingTotal + maxVolBarHeightNeeded,
                                              barHeight: barHeight_Normal, interPillGapWidth: 0.0,
                                              fillColor: barColorLeft, pillCornerRadius: barCornerRadius_Normal)
    let volumeBelow100_Right = volumeBelow100_Left.cloned(fillColor: barColorRight)

    let volAbove100_Left_FillColor = volumeBelow100_Left.fillColor.exaggerated()
    let volAbove100_Right_FillColor = volumeBelow100_Right.fillColor // volumeBelow100_Right.fillColor.exaggerated()
    let volumeAbove100_Left = volumeBelow100_Left.cloned(barHeight: barHeight_VolumeAbove100_Left,
                                                         fillColor: volAbove100_Left_FillColor,
                                                         pillCornerRadius: barCornerRadius_VolumeAbove100_Left)
    let volumeAbove100_Right = volumeBelow100_Right.cloned(barHeight: barHeight_VolumeAbove100_Right,
                                                           fillColor: volAbove100_Right_FillColor,
                                                           pillCornerRadius: barCornerRadius_VolumeAbove100_Right)

    volBar_Normal = VolBarConfScaleSet(volumeBelow100_Left: volumeBelow100_Left,
                                       volumeBelow100_Right: volumeBelow100_Right,
                                       volumeAbove100_Left: volumeAbove100_Left,
                                       volumeAbove100_Right: volumeAbove100_Right)

    volBar_Focused = VolBarConfScaleSet(volumeBelow100_Left: volumeBelow100_Left.cloned(barHeight: barHeight_Volume_Focused, pillCornerRadius: barCornerRadius_Volume_Focused),
                                        volumeBelow100_Right: volumeBelow100_Right.cloned(barHeight: barHeight_Volume_Focused, pillCornerRadius: barCornerRadius_Volume_Focused),
                                        volumeAbove100_Left: volumeAbove100_Left.cloned(barHeight: barHeight_Focused_VolumeAbove100_Left, pillCornerRadius: barCornerRadius_Focused_VolumeAbove100_Left),
                                        volumeAbove100_Right: volumeAbove100_Right.cloned(barHeight: barHeight_Focused_VolumeAbove100_Right, pillCornerRadius: barCornerRadius_Focused_VolumeAbove100_Right))
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

  func updateBarStylesFromPrefs() {
    // Just replace the whole instance:
    BarFactory.current = BarFactory()
  }

  // MARK: - Volume Bar

  func buildVolumeBarImage(darkMode: Bool, clearBG: Bool, useFocusEffect: Bool,
                           barWidth: CGFloat,
                           screen: NSScreen,
                           knobMinX: CGFloat, knobWidth: CGFloat,
                           currentValue: Double, maxValue: Double,
                           currentPreviewValue: CGFloat? = nil) -> CGImage {

    // - Set up calculations
    let scaleFactor = screen.backingScaleFactor
    let conf = (useFocusEffect ? volBar_Focused : volBar_Normal).forImg(scale: scaleFactor, barWidth: barWidth)

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

        barConf.addPillPath(cgc, minX: barConf.barMinX,
                            maxX: barMaxX,
                            leftEdge: .noBorderingPill,
                            rightEdge: .noBorderingPill)
        cgc.clip()

        barConf.drawPill(cgc,
                         minX: barConf.barMinX,
                         maxX: barMaxX,
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
                         screen: NSScreen, darkMode: Bool, useFocusEffect: Bool,
                         knobMinX: CGFloat, knobWidth: CGFloat, currentValueRatio: CGFloat,
                         durationSec: CGFloat, _ chapters: [MPVChapter], cachedRanges: [(Double, Double)],
                         currentPreviewTimeSec: Double?) -> CGImage {
    // - Set up calculations
    let scaleFactor = screen.backingScaleFactor

    let imgConf = (useFocusEffect ? playBar_Focused : playBar_Normal).forImg(scale: scaleFactor, barWidth: barWidth)

    let currentHoverX: CGFloat?
    if let currentPreviewTimeSec {
      currentHoverX = currentPreviewTimeSec / durationSec * imgConf.barWidth
    } else {
      currentHoverX = nil
    }

    let currentValuePointX = (imgConf.imgPadding + (currentValueRatio * imgConf.barWidth)).rounded()

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

    let hasLeft = leftClipMaxX - imgConf.imgPadding > 0.0
    let hasRight = rightClipMinX + imgConf.imgPadding < imgConf.imgWidth

    let leftClipRect = CGRect(x: 0, y: 0,
                              width: leftClipMaxX,
                              height: imgConf.imgHeight)

    let rightClipRect = CGRect(x: rightClipMinX, y: 0,
                               width: imgConf.imgWidth - rightClipMinX,
                               height: imgConf.imgHeight)

    let barImg = CGImage.buildBitmapImage(width: Int(imgConf.imgWidth), height: Int(imgConf.imgHeight)) { cgc in

      // Note that nothing is drawn for leading knobMarginRadius_Scaled or trailing knobMarginRadius_Scaled.
      // The empty space exists to make image offset calculations consistent (thus easier) between knob & bar images.
      var segsMaxX: [Double]
      if chapters.count > 0, durationSec > 0 {
        segsMaxX = chapters[1...].map{ $0.startTime / durationSec * imgConf.barWidth }
      } else {
        segsMaxX = []
      }

      // Add right end of bar (don't forget to subtract left & right padding from img)
      let lastSegMaxX = imgConf.imgWidth - (imgConf.imgPadding * 2)
      segsMaxX.append(lastSegMaxX)

      var segIndex = 0
      var segMinX = imgConf.imgPadding

      var leftEdge: BarConf.PillEdgeType = .noBorderingPill
      var rightEdge: BarConf.PillEdgeType = .bordersAnotherPill

      if hasLeft {
        // Left of knob
        cgc.resetClip()
        cgc.clip(to: leftClipRect)

        var doneWithLeft = false
        while !doneWithLeft && segIndex < segsMaxX.count {
          let segMaxX = segsMaxX[segIndex]
          let conf: BarConf
          if let currentHoverX, segsMaxX.count > 1, currentHoverX > segMinX && currentHoverX < segMaxX {
            // Is hovering in chapter
            conf = imgConf.currentChapter_Left
          } else {
            conf = imgConf.nonCurrentChapter_Left
          }

          if segIndex == segsMaxX.count - 1 {
            // Is last pill
            rightEdge = .noBorderingPill
            doneWithLeft = true
          } else if segMaxX > leftClipMaxX || segMinX > leftClipMaxX {
            // Round the image corners by clipping out all drawing which is not in roundedRect (like using a stencil)
            conf.addPillPath(cgc, minX: segMinX,
                             maxX: segMaxX,
                             leftEdge: leftEdge,
                             rightEdge: rightEdge)
            cgc.clip()
            doneWithLeft = true
          }

          conf.drawPill(cgc, minX: segMinX, maxX: segMaxX,
                        leftEdge: leftEdge,
                        rightEdge: rightEdge)

          // Set for all but first pill
          leftEdge = .bordersAnotherPill

          if !doneWithLeft {
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

          let conf: BarConf
          if let currentHoverX, segsMaxX.count > 1, currentHoverX > segMinX && currentHoverX < segMaxX {
            conf = imgConf.currentChapter_Right
          } else {
            conf = imgConf.nonCurrentChapter_Right
          }

          if segIndex == segsMaxX.count - 1 {
            rightEdge = .noBorderingPill
          }

          conf.drawPill(cgc,
                        minX: segMinX, maxX: segMaxX,
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

    // Show cached ranges (if enabled).
    // Not sure how efficient this is...

    // First build overlay image which colors all the cached regions
    let cacheImg = CGImage.buildBitmapImage(width: Int(imgConf.imgWidth), height: Int(imgConf.imgHeight)) { cgc in
      if hasSpaceForKnob {
        // Apply clip (pixel whitelist) to avoid drawing over the knob
        cgc.clip(to: [leftClipRect, rightClipRect])
      }

      // First, just color the cached regions as crude rects which are at least as large as barImg…
      let maxBarHeightNeeded = imgConf.maxBarHeightNeeded
      let minY: CGFloat = (imgConf.imgHeight - maxBarHeightNeeded) * 0.5

      var rectsLeft: [NSRect] = []
      var rectsRight: [NSRect] = []
      for cachedRange in cachedRanges {
        let startX: CGFloat = cachedRange.0 / durationSec * imgConf.barWidth
        let endX: CGFloat = cachedRange.1 / durationSec * imgConf.barWidth
        if startX > leftClipMaxX {
          rectsRight.append(CGRect(x: startX, y: minY,
                                   width: endX - startX, height: maxBarHeightNeeded))
        } else if endX > leftClipMaxX {
          rectsLeft.append(CGRect(x: startX, y: minY,
                                  width: leftClipMaxX - startX, height: maxBarHeightNeeded))

          let start2ndX = leftClipMaxX
          rectsRight.append(CGRect(x: start2ndX, y: minY,
                                   width: endX - start2ndX, height: maxBarHeightNeeded))
        } else {
          rectsLeft.append(CGRect(x: startX, y: minY,
                                  width: endX - startX, height: maxBarHeightNeeded))
        }
      }

      cgc.setFillColor(leftCachedColor)
      cgc.fill(rectsLeft)
      cgc.setFillColor(rightCachedColor)
      cgc.fill(rectsRight)

      // Now use barImg as a mask, so that crude rects above are trimmed to match its silhoulette:
      cgc.setBlendMode(.destinationIn)
      cgc.draw(barImg, in: CGRect(origin: .zero, size: imgConf.imgSize))
    }

    // Now paste cacheImg into barImg and return the result:
    return CGImage.buildCompositeBarImg(barImg: barImg, highlightOverlayImg: cacheImg)
  }

  // MARK: - Other API functions

  func heightNeeded(tallestBarHeight: CGFloat) -> CGFloat {
    return barVerticalPaddingTotal + tallestBarHeight
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

  func drawBar(_ barImg: CGImage, in barRect: NSRect, tallestBarHeight: CGFloat) {
    var drawRect = imageRect(in: barRect, tallestBarHeight: tallestBarHeight)
    if #unavailable(macOS 11) {
      drawRect = NSRect(x: drawRect.origin.x,
                        y: drawRect.origin.y + 1,
                        width: drawRect.width,
                        height: drawRect.height - 2)
    }

    NSGraphicsContext.current!.cgContext.draw(barImg, in: drawRect)
  }

}
