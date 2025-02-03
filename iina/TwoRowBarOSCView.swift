//
//  TwoRowBarOSCView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-30.
//  Copyright © 2025 lhc. All rights reserved.
//

class TwoRowBarOSCView: ClickThroughView {
  static let id = "OSC_2RowView"
  let hStackView = ClickThroughStackView()
  let centralSpacerView = SpacerView.buildNew(id: "\(TwoRowBarOSCView.id)-CentralSpacer")
  var intraRowSpacingConstraint: NSLayoutConstraint!
  /// This subtracts from the height of the icons, but is needed to balance out the space above
  var hStackView_BottomMarginConstraint: NSLayoutConstraint!

  init() {
    super.init(frame: .zero)
    identifier = .init(TwoRowBarOSCView.id)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    layer?.backgroundColor = .clear

    hStackView.idString = "\(TwoRowBarOSCView.id)-HStackView"
    hStackView.orientation = .horizontal
    hStackView.alignment = .centerY
    hStackView.translatesAutoresizingMaskIntoConstraints = false
    hStackView.detachesHiddenViews = true
    hStackView.setClippingResistancePriority(.defaultLow, for: .horizontal)
    hStackView.spacing = Constants.Distance.oscSectionHSpacing_MultiLine

    addSubview(hStackView)
    hStackView.addConstraintsToFillSuperview(leading: Constants.Distance.TwoRowOSC.leadingStackViewMargin,
                                             trailing: Constants.Distance.TwoRowOSC.trailingStackViewMargin)
    hStackView_BottomMarginConstraint = bottomAnchor.constraint(equalTo: hStackView.bottomAnchor, constant: 0.0)
    hStackView_BottomMarginConstraint.priority = .defaultLow  // for now
    hStackView_BottomMarginConstraint.isActive = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func updateSubviews(from pwc: PlayerWindowController, _ oscGeo: ControlBarGeometry) {
    // Avoid constraint violations while we change things below
    hStackView_BottomMarginConstraint.priority = .defaultLow
    intraRowSpacingConstraint?.priority = .defaultLow

    let playSliderAndTimeLabelsView = pwc.playSliderAndTimeLabelsView
    let bottomMargin = ControlBarGeometry.twoRowOSC_BottomMargin(playSliderHeight: oscGeo.playSliderHeight)

    if !subviews.contains(playSliderAndTimeLabelsView) {
      addSubview(playSliderAndTimeLabelsView)

      playSliderAndTimeLabelsView.addConstraintsToFillSuperview(top: 0, leading: Constants.Distance.TwoRowOSC.leadingStackViewMargin,
                                                                trailing: Constants.Distance.TwoRowOSC.trailingStackViewMargin)
      intraRowSpacingConstraint = hStackView.topAnchor.constraint(equalTo: playSliderAndTimeLabelsView.bottomAnchor, constant: -bottomMargin)
      intraRowSpacingConstraint.isActive = true
    }

    pwc.log.verbose("TwoRowOSC bottomMargin: \(bottomMargin)")
    intraRowSpacingConstraint.animateToConstant(-bottomMargin)
    hStackView_BottomMarginConstraint.animateToConstant(bottomMargin)
    hStackView_BottomMarginConstraint.priority = .required  // restore priority now that we're done
    intraRowSpacingConstraint.priority = .required

    // [Re-]add views to hstack
    var views: [NSView] = [pwc.fragPlaybackBtnsView, centralSpacerView, pwc.fragVolumeView]
    if let toolbarView = pwc.fragToolbarView {
      views.append(toolbarView)
    }
    hStackView.setViews(views, in: .leading)

    // Set visibility priorities
    hStackView.setVisibilityPriority(.detachEarly, for: pwc.fragVolumeView)
    if let toolbarView = pwc.fragToolbarView {
      hStackView.setVisibilityPriority(.detachEarlier, for: toolbarView)
    }
  }
}
