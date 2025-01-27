//
//  Extensions.swift
//  iina
//
//  Created by lhc on 12/8/16.
//  Copyright © 2016 lhc. All rights reserved.
//

import Cocoa
import UniformTypeIdentifiers

infix operator %%

extension Int {
  /** Modulo operator. Swift's remainder operator (%) can return negative values, which is rarely what we want. */
  static  func %% (_ left: Int, _ right: Int) -> Int {
    return (left % right + right) % right
  }

  var isEven: Bool {
    return self % 2 == 0
  }
  var isOdd: Bool {
    return self % 2 != 0
  }

  func isBetweenInclusive(_ lowerBound: Int, and upperBound: Int) -> Bool {
    return self >= lowerBound && self <= upperBound
  }

}
import CryptoKit

extension NSSlider {

  /// Range of values the slider is configured to return.
  var range: ClosedRange<Double> { minValue...maxValue }

  /// Span of the range of values the slider is configured to return.
  var span: Double { maxValue - minValue }

  var progressRatio: Double {
    (doubleValue - minValue) / span
  }

  /**
   Returns the position of the knob's center point along the slider's track in window coordinates.

   This method calculates the horizontal position of the center of the slider's knob based on the slider's current value (`doubleValue`), the minimum and maximum values, and the slider's dimensions. It can be useful for custom drawing, animations, or hit detection related to the knob's position.

   - Returns: A `CGFloat` representing the x-coordinate of the knob's center along the slider's width.

   - Important: Ensure that the slider's `maxValue` is greater than `minValue`. An assertion is used to validate this.

   Example usage:
   ```swift
   let slider = NSSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
   let knobPosition = slider.centerOfKnobInWindowCoordX()
   print("The knob is positioned at x-coordinate: \(knobPosition)")
   ```
   */
  func centerOfKnobInWindowCoordX() -> CGFloat {
    let knobCenterInSliderCoordX = centerOfKnobInSliderCoordX()
    let knobCenterInWindowCoordX = self.convert(NSPoint(x: knobCenterInSliderCoordX, y: 0), to: nil).x
    return knobCenterInWindowCoordX
  }

  /// Returns the position of the knob's center point along the slider's track.
  /// See also `centerOfKnobInWindowX()`.
  func centerOfKnobInSliderCoordX() -> CGFloat {
    // The knob must always be within the bounds of the slider. With respect to the center of the knob,
    // this means that there is a space of (knobThickness / 2) at both sides where the center can never go.
    let knobCenterMinX = knobThickness / 2
    let knobRangeWidth = frame.width - knobThickness
    assert(maxValue > minValue)
    let knobPosX = knobCenterMinX + knobRangeWidth * CGFloat((doubleValue - minValue) / span)
    assert(knobPosX.clamped(to: knobCenterMinX...(knobCenterMinX + knobRangeWidth)) == knobPosX,
           "Invalid calculated centerOfKnobInSliderCoordX for slider: \(knobPosX)")
    return knobPosX
  }

  func computeProgressRatioGiven(centerOfKnobInSliderCoordX: CGFloat) -> CGFloat {
    let knobCenterMinX = knobThickness / 2
    let knobRangeWidth = frame.width - knobThickness
    let knobCenterMaxX = knobCenterMinX + knobRangeWidth
    // It's valid for the given X value to be in the (knobThickness / 2) regions near minX & maxX where the
    // knob can't go. This can happen if the user clicks near in this area. Just check & clamp to valid values.
    let centerOfKnobCorrected = centerOfKnobInSliderCoordX.clamped(to: knobCenterMinX...knobCenterMaxX)
    let ratio = Double((centerOfKnobCorrected - knobCenterMinX) / knobRangeWidth)
    assert(ratio.clamped(to: 0...1) == ratio, "Invalid calculated ratio for slider: \(ratio)")
    return ratio
  }

  func computeValueGiven(centerOfKnobInSliderCoordX: CGFloat) -> CGFloat {
    let ratio = computeProgressRatioGiven(centerOfKnobInSliderCoordX: centerOfKnobInSliderCoordX)
    let val = (ratio * span) + minValue
    assert(val.clamped(to: minValue...maxValue) == val,
           "Invalid calculated value for slider: \(val)")
    return val
  }

  func computeCenterOfKnobInSliderCoordXGiven(pointInWindow: NSPoint) -> CGFloat {
    let xOffsetInSlider = convert(pointInWindow, from: nil).x
    let knobCenterMinX = knobThickness / 2
    let knobRangeWidth = frame.width - knobThickness
    let knobCenterMaxX = knobCenterMinX + knobRangeWidth
    return xOffsetInSlider.clamped(to: knobCenterMinX...knobCenterMaxX)
  }
}

extension NSSegmentedControl {
  @discardableResult
  func selectSegment(withLabel label: String) -> Bool {
    for i in 0..<segmentCount {
      if self.label(forSegment: i) == label {
        self.selectedSegment = i
        return true
      }
    }
    Logger.log("Could not find segment with label \(label.quoted). Setting selection to -1", level: .verbose)
    self.selectedSegment = -1
    return false
  }
}

func - (lhs: NSPoint, rhs: NSPoint) -> NSPoint {
  return NSMakePoint(lhs.x - rhs.x, lhs.y - rhs.y)
}

extension CGPoint {
  /**
   Uses the Pythagorean theorem to calculate the distance between two points.

   This method calculates the straight-line distance (Euclidean distance) between the current point and another `CGPoint`. It is useful for measuring distances in a two-dimensional coordinate system, such as when working with points on a canvas or in a graphics context.

   - Parameter to: The target `CGPoint` to which the distance will be calculated.
   - Returns: A `CGFloat` representing the distance between the two points.

   Example usage:
   ```swift
   let pointA = CGPoint(x: 0, y: 0)
   let pointB = CGPoint(x: 3, y: 4)
   let distance = pointA.distance(to: pointB)
   print("Distance between pointA and pointB is \(distance)")  // Output: 5.0
   ```
   */
  func distance(to: CGPoint) -> CGFloat {
    return sqrt(pow(self.x - to.x, 2) + pow(self.y - to.y, 2))
  }
}

extension NSSize {

  var area: CGFloat {
    return width * height
  }

  /**
   Returns the aspect ratio (width divided by height) of the size.

   This property asserts that neither width nor height is zero, and then calculates the aspect ratio.

   - Returns: The aspect ratio of the size as a `CGFloat`.
   */
  var aspect: CGFloat {
    if width == 0 || height == 0 {
      Logger.log("Returning 1 for NSSize aspectRatio because width or height is 0", level: .warning)
      return 1
    }
    return width / height
  }

  var mpvAspect: CGFloat {
    return Aspect.mpvPrecision(of: aspect)
  }

  /**
   Resizes the current size to be no smaller than a given minimum size while maintaining the same aspect ratio.

   This method checks if the current size is already larger than the given minimum size, and if not, it resizes the current size to the minimum size, preserving the aspect ratio.

   - Parameter minSize: The minimum size that the current size should satisfy.
   - Returns: The resized `NSSize` that satisfies the minimum size requirement while keeping the same aspect ratio.
   */
  func satisfyMinSizeWithSameAspectRatio(_ minSize: NSSize) -> NSSize {
    if width >= minSize.width && height >= minSize.height {
      return self
    } else {
      return grow(toSize: minSize)
    }
  }

  /**
   Resizes the current size to be no larger than a given maximum size while maintaining the same aspect ratio.

   This method checks if the current size is already smaller than the given maximum size, and if not, it resizes the current size to the maximum size, preserving the aspect ratio.

   - Parameter maxSize: The maximum size that the current size should satisfy.
   - Returns: The resized `NSSize` that satisfies the maximum size requirement while keeping the same aspect ratio.
   */
  func satisfyMaxSizeWithSameAspectRatio(_ maxSize: NSSize) -> NSSize {
    if width <= maxSize.width && height <= maxSize.height {
      return self
    } else {
      return shrink(toSize: maxSize)
    }
  }

  /**
   Crops the current size to fit within a target aspect ratio, reducing either the width or height to match the aspect ratio of the target rectangle.

   - Parameter aspectRect: A rectangle or size structure that contains the desired aspect ratio.
   - Returns: The cropped `NSSize` that fits within the given aspect ratio.
   */
  func crop(withAspect targetAspect: CGFloat) -> NSSize {
    if aspect > targetAspect {  // self is wider, crop width, use same height
      return NSSize(width: round(height * targetAspect), height: height)
    } else {
      return NSSize(width: width, height: round(width / targetAspect))
    }
  }

  func getCropRect(withAspect aspect: CGFloat) -> NSRect {
    let croppedSize = crop(withAspect: aspect)
    let cropped = NSMakeRect(round((width - croppedSize.width) / 2),
                             round((height - croppedSize.height) / 2),
                             croppedSize.width,
                             croppedSize.height)
    return cropped
  }

  func getCropRect(withAspect aspect: Aspect) -> NSRect {
    let croppedSize = crop(withAspect: aspect.value)
    let cropped = NSMakeRect(round((width - croppedSize.width) / 2),
                             round((height - croppedSize.height) / 2),
                             croppedSize.width,
                             croppedSize.height)
    return cropped
  }

  func expand(withAspect targetAspect: Double) -> NSSize {
    if aspect < targetAspect {  // self is taller, expand width, use same height
      return NSSize(width: height * targetAspect, height: height)
    } else {
      return NSSize(width: width, height: width / targetAspect)
    }
  }

