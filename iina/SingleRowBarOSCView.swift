//
//  SingleRowBarOSCView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-30.
//  Copyright © 2025 lhc. All rights reserved.
//

/// For "bar"-type OSCs: `bottom` and `top` only - not `floating` or music mode.
class SingleRowBarOSCView: ClickThroughStackView {
  static let id = "OSC_1RowView"
  let hStackView = ClickThroughStackView()

  init() {
    super.init(frame: .zero)
    identifier = .init(SingleRowBarOSCView.id)

    /// `oscOneRowView`
    idString = SingleRowBarOSCView.id
    orientation = .horizontal
    alignment = .centerY
    distribution = .gravityAreas
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = .clear
    setClippingResistancePriority(.defaultLow, for: .horizontal)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func dispose() {
    // Not much to do here presently
    removeAllSubviews()
    removeFromSuperview()
  }

  func updateSubviews(from pwc: PlayerWindowController, _ oscGeo: ControlBarGeometry) {
    spacing = oscGeo.hStackSpacing

    pwc.addSubviewsToPlaySliderAndTimeLabelsView()
    
    var newViews: [NSView] = [pwc.fragPlaybackBtnsView, pwc.playSliderAndTimeLabelsView, pwc.fragVolumeView, pwc.fragToolbarView]

    setViews(newViews, in: .leading)
    // Seems to help restore views which have been detached from other stack views before being added here
    for view in newViews {
      view.isHidden = false
    }

    setVisibilityPriority(.mustHold, for: pwc.fragPlaybackBtnsView)
    setVisibilityPriority(.detachLessEarly, for: pwc.playSliderAndTimeLabelsView)
    setVisibilityPriority(.detachEarly, for: pwc.fragVolumeView)
    setVisibilityPriority(.detachEarlier, for: pwc.fragToolbarView)
  }

}
