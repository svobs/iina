//
//  VideoView_Constraints.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-16.
//  Copyright © 2025 lhc. All rights reserved.
//

extension VideoView {
  
  struct VideoViewConstraints {
    let eqOffsetTop: NSLayoutConstraint
    let eqOffsetTrailing: NSLayoutConstraint
    let eqOffsetBottom: NSLayoutConstraint
    let eqOffsetLeading: NSLayoutConstraint

    // Use aspect ratio constraint + weak center constraints to improve the video resize animation when
    // tiling the window while lockViewportToVideoSize is enabled.
    // Previously the video would get squeezed during resize. This became more noticable with the introduction
    // of MacOS Sequoia 15.0.
    let centerX: NSLayoutConstraint
    let centerY: NSLayoutConstraint
    let aspectRatio: NSLayoutConstraint
  }

  var aspectMultiplier: CGFloat? {
    return videoViewConstraints?.aspectRatio.multiplier
  }

  private func addOrUpdate(_ existingConstraint: NSLayoutConstraint?,
                           _ attr: NSLayoutConstraint.Attribute, _ relation: NSLayoutConstraint.Relation, _ constant: CGFloat,
                           _ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
    let constraint: NSLayoutConstraint
    if let existingConstraint {
      constraint = existingConstraint
      constraint.animateToConstant(constant)
    } else {
      constraint = NSLayoutConstraint(item: self, attribute: attr, relatedBy: relation, toItem: superview!,
                                      attribute: attr, multiplier: 1, constant: constant)
    }
    constraint.priority = priority
    return constraint
  }

  private func rebuildConstraints(top: CGFloat = 0, trailing: CGFloat = 0, bottom: CGFloat = 0, leading: CGFloat = 0,
                                  aspectMultiplier: CGFloat,
                                  eqIsActive: Bool = true, eqPriority: NSLayoutConstraint.Priority,
                                  hCenterActive: Bool, vCenterActive: Bool, centerPriority: NSLayoutConstraint.Priority,
                                  aspectIsActive: Bool = true, aspectPriority: NSLayoutConstraint.Priority) {
    guard let superview else {
      // Should not get here
      log.error("Cannot rebuild constraints for videoView: it has no superview!")
      return
    }
    var existing = self.videoViewConstraints
    self.videoViewConstraints = nil

    var newCenterX: NSLayoutConstraint
    var newCenterY: NSLayoutConstraint
    let newAspect: NSLayoutConstraint
    if let existing {
      newCenterX = existing.centerX
      newCenterY = existing.centerY
      if existing.aspectRatio.isActive != aspectIsActive || aspectMultiplier != existing.aspectRatio.multiplier {
        existing.aspectRatio.isActive = false
        newAspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
      } else {
        newAspect = existing.aspectRatio
      }
    } else {
      newCenterX = centerXAnchor.constraint(equalTo: superview.centerXAnchor)
      newCenterY = centerYAnchor.constraint(equalTo: superview.centerYAnchor)
      newAspect = widthAnchor.constraint(equalTo: heightAnchor, multiplier: aspectMultiplier, constant: 0)
    }
    newCenterX.priority = centerPriority
    newCenterY.priority = centerPriority
    newAspect.priority = aspectPriority

    let vPriority = eqPriority
    let hPriority = eqPriority
    //    let vPriority: NSLayoutConstraint.Priority = (top == 0 && bottom == 0) ? .required : eqPriority
    //    let hPriority: NSLayoutConstraint.Priority = (vPriority.rawValue != 1000 && leading == 0 && trailing == 0) ? .required : eqPriority

    let newConstraints = VideoViewConstraints(
      eqOffsetTop: addOrUpdate(existing?.eqOffsetTop, .top, .equal, top, vPriority),
      eqOffsetTrailing: addOrUpdate(existing?.eqOffsetTrailing, .trailing, .equal, trailing, hPriority),
      eqOffsetBottom: addOrUpdate(existing?.eqOffsetBottom, .bottom, .equal, bottom, vPriority),
      eqOffsetLeading: addOrUpdate(existing?.eqOffsetLeading, .leading, .equal, leading, hPriority),

      centerX: newCenterX,
      centerY: newCenterY,
      aspectRatio: newAspect
    )
    existing = nil
    videoViewConstraints = newConstraints

    newConstraints.eqOffsetTop.isActive = eqIsActive
    newConstraints.eqOffsetTrailing.isActive = eqIsActive
    newConstraints.eqOffsetBottom.isActive = eqIsActive
    newConstraints.eqOffsetLeading.isActive = eqIsActive
    newConstraints.centerX.isActive = hCenterActive
    newConstraints.centerY.isActive = vCenterActive
    newConstraints.aspectRatio.isActive = aspectIsActive
  }

  func apply(_ geometry: PWinGeometry?) {
    assert(DispatchQueue.isExecutingIn(.main))

    guard player.windowController.pip.status == .notInPIP else {
      log.verbose("VideoView: currently in PiP; ignoring request to set viewportMargin constraints")
      return
    }

    let margins: MarginQuad
    let eqPriority: NSLayoutConstraint.Priority = .init(499)

    let videoAspect: Double
    let aspectPriority: NSLayoutConstraint.Priority = .required

    let centerPriority: NSLayoutConstraint.Priority = .minimum

    if let geometry, geometry.isVideoVisible {
      margins = geometry.viewportMargins
      videoAspect = geometry.videoViewAspect
      log.verbose{"VideoView: updating constraints to margins=\(margins), aspect=\(videoAspect)"}
    } else {
      margins = .zero
      videoAspect = -1
      log.verbose("VideoView: zeroing out constraints")
    }

    rebuildConstraints(top: margins.top,
                       trailing: -margins.trailing,
                       bottom: -margins.bottom,
                       leading: margins.leading,
                       aspectMultiplier: videoAspect,
                       eqIsActive: true, eqPriority: eqPriority,
                       hCenterActive: true, vCenterActive: true, centerPriority: centerPriority,
                       aspectIsActive: videoAspect > 0.0, aspectPriority: aspectPriority)
    // FIXME: when watching vertical video with letterbox & leading sidebar shown & resizing from side,
    // VideoView can stretch horizontally, even though it violates its aspect constraint (priority 1000),
    // and even though the View Debugger shows it is not distorted...
    needsUpdateConstraints = true
    needsLayout = true
  }

}