  /**
   Given another size S, returns a size that:

   - maintains the same aspect ratio;
   - has same height or/and width as S;
   - always bigger than S.

   - parameter toSize: The given size S.

   ```
   +--+------+--+
   |  |      |  |
   |  |  S   |  |<-- The result size
   |  |      |  |
   +--+------+--+
   ```
   */
  func grow(toSize size: NSSize) -> NSSize {
    if width == 0 || height == 0 {
      return size
    }
    let sizeAspect = size.aspect
    var newSize: NSSize
    if aspect > sizeAspect {  // self is wider, grow to meet height
      newSize = NSSize(width: size.height * aspect, height: size.height)
    } else {
      newSize = NSSize(width: size.width, height: size.width / aspect)
    }
    Logger.log("Growing \(self) to size \(size). Derived aspect: \(sizeAspect); result: \(newSize)", level: .verbose)
    return newSize
  }

  /**
   Given another size S, returns a size that:

   - maintains the same aspect ratio;
   - has same height or/and width as S;
   - always smaller than S.

   - parameter toSize: The given size S.

   ```
   +--+------+--+
   |  |The   |  |
   |  |result|  |<-- S
   |  |size  |  |
   +--+------+--+
   ```
   */
  func shrink(toSize size: NSSize) -> NSSize {
    if width == 0 || height == 0 {
      return size
    }
    let sizeAspect = size.aspect
    var newSize: NSSize
    if aspect < sizeAspect { // self is taller, shrink to meet height
      newSize = NSSize(width: size.height * aspect, height: size.height)
    } else {
      newSize = NSSize(width: size.width, height: size.width / aspect)
    }
    Logger.log("Shrinking \(self) to size \(size). Derived aspect: \(sizeAspect); result: \(newSize)", level: .verbose)
    return newSize
  }
  /**
   Returns a `NSRect` that represents the size centered within the given `NSRect`.

   This method calculates a new rectangle (`NSRect`) where the current size (`NSSize`) is centered inside the provided rectangle (`rect`). It is useful when you need to center one view or size within another, maintaining its dimensions.

   - Parameter rect: The rectangle within which to center the current size.
   - Returns: A `NSRect` where the current size is centered inside the given rectangle.

   Example usage:
   ```swift
   let size = NSSize(width: 100, height: 50)
   let containerRect = NSRect(x: 0, y: 0, width: 300, height: 200)
   let centeredRect = size.centeredRect(in: containerRect)
   print(centeredRect)  // Output: NSRect(x: 100.0, y: 75.0, width: 100.0, height: 50.0)
   ```
   */
  func centeredRect(in rect: NSRect) -> NSRect {
    return NSRect(x: rect.origin.x + (rect.width - width) / 2,
                  y: rect.origin.y + (rect.height - height) / 2,
                  width: width,
                  height: height)
  }
  /**
   Multiplies both the width and height of the current size by a given multiplier.
   */
  static func * (operand: NSSize, multiplier: CGFloat) -> NSSize {
    return NSSize(width: operand.width * multiplier, height: operand.height * multiplier)
  }
  /**
   Adds a given value to both the width and height of the current size.
   */
  func multiplyThenRound(_ multiplier: CGFloat) -> NSSize {
    return NSSize(width: (width * multiplier).rounded(), height: (height * multiplier).rounded())
  }

  static func + (augend: NSSize, addend: CGFloat) -> NSSize {
    return NSSize(width: augend.width + addend, height: augend.height + addend)
  }

  static func - (minuend: NSSize, subtrahend: NSSize) -> NSSize {
    return NSSize(width: minuend.width - subtrahend.width, height: minuend.height - subtrahend.height)
  }
}


extension NSRect {

  init(vertexPoint pt1: NSPoint, and pt2: NSPoint) {
    self.init(x: min(pt1.x, pt2.x),
              y: min(pt1.y, pt2.y),
              width: abs(pt1.x - pt2.x),
              height: abs(pt1.y - pt2.y))
  }

  func clone(size newSize: NSSize) -> NSRect {
    return NSRect(origin: self.origin, size: newSize)
  }

  func addingTo( top: CGFloat = 0,  trailing: CGFloat = 0, bottom: CGFloat = 0,  leading: CGFloat = 0) -> NSRect {
    return NSRect(x: origin.x - leading, y: origin.y - bottom, width: width + leading + trailing, height: height + top + bottom)
  }

  func subtractingFrom( top: CGFloat = 0,  trailing: CGFloat = 0, bottom: CGFloat = 0,  leading: CGFloat = 0) -> NSRect {
    return addingTo(top: -top, trailing: -trailing, bottom: -bottom, leading: -leading)
  }

  func centeredResize(to newSize: NSSize) -> NSRect {
    var newX = origin.x - (newSize.width - size.width) / 2
    var newY = origin.y - (newSize.height - size.height) / 2
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
    
    // resizes x and y values so the window always stays within a valid screenFrame
    if screenFrame != NSRect.zero {
      newX = max(min(newX, screenFrame.maxX - newSize.width), screenFrame.minX)
      newY = max(min(newY, screenFrame.maxY - newSize.height), screenFrame.minY)
    }
    return NSRect(x: newX, y: newY, width: newSize.width, height: newSize.height)
  }

  func constrain(in biggerRect: NSRect) -> NSRect {
    // new size, keeping aspect ratio
    var newSize = size
    if newSize.width > biggerRect.width || newSize.height > biggerRect.height {
      /// We should have adjusted the rect's size before getting here. Using `shrink()` is not always 100% correct.
      /// If in debug environment, fail fast. Otherwise log and continue.
      assert(false, "Rect \(newSize) should already be <= rect in which it is being constrained (\(biggerRect))")
      Logger.log("Rect \(newSize) is larger than rect in which it is being constrained (\(biggerRect))! Will attempt to resize but it may be imprecise.")
      newSize = size.shrink(toSize: biggerRect.size)
    }
    // new origin
    var newOrigin = origin
    if newOrigin.x < biggerRect.origin.x {
      newOrigin.x = biggerRect.origin.x
    }
    if newOrigin.y < biggerRect.origin.y {
      newOrigin.y = biggerRect.origin.y
    }
    if newOrigin.x + width > biggerRect.origin.x + biggerRect.width {
      newOrigin.x = biggerRect.origin.x + biggerRect.width - width
    }
    if newOrigin.y + height > biggerRect.origin.y + biggerRect.height {
      newOrigin.y = biggerRect.origin.y + biggerRect.height - height
    }
    return NSRect(origin: newOrigin, size: newSize)
  }
}

extension NSPoint {
  func constrained(to rect: NSRect) -> NSPoint {
    return NSMakePoint(x.clamped(to: rect.minX...rect.maxX), y.clamped(to: rect.minY...rect.maxY))
  }
}

extension Array {
  subscript(at index: Index) -> Element? {
    if indices.contains(index) {
      return self[index]
    } else {
      return nil
    }
  }
}

class ContextMenuItem: NSMenuItem {
  let targetRows: IndexSet

  init(targetRows: IndexSet, title: String, action: Selector?, keyEquivalent: String) {
    self.targetRows = targetRows
    super.init(title: title, action: action, keyEquivalent: keyEquivalent)
  }

  required init(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented for ContextMenuItem")
  }
}

extension NSMenu {
  @discardableResult
  func addItem(forRows targetRows: IndexSet? = nil, withTitle string: String, action selector: Selector? = nil, target: AnyObject? = nil,
               tag: Int? = nil, obj: Any? = nil, stateOn: Bool = false, enabled: Bool = true) -> NSMenuItem {
    let menuItem: NSMenuItem
    if let targetRows = targetRows {
      menuItem = ContextMenuItem(targetRows: targetRows, title: string, action: selector, keyEquivalent: "")
    } else {
      menuItem = NSMenuItem(title: string, action: selector, keyEquivalent: "")
    }
    menuItem.tag = tag ?? -1
    menuItem.representedObject = obj
    menuItem.target = target
    menuItem.state = stateOn ? .on : .off
    menuItem.isEnabled = enabled
    self.addItem(menuItem)
    return menuItem
  }
}

extension CGFloat {
  var string: String {
    return Double(self).string
  }

  /// Formats the decimal for logging. Omits trailing zeroes & grouping separator.
  var logStr: String {
    return Double(self).logStr
  }

  var isInteger: Bool {
    return CGFloat(Int(self)) == self
  }
}

extension Bool {
  var yn: String {
    self ? "Y" : "N"
  }

  var yesno: String {
    self ? "YES" : "NO"
  }

  static func yn(_ yn: String?) -> Bool? {
    guard let yn = yn else { return nil }
    switch yn {
    case "Y", "y":
      return true
    case "N", "n":
      return false
    default:
      return nil
    }
  }
}

// Try to use Double instead of CGFloat as declared type - more compatible
extension Double {
  func prettyFormat() -> String {
    let rounded = (self * 1000).rounded() / 1000
    if rounded.truncatingRemainder(dividingBy: 1) == 0 {
      return "\(Int(rounded))"
    } else {
      return "\(rounded)"
    }
  }

  var isInteger: Bool {
    return Double(Int(self)) == self
  }

  var twoDecimalPlaces: String {
    return String(format: "%.2f", self)
  }

  var twoDigitHex: String {
    String(format: "%02X", self)
  }

  func isWithin(_ threshold: CGFloat, of other: CGFloat) -> Bool {
    return abs(self - other) <= threshold
  }

  func isBetweenInclusive(_ lowerBound: Double, and upperBound: Double) -> Bool {
    return self >= lowerBound && self <= upperBound
  }

