//
//  IINA_Tests.swift
//  IINA-Tests
//
//  Created by Matthew Svoboda on 2022.05.27.
//  Copyright © 2022 lhc. All rights reserved.
//

import XCTest
@testable import IINA

class RingBuffer_Tests: XCTestCase {
  var rb_1: RingBuffer<String>!
  var rb_5: RingBuffer<String>!

  override func setUpWithError() throws {
    rb_1 = RingBuffer<String>(capacity: 1)
    rb_5 = RingBuffer<String>(capacity: 5)
  }

  func testEmpty() throws {
    // rb_1
    XCTAssertNil(rb_1.head)
    XCTAssertNil(rb_1.tail)
    XCTAssertNil(rb_1.popHead())
    XCTAssertNil(rb_1.popTail())
    XCTAssertEqual(rb_1.count, 0)
    XCTAssertTrue(rb_1.isEmpty)
    XCTAssertFalse(rb_1.isFull)
    XCTAssertEqual(rb_1.description, "[]")

    // rb_5
    XCTAssertNil(rb_5.head)
    XCTAssertNil(rb_5.tail)
    XCTAssertNil(rb_5.popHead())
    XCTAssertNil(rb_5.popTail())
    XCTAssertEqual(rb_5.count, 0)
    XCTAssertTrue(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[]")
  }

  func testSimpleHeadAndTail() throws {
    let H = "Head"
    let T = "Tail"

    rb_1.appendHead(H)
    rb_1.appendTail(T)

    rb_5.appendHead(H)
    rb_5.appendTail(T)

    // rb_1
//    XCTAssertNil(rb_1.head)
//    XCTAssertNil(rb_1.tail)
//    XCTAssertNil(rb_1.popHead())
//    XCTAssertNil(rb_1.popTail())
//    XCTAssertEqual(rb_1.count, 0)
//    XCTAssertTrue(rb_1.isEmpty)
//    XCTAssertFalse(rb_1.isFull)
//    XCTAssertEqual(rb_1.description, "[]")

    // rb_5
    XCTAssertEqual(rb_5.head, H)
    XCTAssertEqual(rb_5.tail, T)
    XCTAssertEqual(rb_5.count, 2)
    XCTAssertFalse(rb_5.isEmpty)
    XCTAssertFalse(rb_5.isFull)
    XCTAssertEqual(rb_5.description, "[\(T), \(H)]")
//    XCTAssertNil(rb_5.popHead())
//    XCTAssertNil(rb_5.popTail())
  }
}
