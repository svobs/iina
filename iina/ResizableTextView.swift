//
//  ResizableTextView.swift
//  iina
//
//  Created by Matt Svoboda on 2025-02-17.
//  Copyright © 2025 lhc. All rights reserved.
//

class ResizableTextView: NSTextView {

  init(lineBreakMode: NSLineBreakMode) {
    super.init(frame: .zero)
    setup()
    let pStyle: NSMutableParagraphStyle = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    pStyle.lineBreakMode = lineBreakMode
    defaultParagraphStyle = pStyle
  }

  required override init(frame frameRect: NSRect, textContainer aTextContainer: NSTextContainer!) {
    super.init(frame: frameRect, textContainer: aTextContainer)
    setup()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }

  fileprivate func setup() {
    isEditable = false
    isSelectable = false
    isFieldEditor = false
    backgroundColor = .clear
  }

  override var acceptsFirstResponder: Bool {
    return false
  }

  override func mouseDown(with event: NSEvent) {
    window?.mouseDown(with: event)
  }

  override func mouseUp(with event: NSEvent) {
    window?.mouseUp(with: event)
  }

  override func rightMouseDown(with event: NSEvent) {
    window?.rightMouseDown(with: event)

    /// Apple note (https://developer.apple.com/documentation/appkit/nsview):
    /// NSView changes the default behavior of rightMouseDown(with:) so that it calls menu(for:) and, if non nil, presents the contextual menu. In macOS 10.7 and later, if the event is not handled, NSView passes the event up the responder chain. Because of these behaviorial changes, call super when implementing rightMouseDown(with:) in your custom NSView subclasses.
    super.rightMouseDown(with: event)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return Preference.bool(for: .videoViewAcceptsFirstMouse)
  }

  // See https://stackoverflow.com/questions/11237622/using-autolayout-with-expanding-nstextviews
  override var intrinsicContentSize: NSSize {
    guard let textContainer = self.textContainer, let layoutManager = self.layoutManager else {
      return super.intrinsicContentSize
    }
    layoutManager.ensureLayout(for: textContainer)

    let stringSize = attributedString().size()
    // Note: need to add some extra width to avoid ellipses (…) being used unnecessarily. Not sure why.
    let contentSize = NSSize(width: (stringSize.width + 8).rounded(), height: stringSize.height)
    associatedPlayer?.log.trace{"ResizableTextView intrinsicContentSize: \(contentSize): \(textStorage!.string.pii.quoted)"}
    return contentSize
  }

  override func didChangeText() {
    sizeToFit()
    invalidateIntrinsicContentSize()
    super.didChangeText()
  }
}