  func truncatedTo1() -> Double {
    return Double(Int(self * 10)) / 10
  }

  func truncatedTo3() -> Double {
    return Double(Int(self * 1e3)) / 1e3
  }

  func truncatedTo5() -> Double {
    return Double(Int(self * 1e5)) / 1e5
  }

  func truncatedTo6() -> Double {
    return Double(Int(self * 1e6)) / 1e6
  }

  func roundedTo1() -> Double {
    let scaledUp = self * 1e1
    let scaledUpRounded = scaledUp.rounded(.toNearestOrAwayFromZero)
    let finalVal = scaledUpRounded / 1e1
    return finalVal
  }

  func roundedTo2() -> Double {
    let scaledUp = self * 1e2
    let scaledUpRounded = scaledUp.rounded(.toNearestOrAwayFromZero)
    let finalVal = scaledUpRounded / 1e2
    return finalVal
  }

  func roundedTo3() -> Double {
    let scaledUp = self * 1e3
    let scaledUpRounded = scaledUp.rounded(.toNearestOrAwayFromZero)
    let finalVal = scaledUpRounded / 1e3
    return finalVal
  }

  func roundedTo5() -> Double {
    let scaledUp = self * 1e5
    let scaledUpRounded = scaledUp.rounded(.toNearestOrAwayFromZero)
    let finalVal = scaledUpRounded / 1e5
    return finalVal
  }

  func roundedTo6() -> Double {
    let scaledUp = self * 1e6
    let scaledUpRounded = scaledUp.rounded(.toNearestOrAwayFromZero)
    let finalVal = scaledUpRounded / 1e6
    return finalVal
  }

  /// Formats this number as a decimal string, using the default locale.
  ///
  /// This should be used in most places where decimal numbers need to be printed. Do not rely on string interpolation alone
  /// because the number will not be localized.
  ///
  /// For example, if the user's locale formats numbers like `1.234.567,89` (in particular, using
  /// a comma to signify the decimal):
  /// ```
  /// let num: Double = 12.34
  /// let badStr = "Value is \(num)"          // badStr will *always* be "Value is 12.34"
  /// let goodStr = "Value is \(num.string)"  // goodStr will be "Value is 12,34"
  /// ```
  ///
  /// Currently the output string is limited to 15 digits after the decimal. This should be more than
  /// enough for any imaginable use right now, but the limit can and should be increased in the future if
  /// needed. (It's not clear what the maximum allowed value for `NumberFormatter.maximumFractionDigits`
  /// actually is. An attempt to set it equal to `NSIntegerMax` seemed to result in it being silently set to
  /// `6` instead.)
  var string: String {
    return fmtDecimalGroupingMaxFractionDigits15.string(from: self as NSNumber) ?? "NaN"
  }

  var logStr: String {
    return fmtDecimalNoGroupingMaxFractionDigits15.string(from: self as NSNumber) ?? "NaN"
  }

  /// Returns a "normalized" number string for the exclusive purpose of comparing two mpv aspect ratios while avoiding precision errors.
  /// Not pretty to put this here, but need to make this searchable & don't have time for a larger refactor.
  /// Addendum: we now assume 6 digits of precision.
  var mpvAspectString: String {
    return fmtStdDecimal.roundHalfDown_exactFracDigits[6].string(for: self)!
  }
}

extension NSInteger {
  func clamped(to range: Range<Self>) -> Self {
    if self < range.lowerBound {
      return range.lowerBound
    } else if self >= range.upperBound {
      return range.upperBound - 1
    } else {
      return self
    }
  }
}

extension Comparable {

  func clamped(to range: ClosedRange<Self>) -> Self {
    if self < range.lowerBound {
      return range.lowerBound
    } else if self > range.upperBound {
      return range.upperBound
    } else {
      return self
    }
  }
}

/// All the formatters here use "standardized" punctuation across locales. The formatted numbers:
/// - Always use period (".") for the decimal separator.
/// - Never use any punctuation to group large numbers.
struct StandardizedDecimalFormatters {
  /// Formats a number up to N digits after the decimal, truncated.
  let truncate_maxFracDigits: [NumberFormatter]
  /// Formats a number to exactly N digits after the decimal, truncated.
  let truncate_exactFracDigits: [NumberFormatter]

  /// Formats a number up to N digits after the decimal, rounded half down.
  let roundHalfDown_maxFracDigits: [NumberFormatter]

  /// Formats a number to exactly N digits after the decimal, rounded half down.
  let roundHalfDown_exactFracDigits: [NumberFormatter]

  init() {
    let decimalSeparator = "."
    var truncate_maxFracDigits: [NumberFormatter] = []
    for i in 0...6 {
      let fmt = NumberFormatter()
      fmt.decimalSeparator = decimalSeparator
      fmt.numberStyle = .decimal
      fmt.maximumFractionDigits = i
      fmt.usesGroupingSeparator = false
      fmt.roundingMode = .floor  
      truncate_maxFracDigits.append(fmt)
    }
    self.truncate_maxFracDigits = truncate_maxFracDigits

    var truncate_exactFracDigits: [NumberFormatter] = []
    for i in 0...6 {
      let fmt = NumberFormatter()
      fmt.decimalSeparator = decimalSeparator
      fmt.numberStyle = .decimal
      fmt.minimumFractionDigits = i
      fmt.maximumFractionDigits = i
      fmt.usesGroupingSeparator = false
      fmt.roundingMode = .floor
      truncate_exactFracDigits.append(fmt)
    }
    self.truncate_exactFracDigits = truncate_exactFracDigits

    var roundHalfDown_exactFracDigits: [NumberFormatter] = []
    for i in 0...6 {
      let fmt = NumberFormatter()
      fmt.decimalSeparator = decimalSeparator
      fmt.numberStyle = .decimal
      fmt.minimumFractionDigits = i
      fmt.maximumFractionDigits = i
      fmt.usesGroupingSeparator = false
      fmt.roundingMode = .halfDown
      roundHalfDown_exactFracDigits.append(fmt)
    }
    self.roundHalfDown_exactFracDigits = roundHalfDown_exactFracDigits

    var roundHalfDown_maxFracDigits: [NumberFormatter] = []
    for i in 0...6 {
      let fmt = NumberFormatter()
      fmt.decimalSeparator = decimalSeparator
      fmt.numberStyle = .decimal
      fmt.maximumFractionDigits = i
      fmt.usesGroupingSeparator = false
      fmt.roundingMode = .halfDown
      roundHalfDown_maxFracDigits.append(fmt)
    }
    self.roundHalfDown_maxFracDigits = roundHalfDown_maxFracDigits
  }
}

fileprivate let fmtStdDecimal = StandardizedDecimalFormatters()

/// Formatter for `Double`, `CGFloat`.
/// - Displays up to 15 digits after the decimal before rounding.
/// - Omits trailing zeroes.
/// - Uses grouping separator (e.g. comma) for large numbers.
fileprivate let fmtDecimalGroupingMaxFractionDigits15: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = true
  fmt.maximumSignificantDigits = 25
  fmt.minimumFractionDigits = 0
  fmt.maximumFractionDigits = 15
  fmt.usesSignificantDigits = false
  return fmt
}()

/// Formatter for `Double`, `CGFloat`. Similar to `fmtDecimalGroupingMaxFractionDigits15` but no gropuing separator.
/// - Displays up to 15 digits after the decimal before rounding.
/// - Omits trailing zeroes.
/// - Does not use grouping separator (e.g. comma) for large numbers.
fileprivate let fmtDecimalNoGroupingMaxFractionDigits15: NumberFormatter = {
  let fmt = NumberFormatter()
  fmt.numberStyle = .decimal
  fmt.usesGroupingSeparator = false
  fmt.maximumSignificantDigits = 25
  fmt.minimumFractionDigits = 0
  fmt.maximumFractionDigits = 15
  fmt.usesSignificantDigits = false
  return fmt
}()

extension CGRect: @retroactive CustomStringConvertible {
  public var description: String {
    return "(\(origin.x.logStr), \(origin.y.logStr), \(size.width.logStr)x\(size.height.logStr))"
  }
}

extension CGSize: @retroactive CustomStringConvertible {
  public var description: String {
    return "(\(width.logStr)x\(height.logStr))"
  }

  var widthInt: Int { Int(width) }
  var heightInt: Int { Int(height) }

  /// Finds the smallest box whose size matches the given `aspect` but with width >= `minWidth` & height >= `minHeight`.
  /// Note: `minWidth` & `minHeight` can be any positive integers. They do not need to match `aspect`.
  static func computeMinSize(withAspect aspect: CGFloat, minWidth: CGFloat, minHeight: CGFloat) -> CGSize {
    let sizeKeepingMinWidth = NSSize(width: minWidth, height: round(minWidth / aspect))
    if sizeKeepingMinWidth.height >= minHeight {
      return sizeKeepingMinWidth
    }

    let sizeKeepingMinHeight = NSSize(width: round(minHeight * aspect), height: minHeight)
    if sizeKeepingMinHeight.width >= minWidth {
      return sizeKeepingMinHeight
    }

    // Negative aspect, but just barely?
    if minWidth < minHeight {
      let width = round(minWidth * aspect)
      let sizeScalingUpWidth = NSSize(width: width, height: round(width / aspect))
      if sizeScalingUpWidth.width >= minWidth, sizeScalingUpWidth.height >= minHeight {
        return sizeScalingUpWidth
      }
    }
    let scaledUpHeight = round(minHeight * aspect)
    let sizeScalingUpHeight = NSSize(width: round(scaledUpHeight * aspect), height: scaledUpHeight)
    assert(sizeScalingUpHeight.width >= minWidth && sizeScalingUpHeight.height >= minHeight, "sizeScalingUpHeight \(sizeScalingUpHeight) < \(minWidth)x\(minHeight)")
    return sizeScalingUpHeight
  }

}

