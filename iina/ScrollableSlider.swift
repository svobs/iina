//
//  ScrollableSlider.swift
//
//  Created by Nate Thompson on 10/24/17.
//  Original source code: https://github.com/thompsonate/Scrollable-NSSlider

import Foundation

/// Adds scroll wheel support to `NSSlider`. Must set its `scrollWheel` property after init.
///
/// The logic for this class has moved. See `VirtualScrollWheel.executeScroll()`.
class ScrollableSlider: NSSlider {
  var scrollWheel: VirtualScrollWheel?

  override func scrollWheel(with event: NSEvent) {
    guard isEnabled else { return }
    scrollWheel?.scrollWheel(with: event)
  }
}
