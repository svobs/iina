//
//  SpacerView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-01-26.
//  Copyright © 2025 lhc. All rights reserved.
//

class SpacerView {
  static func buildNew(id: String? = nil) -> NSView {
    let spacer = NSView()
    if let id {
      spacer.idString = id
    }
    spacer.translatesAutoresizingMaskIntoConstraints = false
    spacer.setContentHuggingPriority(.minimum, for: .horizontal)
    spacer.setContentHuggingPriority(.minimum, for: .vertical)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return spacer
  }
}