extension FloatingPoint {
  // TODO: replace with "bounded"
  func clamped(to range: Range<Self>) -> Self {
    if self < range.lowerBound {
      return range.lowerBound
    } else if self >= range.upperBound {
      return range.upperBound.nextDown
    } else {
      return self
    }
  }

  /// Formats as String, rounding the number to 2 digits after the decimal.
  /// Always displays 2 digits after the decimal.
  var string2FractionDigits: String {
    return fmtStdDecimal.truncate_exactFracDigits[2].string(for: self)!
  }

  /// Formats as String, truncating the number to 2 digits after the decimal
  var stringTrunc2f: String {
    return fmtStdDecimal.truncate_maxFracDigits[2].string(for: self)!
  }

  /// Formats as String, truncating the number to 3 digits after the decimal
  var stringTrunc3f: String {
    return fmtStdDecimal.truncate_maxFracDigits[3].string(for: self)!
  }

  /// Formats as String, truncating the number to 5 digits after the decimal
  var stringTrunc5f: String {
    return fmtStdDecimal.truncate_maxFracDigits[5].string(for: self)!
  }

  /// Formats as String, truncating the number to 6 digits after the decimal
  var stringTrunc6f: String {
    return fmtStdDecimal.truncate_maxFracDigits[6].string(for: self)!
  }

  /// Formats as String, rounding the number to 2 digits after the decimal
  var stringMaxFrac2: String {
    return fmtStdDecimal.roundHalfDown_maxFracDigits[2].string(for: self)!
  }

  /// Formats as String, rounding the number to 4 digits after the decimal
  var stringMaxFrac4: String {
    return fmtStdDecimal.roundHalfDown_maxFracDigits[4].string(for: self)!
  }

  /// Formats as String, rounding the number to 6 digits after the decimal
  var stringMaxFrac6: String {
    return fmtStdDecimal.roundHalfDown_maxFracDigits[6].string(for: self)!
  }
}

extension Date {
  var timeIntervalToNow: TimeInterval {
    return Date().timeIntervalSince(self)
  }
}

extension NSColor {
  var mpvColorString: String {
    get {
      return "\(self.redComponent)/\(self.greenComponent)/\(self.blueComponent)/\(self.alphaComponent)"
    }
  }

  convenience init?(mpvColorString: String) {
    let splitted = mpvColorString.split(separator: "/").map { (seq) -> Double? in
      return Double(String(seq))
    }
    // check nil
    if (!splitted.contains {$0 == nil}) {
      if splitted.count == 3 {  // if doesn't have alpha value
        self.init(red: CGFloat(splitted[0]!), green: CGFloat(splitted[1]!), blue: CGFloat(splitted[2]!), alpha: CGFloat(1))
      } else if splitted.count == 4 {  // if has alpha value
        self.init(red: CGFloat(splitted[0]!), green: CGFloat(splitted[1]!), blue: CGFloat(splitted[2]!), alpha: CGFloat(splitted[3]!))
      } else {
        return nil
      }
    } else {
      return nil
    }
  }
}


extension NSMutableAttributedString {
  convenience init?(linkTo url: String, text: String, font: NSFont) {
    self.init(string: text)
    let range = NSRange(location: 0, length: self.length)
    let nsurl = NSURL(string: url)!
    self.beginEditing()
    self.addAttribute(.link, value: nsurl, range: range)
    self.addAttribute(.font, value: font, range: range)
    self.endEditing()
  }

  // Adds the given attribute for the entire string
  func addAttrib(_ key: NSAttributedString.Key, _ value: Any) {
    self.addAttributes([key: value], range: NSRange(location: 0, length: self.length))
  }

  func addItalic(using font: NSFont?) {
    if let italicFont = makeItalic(font) {
      self.addAttrib(NSAttributedString.Key.font, italicFont)
    }
  }

  private func makeItalic(_ font: NSFont?) -> NSFont? {
    if let font = font {
      let italicDescriptor: NSFontDescriptor = font.fontDescriptor.withSymbolicTraits(NSFontDescriptor.SymbolicTraits.italic)
      return NSFont(descriptor: italicDescriptor, size: 0)
    }
    return nil
  }
}


extension NSData {
  var md5: String { Insecure.MD5.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}

extension Data {
  init<T> (bytesOf thing: T) where T: FixedWidthInteger {
    var copyOfThing = thing
    self.init(bytes: &copyOfThing, count: MemoryLayout<T>.size)
  }

  init(bytesOf num: Double) {
    var numCopy = num
    self.init(bytes: &numCopy, count: MemoryLayout<Double>.size)
  }

  init(bytesOf ts: timespec) {
    var mutablePointer = ts
    self.init(bytes: &mutablePointer, count: MemoryLayout<timespec>.size)
  }

  var md5: String {
    get {
      return (self as NSData).md5
    }
  }

  var chksum64: UInt64 {
    return withUnsafeBytes {
      $0.bindMemory(to: UInt64.self).reduce(0, &+)
    }
  }

  func saveToFolder(_ url: URL, filename: String) -> URL? {
    let fileUrl = url.appendingPathComponent(filename)
    do {
      try self.write(to: fileUrl)
    } catch {
      Utility.showAlert("error_saving_file", arguments: ["data", filename])
      return nil
    }
    return fileUrl
  }
}

extension FileHandle {
  func read<T>(type: T.Type /* To prevent unintended specializations */) -> T? {
    let size = MemoryLayout<T>.size
    let data = readData(ofLength: size)
    guard data.count == size else {
      return nil
    }
    return data.withUnsafeBytes {
      $0.bindMemory(to: T.self).first!
    }
  }
}

extension String {
  init(_ optionalInt: Int?) {
    if let optionalInt {
      self.init(optionalInt)
    } else {
      self.init("nil")
    }
  }

  var md5: String {
    get {
      return self.data(using: .utf8)!.md5
    }
  }

  // Returns a lookup token for the given string, which can be used in its place to privatize the log.
  // The pii.txt file is required to match the lookup token with the privateString.
  var pii: String {
    Logger.getOrCreatePII(for: self)
  }

  var isDirectoryAsPath: Bool {
    get {
      var re = ObjCBool(false)
      FileManager.default.fileExists(atPath: self, isDirectory: &re)
      return re.boolValue
    }
  }

  var lowercasedPathExtension: String {
    return (self as NSString).pathExtension.lowercased()
  }

  var mpvFixedLengthQuoted: String {
    return "%\(count)%\(self)"
  }

  func equalsIgnoreCase(_ other: String) -> Bool {
    return localizedCaseInsensitiveCompare(other) == .orderedSame
  }

  var quoted: String {
    return "\"\(self)\""
  }

  func containsWhitespaceOrNewlines() -> Bool {
    return rangeOfCharacter(from: .whitespacesAndNewlines) != nil
  }

  func deletingPrefix(_ prefix: String) -> String {
    guard self.hasPrefix(prefix) else { return self }
    return String(self.dropFirst(prefix.count))
  }

  mutating func deleteLast(_ num: Int) {
    removeLast(Swift.min(num, count))
  }

  func countOccurrences(of str: String, in range: Range<Index>?) -> Int {
    if let firstRange = self.range(of: str, options: [], range: range, locale: nil) {
      let nextRange = firstRange.upperBound..<self.endIndex
      return 1 + countOccurrences(of: str, in: nextRange)
    } else {
      return 0
    }
  }
}


extension CharacterSet {
  static let urlAllowed: CharacterSet = {
    var set = CharacterSet.urlHostAllowed
      .union(.urlUserAllowed)
      .union(.urlPasswordAllowed)
      .union(.urlPathAllowed)
      .union(.urlQueryAllowed)
      .union(.urlFragmentAllowed)
    set.insert(charactersIn: "%")
    return set
  }()
}


extension NSMenuItem {
  static let dummy = NSMenuItem(title: "Dummy", action: nil, keyEquivalent: "")

  var menuPathDescription: String {
    var ancestors: [String] = [self.title]
    var parent = self.parent
    while let parentItem = parent {
      ancestors.append(parentItem.title)
      parent = parentItem.parent
    }
    return ancestors.reversed().joined(separator: " → ")
  }

}


extension URL {
  var creationDate: Date? {
    (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
  }

  var isExistingDirectory: Bool {
    return (try? self.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
  }
}

extension RangeExpression where Bound == String.Index  {
  func nsRange<S: StringProtocol>(in string: S) -> NSRange { .init(self, in: string) }
}

extension NSTextField {

  func setHTMLValue(_ html: String) {
    let font = self.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let color = self.textColor ?? NSColor.labelColor
    if let data = html.data(using: .utf8), let str = NSMutableAttributedString(html: data,
                                                                               options: [.textEncodingName: "utf8"],
                                                                               documentAttributes: nil) {
      str.addAttributes([.font: font, .foregroundColor: color], range: NSMakeRange(0, str.length))
      self.attributedStringValue = str
    }
  }

  func setText(_ textContent: String, textColor: NSColor) {
    setFormattedText(stringValue: textContent, textColor: textColor)
    stringValue = textContent
    toolTip = textContent
  }

  func setFormattedText(stringValue: String, textColor: NSColor? = nil,
                        strikethrough: Bool = false, italic: Bool = false) {
    let attrString = NSMutableAttributedString(string: stringValue)

    let fgColor: NSColor
    if let textColor = textColor {
      // If using custom text colors, need to make sure `EditableTextFieldCell` is specified
      // as the class of the child cell in Interface Builder.
      fgColor = textColor
    } else {
      fgColor = NSColor.controlTextColor
    }
    self.textColor = fgColor

    if strikethrough {
      attrString.addAttrib(NSAttributedString.Key.strikethroughStyle, NSUnderlineStyle.single.rawValue)
    }

    if italic {
      attrString.addItalic(using: self.font)
    }
    self.attributedStringValue = attrString
  }

}

extension CGContext {
  /// Decorator which encloses `closure` with `saveGState` at start and `restoreGState` at end
  func withNestedGState<T>(_ closure: () throws -> T) rethrows -> T {
    saveGState()
    defer {
      restoreGState()
    }
    return try closure()
  }

  func drawRoundedRect(_ rect: NSRect, cornerRadius: CGFloat, fillColor: CGColor) {
    setFillColor(fillColor)
    // Clip its corners to round it:
    beginPath()
    addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
    closePath()
    clip()
    fill([rect])
  }
}


extension CGImage {
  /// Returns this image's data in PNG format, suitable for writing to a `.png` file on disk
  var pngData: Data? {
    guard let mutableData = CFDataCreateMutable(nil, 0),
          let destination = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, self, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return mutableData as Data
  }

  @discardableResult
  func saveAsPNG(fileURL: URL) -> Bool {
    let path = fileURL.path
    guard FileManager.default.createFile(atPath: fileURL.path, contents: nil, attributes: nil) else {
      Logger.log("Could not create PNG file: \(path.pii.quoted)", level: .error)
      return false
    }
    guard let file = try? FileHandle(forWritingTo: fileURL) else {
      Logger.log("Could not create PNG file for writing: \(path.pii.quoted)", level: .error)
      return false
    }

    guard let pngData else {
      Logger.log("Could not get PNG data from CGImage!", level: .error)
      return false
    }

    file.write(pngData)

    if #available(macOS 10.15, *) {
      do {
        try file.close()
      } catch {
        Logger.log("Failed to close file: \(path.pii.quoted)", level: .error)
      }
    }
    return true
  }

  // https://github.com/venj/Cocoa-blog-code/blob/master/Round%20Corner%20Image/Round%20Corner%20Image/NSImage%2BRoundCorner.m
  func roundCorners(cornerWidth: CGFloat, cornerHeight: CGFloat) -> CGImage {
    let size = CGSize(width: width, height: height)
    let rect = CGRect(origin: NSPoint.zero, size: size)
    if let context = CGContext(data: nil,
                             width: Int(size.width),
                             height: Int(size.height),
                             bitsPerComponent: 8,
                             bytesPerRow: 4 * Int(size.width),
                             space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
      context.beginPath()
      context.addPath(CGPath(roundedRect: rect, cornerWidth: cornerWidth, cornerHeight: cornerHeight, transform: nil))
      context.closePath()
      context.clip()
      context.draw(self, in: rect)

      if let composedImage = context.makeImage() {
        return composedImage
      }
    }
    return self
  }

  /// This uses CoreGraphics calls, which in tests was ~5x faster than using `NSAffineTransform` on `NSImage` directly
  func rotated(degrees: Int) -> CGImage {
    let imgRect = CGRect(origin: CGPointZero, size: CGSize(width: width, height: height))

    let angleRadians = degToRad(CGFloat(degrees))
    let imgRotateTransform = rotateTransformRectAroundCenter(rect: imgRect, angle: angleRadians)
    let rotatedImgFrame = CGRectApplyAffineTransform(imgRect, imgRotateTransform)


    let drawingCalls: (CGContext) -> Void = { [self] cgContext in
      let rotateContext = rotateTransformRectAroundCenter(rect: rotatedImgFrame, angle: angleRadians)
      cgContext.concatenate(rotateContext)
      cgContext.draw(self, in: imgRect)
    }
    return CGImage.buildBitmapImage(width: rotatedImgFrame.size.widthInt, height: rotatedImgFrame.size.heightInt, drawingCalls)
  }

  private func degToRad(_ degrees: CGFloat) -> CGFloat {
    return degrees * CGFloat.pi / 180
  }

  /// `cornerRadius`: if greater than 0, round the corners by this radius
  func resized(newWidth: Int, newHeight: Int, cornerRadius: CGFloat = 0) -> CGImage {
    guard newWidth != width || newHeight != height else {
      return self
    }

    guard newWidth > 0, newHeight > 0 else {
      Logger.fatal("NSImage.resized: invalid width (\(newWidth)) or height (\(newHeight)) - both must be greater than 0")
    }

    // Use raw CoreGraphics calls instead of their NS equivalents. They are > 10x faster, and only downside is that the image's
    // dimensions must be integer values instead of decimals.
    let newImage = CGImage.buildBitmapImage(width: Int(newWidth), height: Int(newHeight)) { cgContext in
      let outputRect = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
      if cornerRadius > 0.0 {
        cgContext.beginPath()
        cgContext.addPath(CGPath(roundedRect: outputRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        cgContext.closePath()
        cgContext.clip()
      }
      cgContext.draw(self, in: outputRect)
    }

    return newImage
  }

  func cropped(normalizedCropRect nRect: CGRect) -> CGImage {
    assert((nRect.width.clamped(to: 0.0...1.0) == nRect.width) && (nRect.height.clamped(to: 0.0...1.0) == nRect.height)
           && (nRect.origin.x.clamped(to: 0.0...1.0) == nRect.origin.x) && (nRect.origin.y.clamped(to: 0.0...1.0) == nRect.origin.y),
           "normalizedCropRect must be between 0 and 1 in all dimensions (found \(nRect))")
    // Scale cropRect to handle images larger than shown-on-screen size
    let w = Double(width)
    let h = Double(height)
    let cropRect = CGRect(x: nRect.origin.x * w,
                          y: nRect.origin.y * h,
                          width: nRect.size.width * w,
                          height: nRect.size.height * h)

    if let croppedImage: CGImage = cropping(to:cropRect) {
      return croppedImage
    }
    return self
  }


  func toNSImage() -> NSImage {
    NSImage(cgImage: self, size: size())
  }

  func size() -> CGSize {
    return CGSize(width: width, height: height)
  }

  /// Builds a bitmap image efficiently using CoreGraphics APIs.
  ///
  /// If it's found useful for any more situations, should put in its own class
  static func buildBitmapImage(width: Int, height: Int, _ drawingCalls: (CGContext) -> Void) -> CGImage {
    guard let compositeImageRep = CGImage.makeNewImgRep(width: width, height: height) else {
      Logger.fatal("DrawImageInBitmapImageContext: Failed to create NSBitmapImageRep!")
    }

    guard let context = NSGraphicsContext(bitmapImageRep: compositeImageRep) else {
      Logger.fatal("DrawImageInBitmapImageContext: Failed to create NSGraphicsContext!")
    }

    context.cgContext.interpolationQuality = .high
    drawingCalls(context.cgContext)

    return compositeImageRep.cgImage!
  }

  /// Creates RGB image with alpha channel
  static func makeNewImgRep(width: Int, height: Int) -> NSBitmapImageRep? {
    return NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: width,
      pixelsHigh: height,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: NSColorSpaceName.calibratedRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0)
  }

  static func buildCompositeBarImg(barImg: CGImage, highlightOverlayImg: CGImage, _ drawingCalls: ((CGContext) -> Void)? = nil) -> CGImage {
    let compositeImg = CGImage.buildBitmapImage(width: barImg.width, height: barImg.height) { cgc in
      let bounds = CGRect(origin: .zero, size: barImg.size())

      cgc.setBlendMode(.normal)
      cgc.draw(barImg, in: bounds)

      cgc.setBlendMode(.overlay)
      cgc.draw(highlightOverlayImg, in: bounds)

      if let drawingCalls {
        cgc.setBlendMode(.normal)
        drawingCalls(cgc)
      }
    }
    return compositeImg
  }


  /// returns the transform equivalent of rotating a rect around its center
  private func rotateTransformRectAroundCenter(rect:CGRect, angle:CGFloat) -> CGAffineTransform {
    let t = CGAffineTransformConcat(
      CGAffineTransformMakeTranslation(-rect.origin.x-rect.size.width*0.5, -rect.origin.y-rect.size.height*0.5),
      CGAffineTransformMakeRotation(angle)
    )
    return CGAffineTransformConcat(t, CGAffineTransformMakeTranslation(rect.size.width*0.5, rect.size.height*0.5))
  }

}

extension NSImage {
  /// Assuming this image is a file icon, gets the appropriate size with given height
  /// Thanks to "Sweeper" at https://stackoverflow.com/questions/62525921/how-to-get-a-high-resolution-app-icon-for-any-application-on-a-mac
  func getBestRepresentation(height: CGFloat) -> NSImage {
    var bestRep: NSImage = self
    if let imageRep = self.bestRepresentation(for: NSRect(x: 0, y: 0, width: height, height: height), context: nil, hints: nil) {
      bestRep = NSImage(size: imageRep.size)
      bestRep.addRepresentation(imageRep)
    }

    bestRep.size = NSSize(width: height, height: height)
    return bestRep
  }

  func tinted(_ tintColor: NSColor) -> NSImage {
    guard self.isTemplate else { return self }

    let image = self.copy() as! NSImage
    image.lockFocus()

    tintColor.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)

    image.unlockFocus()
    image.isTemplate = false

    return image
  }

  static func from(_ cgi: CGImage) -> NSImage {
    return NSImage(cgImage: cgi, size: NSSize(width: cgi.width, height: cgi.height))
  }

  var cgImage: CGImage? {
    var rect = CGRect.init(origin: .zero, size: self.size)
    return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
  }

  /// Derives a new width from the given height using this image's existing aspect.
  func deriveWidth(fromHeight height: CGFloat) -> CGFloat {
    return round(height * aspect)
  }

  var aspect: CGFloat {
    if size.width > 0 && size.height > 0 {
      let imageAspect = size.width / size.height
      return imageAspect
    }
    let cgImage = self.cgImage
    let imageAspect = CGFloat(cgImage!.width) / CGFloat(cgImage!.height)
    return imageAspect
  }

  func clipToCircle() -> NSImage {
    return roundCorners(cornerWidth: size.width * 0.5, cornerHeight: size.height * 0.5)
  }

  func roundCorners(withRadius radius: CGFloat) -> NSImage {
    return roundCorners(cornerWidth: radius, cornerHeight: radius)
  }

  func roundCorners(cornerWidth: CGFloat, cornerHeight: CGFloat) -> NSImage {
    if let cgImageNew = cgImage?.roundCorners(cornerWidth: cornerWidth, cornerHeight: cornerHeight) {
      return NSImage(cgImage: cgImageNew, size: self.size)
    }
    return self
  }

  /// This uses CoreGraphics calls, which in tests was ~5x faster than using `NSAffineTransform` on `NSImage` directly
  func rotated(degrees: Int) -> NSImage {
    if let cgImageNew = cgImage?.rotated(degrees: degrees) {
      return NSImage(cgImage: cgImageNew, size: size)
    }
    return self
  }

  func cropped(normalizedCropRect nRect: NSRect) -> NSImage {
    let croppedImage = cgImage!.cropped(normalizedCropRect: nRect)
    return NSImage(cgImage: croppedImage, size: NSSize(width: croppedImage.width, height: croppedImage.height))
  }

  /// `cornerRadius`: if greater than 0, round the corners by this radius
  func resized(newWidth: Int, newHeight: Int, cornerRadius: CGFloat = 0) -> NSImage {
    if let cgImageNew = cgImage?.resized(newWidth: newWidth, newHeight: newHeight, cornerRadius: cornerRadius) {
      return NSImage(cgImage: cgImageNew, size: NSSize(width: newWidth, height: newHeight))
    }
    return self
  }

  /// Try to find a SF Symbol. This function will iterate through the provided list of SF Symbol name list to and return the
  /// first available SF Symbol at runtime.
  ///
  /// Even though SF Symbol is available from macOS 11, we require at macOS 14 to use SF Symbol for the sake of consistency. On
  /// older systems (macOS 13 and below), because SF Symbols are not complete enough for our usage, we don't use them at all.
  /// If a better symbol is found in a later release of SF Symbol, place it at the first of the name list, so that IINA running
  /// on the latest version of macOS can make use of it; IINA running on a older version of macOS will fallback to a symbol
  /// in a previous release of SF Symbol. But the list of name must contain a symbol which is available in macOS 14 (SF Symbol 5).
  ///
  /// - Parameters:
  ///   - names: A list name of the SF Symbol. The name requires higher SF Symbol version must be at front, with fallback SF Symbol
  ///   names at later indexes. The last one must be available in macOS 14 (SF Symbol 5), otherwise a fatal error will occur.
  ///   - configuration: The symbol configuration for the SF symbol. Optional.
  @available(macOS 14.0, *)
  static func findSFSymbol(_ names: [String], withConfiguration configuration: NSImage.SymbolConfiguration? = nil) -> NSImage {
    for name in names {
      if let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
        if let configuration, let configured = symbol.withSymbolConfiguration(configuration) {
          return configured
        }
        return symbol
      }
    }
    fatalError("Could not find SF Symbol: \(names)")
  }

}


extension NSVisualEffectView {
  func roundCorners(withRadius cornerRadius: CGFloat) {
    layer?.cornerRadius = cornerRadius
  }

  func roundCorners() {
    let radius = suggestedRoundedCornerRadius()
    roundCorners(withRadius: radius)
  }
}


extension NSBox {
  static func horizontalLine() -> NSBox {
    let box = NSBox(frame: NSRect(origin: .zero, size: NSSize(width: 100, height: 1)))
    box.boxType = .separator
    return box
  }
}

extension NSEvent.Phase {
  var name: String {
    if self.contains(.began) {
      return "began"
    }
    if self.contains(.stationary) {
      return "stationary"
    }
    if self.contains(.changed) {
      return "changed"
    }
    if self.contains(.ended) {
      return "ended"
    }
    if self.contains(.mayBegin) {
      return "mayBegin"
    }
    if self.contains(.cancelled) {
      return "cancelled"
    }
    if self.isEmpty {
      return "none"
    }

    return "UNKNOWN"
  }
}

extension NSPasteboard {

  func getStringItems() -> [String] {
    guard let pasteboardItems else { return [] }
    return pasteboardItems.compactMap{$0.string(forType: .string)}
  }
}


extension NSPasteboard.PasteboardType {
  static let nsURL = NSPasteboard.PasteboardType("NSURL")
  static let nsFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")
  static let iinaPlaylistItem = NSPasteboard.PasteboardType("IINAPlaylistItem")
}


extension NSWindow.Level {
  static let iinaFloating = NSWindow.Level(NSWindow.Level.floating.rawValue - 1)
  static let iinaBlackScreen = NSWindow.Level(NSWindow.Level.mainMenu.rawValue + 1)
}

extension NSUserInterfaceItemIdentifier {
  static let isChosen = NSUserInterfaceItemIdentifier("IsChosen")
  static let trackId = NSUserInterfaceItemIdentifier("TrackId")
  static let trackName = NSUserInterfaceItemIdentifier("TrackName")
  static let key = NSUserInterfaceItemIdentifier("Key")
  static let value = NSUserInterfaceItemIdentifier("Value")
}

extension NSAppearance {
  convenience init?(iinaTheme theme: Preference.Theme) {
    switch theme {
    case .dark:
      self.init(named: .darkAqua)
    case .light:
      self.init(named: .aqua)
    default:
      return nil
    }
  }

  var isDark: Bool {
    return name == .darkAqua || name == .vibrantDark || name == .accessibilityHighContrastDarkAqua || name == .accessibilityHighContrastVibrantDark
  }

  // Performs the given closure with this appearance by temporarily making this the current appearance.
  func applyAppearanceFor<T>(_ closure: ()  -> T) -> T {
    if #available(macOS 11.0, *) {
      var result: T?
      self.performAsCurrentDrawingAppearance {
        result = closure()
      }
      return result!
    } else {
      let previousAppearance = NSAppearance.current
      NSAppearance.current = self
      defer {
        NSAppearance.current = previousAppearance
      }
      return closure()
    }
  }
}

extension NSApplication {
  /// Returns `PlayerWindowController` array for all open player windows.
  static var playerWindows: [PlayerWindowController] {
    return NSApp.windows.compactMap{ $0.windowController as? PlayerWindowController }.filter{ $0.isOpen }
  }
}

extension NSScreen {
  static func getOwnerScreenID(forPoint point: NSPoint) -> String? {
    for screen in NSScreen.screens {
      if screen.frame.contains(point) {
        return screen.screenID
      }
    }
    return nil
  }

  /// Apple's documentation says to use the origin (lower-left corner) to determine which screen the rect belongs to.
  /// But this doesn't seem intuitive because the window's title bar is traditionally the most important part of the window,
  /// and that is at the top of the rect. Let's use the upper-left corner instead.
  static func getOwnerScreenID(forViewRect viewRect: NSRect) -> String? {
    var x = viewRect.origin.x
    /// Subtract 1 from `maxY`. Seems that `contains(point)` will return `nil` for points at the very top (i.e., it excludes the topmost row).
    /// However, this only seems to happen if the screen being tested is directly above another one.
    let y = viewRect.maxY - 1
    var ownerScreenID = getOwnerScreenID(forPoint: NSPoint(x: x, y: y))
    if ownerScreenID == nil {
      // If upper-left corner is off screen, try using upper-right corner.
      // Should help avoid case where left side of window is slightly off screen & window ends up defaulting to main screen
      x = viewRect.maxX
      ownerScreenID = getOwnerScreenID(forPoint: NSPoint(x: x, y: y))
    }
    Logger.log("ViewRect=\(viewRect) → point=(\(x), \(y)) → owner screen is \(ownerScreenID?.debugDescription ?? "nil")", level: .verbose)
    return ownerScreenID
  }

  static func getOwnerOrDefaultScreenID(forViewRect viewRect: NSRect) -> String {
    return getOwnerScreenID(forViewRect: viewRect) ?? screens[0].screenID
  }

  static func getOwnerOrDefaultScreenID(forPoint point: NSPoint) -> String {
    return getOwnerScreenID(forPoint: point) ?? screens[0].screenID
  }

  static func forScreenID(_ screenID: String) -> NSScreen? {
    let splitted = screenID.split(separator: ":")
    guard splitted.count > 0, let displayID = UInt32(splitted[0]) else { return nil }
    if let screen = forDisplayID(displayID) {
      // TODO: better matching logic. There is no guarantee that displayId will be consistent for the same screen across launches
      if screen.screenID != screenID {
        Logger.log("NSScreen with displayID \(displayID) is not exact match! Search target was \(screenID.quoted), but found \(screen.screenID.quoted). It is possible the wrong screen is being returned", level: .error)
      }
      return screen
    }
    Logger.log("Failed to find an NSScreen for screenID \(screenID.quoted). Returning nil", level: .error)
    return nil
  }

  static func forDisplayID(_ displayID: UInt32) -> NSScreen? {
    for screen in NSScreen.screens {
      if screen.displayId == displayID {
        return screen
      }
    }
    return nil
  }

  static func getScreenOrDefault(screenID: String) -> NSScreen {
    if let screen = forScreenID(screenID) {
      return screen
    }

    Logger.log("Failed to find an NSScreen for screenID \(screenID.quoted). Returning default screen", level: .debug)
    return NSScreen.screens[0]
  }

  /// Height of the camera housing on this screen if this screen has an embedded camera.
  var cameraHousingHeight: CGFloat? {
    if #available(macOS 12.0, *) {
      return safeAreaInsets.top == 0.0 ? nil : safeAreaInsets.top
    } else {
      return nil
    }
  }

  var frameWithoutCameraHousing: NSRect {
    if #available(macOS 12.0, *) {
      let frame = self.frame
      return NSRect(origin: frame.origin, size: CGSize(width: frame.width, height: frame.height - safeAreaInsets.top))
    } else {
      return self.frame
    }
  }

  var hasCameraHousing: Bool {
    return (cameraHousingHeight ?? 0) > 0
  }

  var displayId: UInt32 {
    return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! UInt32
  }

  var screenID: String {
    if #available(macOS 10.15, *) {
      return "\(displayId):\(localizedName)"
    }
    return "\(displayId)"
  }

  // Returns nil on failure (not sure if success is guaranteed)
  var nativeResolution: CGSize? {
    // if there's a native resolution found in this method, that's more accurate than above
    guard let displayModes = CGDisplayCopyAllDisplayModes(displayId, nil) as? [CGDisplayMode] else {
      Logger.log("Failed to get CGDisplayModes for displayID \(displayId)! Returning nil", level: .warning)
      return nil
    }
    for mode in displayModes {
      let isNative = mode.ioFlags & UInt32(kDisplayModeNativeFlag) > 0
      if isNative {
        return CGSize(width: mode.width, height: mode.height)
      }
    }

    return nil
  }

  /// Gets the actual scale factor, because `NSScreen.backingScaleFactor` does not provide this.
  var screenScaleFactor: CGFloat {
    if let nativeSize = nativeResolution {
      return CGFloat(nativeSize.width) / frame.size.width
    }
    return 1.0  // default fallback
  }
}

extension NSWindow {

  /// Provides a unique window ID for reference by `UIState`.
  var savedStateName: String {
    if let playerController = windowController as? PlayerWindowController {
      // Not using AppKit autosave for player windows. Instead build ID based on player label
      return WindowAutosaveName.playerWindow(id: playerController.player.label).string
    }
    // Default to the AppKit autosave ID for all other windows.
    return frameAutosaveName
  }

  /// Return the screen to use by default for this window.
  ///
  /// This method searches for a screen to use in this order:
  /// - `window!.screen` The screen where most of the window is on; it is `nil` when the window is offscreen.
  /// - `NSScreen.main` The screen containing the window that is currently receiving keyboard events.
  /// - `NSScreen.screens[0]` The primary screen of the user’s system.
  ///
  /// `PlayerCore` caches players along with their windows. This window may have been previously used on an external monitor
  /// that is no longer attached. In that case the `screen` property of the window will be `nil`.  Apple documentation is silent
  /// concerning when `NSScreen.main` is `nil`.  If that is encountered the primary screen will be used.
  ///
  /// - returns: The default `NSScreen` for this window
  func selectDefaultScreen() -> NSScreen {
    if screen != nil {
      return screen!
    }
    if NSScreen.main != nil {
      return NSScreen.main!
    }
    return NSScreen.screens[0]
  }

  var screenScaleFactor: CGFloat {
    return selectDefaultScreen().screenScaleFactor
  }

  var isAnotherWindowInFullScreen: Bool {
    for winCon in NSApplication.playerWindows {
      if winCon.window != self, winCon.isFullScreen {
        return true
      }
    }
    return false
  }

  /// Excludes the Inspector window
  var isOnlyOpenWindow: Bool {
    if savedStateName == WindowAutosaveName.openFile.string && AppDelegate.shared.isShowingOpenFileWindow {
      return false
    }
    for window in NSApp.windows {
      if window != self, let knownWindowName = WindowAutosaveName(window.savedStateName), knownWindowName != .inspector, window.isOpen {
        return false
      }
    }
    Logger.log("Window is the only window currently open: \(savedStateName.quoted)", level: .verbose)
    return true
  }

  var isOpen: Bool {
    if let windowController = self.windowController as? PlayerWindowController, windowController.isOpen {
      return true
    } else if self.isVisible || self.isMiniaturized {
      return true
    }
    return false
  }

  func postWindowIsReadyToShow() {
    NotificationCenter.default.post(Notification(name: .windowIsReadyToShow, object: self))
  }

  func postWindowMustCancelShow() {
    NotificationCenter.default.post(Notification(name: .windowMustCancelShow, object: self))
  }
}


class IINAWindowController: NSWindowController {

  func openWindow(_ sender: Any?) {
    guard let window else {
      Logger.log("Cannot open window: no window object!", level: .error)
      return
    }

    let windowName = window.savedStateName
    if !Preference.bool(for: .isRestoreInProgress), !windowName.isEmpty {
      /// Make sure `windowsOpen` is updated. This patches certain possible race conditions during launch
      UIState.shared.windowsOpen.insert(windowName)
    }

    window.postWindowIsReadyToShow()
  }
}

extension NSOutlineView {
  // Use this instead of reloadData() if the table data needs to be reloaded but the row count is the same.
  // This will preserve the selection indexes (whereas reloadData() will not)
  func reloadExistingRows(reselectRowsAfter: Bool, usingNewSelection newRowIndexes: IndexSet? = nil) {
    let selectedRows = newRowIndexes ?? self.selectedRowIndexes
    Logger.log.verbose("Reloading existing rows\(reselectRowsAfter ? " (will re-select \(selectedRows) after)" : "")")
    reloadData(forRowIndexes: IndexSet(0..<numberOfRows), columnIndexes: IndexSet(0..<numberOfColumns))
    if reselectRowsAfter {
      // Fires change listener...
      selectApprovedRowIndexes(selectedRows, byExtendingSelection: false)
    }
  }

  func selectApprovedRowIndexes(_ newSelectedRowIndexes: IndexSet, byExtendingSelection: Bool = false) {
    // It seems that `selectionIndexesForProposedSelection` needs to be called explicitly
    // in order to keep enforcing selection rules.
    if let approvedRows = self.delegate?.outlineView?(self, selectionIndexesForProposedSelection: newSelectedRowIndexes) {
      Logger.log.verbose("Updating table selection to approved indexes: \(approvedRows.map{$0})")
      self.selectRowIndexes(approvedRows, byExtendingSelection: byExtendingSelection)
    } else {
      Logger.log.verbose("Updating table selection (no approval) to indexes: \(newSelectedRowIndexes.map{$0})")
      self.selectRowIndexes(newSelectedRowIndexes, byExtendingSelection: byExtendingSelection)
    }
  }


}

extension NSTableCellView {
  func setTitle(_ title: String, textColor: NSColor) {
    textField?.setText(title, textColor: textColor)
  }
}

extension NSScrollView {
  // Note: if false is returned, no scroll occurred, and the caller should pick a suitable default.
  // This is because NSScrollViews containing NSTableViews can be screwy and
  // have some arbitrary negative value as their "no scroll".
  func restoreVerticalScroll(key: Preference.Key) -> Bool {
    if UIState.shared.isRestoreEnabled {
      if let offsetY: Double = Preference.value(for: key) as? Double {
        Logger.log("Restoring vertical scroll to: \(offsetY)", level: .verbose)
        // Note: *MUST* use scroll(to:), not scroll(_)! Weird that the latter doesn't always work
        self.contentView.scroll(to: NSPoint(x: 0, y: offsetY))
        return true
      }
    }
    return false
  }

  // Adds a listener to record scroll position for next launch
  func addVerticalScrollObserver(key: Preference.Key) -> NSObjectProtocol {
    let observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                          object: self.contentView, queue: .main) { note in
      if let clipView = note.object as? NSClipView {
        let scrollOffsetY = clipView.bounds.origin.y
//        Logger.log("Saving Y scroll offset \(key.rawValue.quoted): \(scrollOffsetY)", level: .verbose)
        UIState.shared.set(scrollOffsetY, for: key)
      }
    }
    return observer
  }
  
  // Combines the previous 2 functions into one
  func restoreAndObserveVerticalScroll(key: Preference.Key, defaultScrollAction: () -> Void) -> NSObjectProtocol {
    if !restoreVerticalScroll(key: key) {
      Logger.log("Did not restore scroll (key: \(key.rawValue.quoted), isRestoreEnabled: \(UIState.shared.isRestoreEnabled)); will use default scroll action", level: .verbose)
      defaultScrollAction()
    }
    return addVerticalScrollObserver(key: key)
  }
}

extension Process {
  @discardableResult
  static func run(_ cmd: [String], at currentDir: URL? = nil) -> (process: Process, stdout: Pipe, stderr: Pipe) {
    guard cmd.count > 0 else {
      fatalError("Process.launch: the command should not be empty")
    }

    let (stdout, stderr) = (Pipe(), Pipe())
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cmd[0])
    process.currentDirectoryURL = currentDir
    process.arguments = [String](cmd.dropFirst())
    process.standardOutput = stdout
    process.standardError = stderr
    process.launch()
    process.waitUntilExit()

    return (process, stdout, stderr)
  }
}
/**
 Adds functionality to detect & report which queue the calling thread is in.
 From: https://stackoverflow.com/questions/17475002/get-current-dispatch-queue
 */
extension DispatchQueue {

  private struct QueueReference { weak var queue: DispatchQueue? }

  private static let key: DispatchSpecificKey<QueueReference> = {
    let key = DispatchSpecificKey<QueueReference>()
    setupSystemQueuesDetection(key: key)
    return key
  }()

  private static func _registerDetection(of queues: [DispatchQueue], key: DispatchSpecificKey<QueueReference>) {
    queues.forEach { $0.setSpecific(key: key, value: QueueReference(queue: $0)) }
  }

  private static func setupSystemQueuesDetection(key: DispatchSpecificKey<QueueReference>) {
    let queues: [DispatchQueue] = [
      .main,
      .global(qos: .background),
      .global(qos: .default),
      .global(qos: .unspecified),
      .global(qos: .userInitiated),
      .global(qos: .userInteractive),
      .global(qos: .utility)
    ]
    _registerDetection(of: queues, key: key)
  }
}

// MARK: public functionality

extension DispatchQueue {
  static func newDQ(label: String, qos: DispatchQoS) -> DispatchQueue {
    let q = DispatchQueue(label: label, qos: qos)
    registerDetection(of: q)
    return q
  }

  public static func registerDetection(of queue: DispatchQueue) {
    _registerDetection(of: [queue], key: key)
  }

  public static var currentQueueLabel: String? { current?.label }
  public static var current: DispatchQueue? { getSpecific(key: key)?.queue }

  /**
   USE THIS instead of `DispatchQueue.isExecutingIn(...))`: this will at least show an error msg.
   To work, the desired queue must first be registered with `registerDetection()` (or use `newDQ` to init)
   */
  public static func isExecutingIn(_ dq: DispatchQueue, logError: Bool = true) -> Bool {
    let isExpected = DispatchQueue.current == dq
    if !isExpected && logError {
      Logger.log.error{"ERROR We are in the wrong queue: '\(DispatchQueue.currentQueueLabel ?? "nil")' (expected: \(dq.label))"}
    }
    return isExpected
  }

  public static func isNotExecutingIn(_ dq: DispatchQueue, logError: Bool = true) -> Bool {
    let isExpected = DispatchQueue.current != dq
    if !isExpected && logError {
      Logger.log.error("ERROR We should not be executing in: '\(DispatchQueue.currentQueueLabel ?? "nil")'")
    }
    return isExpected
  }

  public static func execSyncOrAsyncIfNotIn(_ dq: DispatchQueue, execute work: @escaping @Sendable @convention(block) () -> Void) {
    if DispatchQueue.isExecutingIn(dq, logError: false) {
      work()
    } else {
      dq.async {
        work()
      }
    }
  }
}

extension NSViewController {
  /// Polyfill for MacOS 14.0's `loadViewIfNeeded()`.
  /// Load XIB if not already loaded. Prevents unboxing nils for `@IBOutlet` properties.
  func loadIfNeeded() {
    _ = self.view
  }
}

extension NSLayoutConstraint.Priority {
  static let minimum: NSLayoutConstraint.Priority = NSLayoutConstraint.Priority(rawValue: 1)
}

/// `NSShadow.shadowColor` is not dark enough. Use pure black.
fileprivate let defaultShadowColor: NSColor = .black
fileprivate let iconDefaultShadowBlurRadiusConstant: CGFloat = 0.5
extension NSControl {

  func addShadow(blurRadiusMultiplier: CGFloat = 0.0, blurRadiusConstant: CGFloat = iconDefaultShadowBlurRadiusConstant,
                 shadowOffsetMultiplier: CGFloat = 0.0,
                 xOffsetConstant: CGFloat = 0.0, yOffsetConstant: CGFloat = 0.0,
                 color: NSColor = defaultShadowColor) {
    let controlHeight = fittingSize.height
    let shadow = NSShadow()
    // Amount of blur (in pixels) applied to the shadow.
    shadow.shadowBlurRadius = controlHeight * blurRadiusMultiplier + blurRadiusConstant
    shadow.shadowColor = color
    // the distance from the text the shadow is dropped (+X = to the right; -Y = below the text):
    shadow.shadowOffset = NSSize(width: controlHeight * shadowOffsetMultiplier + xOffsetConstant, height: controlHeight * shadowOffsetMultiplier + yOffsetConstant)
    self.shadow = shadow
  }

}

extension NSView {
  var associatedPlayer: PlayerCore? {
    return (window?.windowController as? PlayerWindowController)?.player
  }

  var frameInWindowCoords: NSRect {
    return convert(frame, to: nil)
  }

  var idString: String {
    get {
      return self.identifier?.rawValue ?? ""
    }
    set {
      self.identifier = .init(newValue)
    }
  }

  func suggestedRoundedCornerRadius() -> CGFloat {
    // Set corner radius to betwen 10 and 20
    return 10 + min(10, max(0, (frame.height - 400) * 0.01))
  }

  func isInsideViewFrame(pointInWindow: CGPoint) -> Bool {
    return isMousePoint(convert(pointInWindow, from: nil), in: bounds)
  }

  /// Recursive func which configures all views in the given subtree for smoother animation.
  ///
  /// By configuring each view to use a layer with the correct redraw policy, AppKit will use Core Animation to draw
  /// them, which uses a dedicated background thread instead of the main thread.
  /// For more explanation, see https://jwilling.com/blog/osx-animations/
  func configureSubtreeForCoreAnimation() {
    if self is NSButton || self is NSSlider || self is NSProgressIndicator {
      // these still need to be redrawn on every resize or they get very buggy
      return
    }
    if self is VideoView {
      // Don't mess with these
      return
    }
    self.layerContentsRedrawPolicy = .onSetNeedsDisplay
    for subview in self.subviews {
      subview.configureSubtreeForCoreAnimation()
    }
  }

#if DEBUG
  func configureSubtreeForClipping() {
    self.clipsToBounds = true
    for subview in self.subviews {
      subview.configureSubtreeForClipping()
    }
  }
#endif

  func removeAllSubviews() {
    for subview in subviews {
      subview.removeFromSuperview()
    }
  }

  func addAllConstraintsToFillSuperview() {
    addConstraintsToFillSuperview(top: 0, bottom: 0, leading: 0, trailing: 0)
  }

  func addConstraintsToFillSuperview(top: CGFloat? = nil, bottom: CGFloat? = nil,
                                     leading: CGFloat? = nil, trailing: CGFloat? = nil) {
    guard let superview else { return }
    assert(!(top == nil && bottom == nil && leading == nil && trailing == nil),
           "addConstraintsToFillSuperview should never be called with no args! Try addAllConstraintsToFillSuperview instead")

    if let top = top {
      let topConstraint = topAnchor.constraint(equalTo: superview.topAnchor, constant: top)
      topConstraint.isActive = true
    }
    if let leading = leading {
      let leadingConstraint = leadingAnchor.constraint(equalTo: superview.leadingAnchor, constant: leading)
      leadingConstraint.isActive = true
    }
    if let trailing = trailing {
      let trailingConstraint = superview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: trailing)
      trailingConstraint.isActive = true
    }
    if let bottom = bottom {
      // Y origin is at bottom, but (+) offset goes UP from superview bottom
      let bottomConstraint = bottomAnchor.constraint(equalTo: superview.bottomAnchor, constant: bottom)
      bottomConstraint.isActive = true
    }
  }

  /// Get `NSImage` representation of the view.
  ///
  /// - Returns: `NSImage` of view
  func image() -> NSImage {
    let imageRepresentation = bitmapImageRepForCachingDisplay(in: bounds)!
    cacheDisplay(in: bounds, to: imageRepresentation)
    return NSImage(cgImage: imageRepresentation.cgImage!, size: bounds.size)
  }

  var iinaAppearance: NSAppearance {
    if #available(macOS 10.14, *) {
      var theme: Preference.Theme = Preference.enum(for: .themeMaterial)
      if theme == .system {
        if self.effectiveAppearance.isDark {
          // For some reason, "system" dark does not result in the same colors as "dark".
          // Just override it with "dark" to keep it consistent.
          theme = .dark
        } else {
          theme = .light
        }
      }
      if let themeAppearance = NSAppearance(iinaTheme: theme) {
        return themeAppearance
      }
    }
    return self.effectiveAppearance
  }

}


extension CALayer {

  /// Get `NSImage` representation of the layer.
  ///
  /// - Returns: `NSImage` of the layer.
  /// Original source: https://stackoverflow.com/a/41387514/1347529
  func image() -> NSImage {
    let width = Int(bounds.width * contentsScale)
    let height = Int(bounds.height * contentsScale)
    let imageRepresentation = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    imageRepresentation.size = bounds.size

    let context = NSGraphicsContext(bitmapImageRep: imageRepresentation)!

    render(in: context.cgContext)

    return NSImage(cgImage: imageRepresentation.cgImage!, size: bounds.size)
  }
}
