//
//  RingBuffer.swift
//  iina
//
//  Created by Matt Svoboda on 2022.05.17.
//  Copyright © 2022 lhc. All rights reserved.
//

/*
 Fixed-capacity ring buffer, backed by an data, which can append and pop from both the head and the tail.
 If already at full capacity:
 - Appending an element to the head will overwrite the element at the tail
 - Appending elements to the tail will overwrite the elements at the head
 */
public struct RingBuffer<T>: CustomStringConvertible, Sequence {
  private var data: [T?]
  private var tailIndex = 0
  private var headIndex = 0
  private var elementCount = 0

  public var count: Int {
    get {
      return elementCount
    }
  }

  public init(capacity: Int) {
    data = [T?](repeating: nil, count: capacity)
    resetCounters()
  }

  /*
   Gets the element at the head, without removing it or changing state in any way.
   */
  public var head: T? {
    get {
      return data[headIndex]
    }
  }

  /*
   Gets the element at the tail, without removing it or changing state in any way.
   */
  public var tail: T? {
    get {
      return data[tailIndex]
    }
  }

  public var isEmpty: Bool {
    return elementCount == 0
  }

  public var isFull: Bool {
    return elementCount == data.count
  }

  /*
   Sets all elements to zero & clears all internal variables to their initial state, except for `capacity`
   */
  public mutating func clear() {
    for i in 0..<data.count {
      data[i] = nil
    }
    resetCounters()
  }

  private mutating func resetCounters() {
    headIndex = 0
    tailIndex = 0
    elementCount = 0
  }

  /*
   Adds the given element to the head and increments the pointer. If already full, then the tail is overwritten.
   Returns true if the tail was overwritten; false if not.
   */
  @discardableResult
  public mutating func appendHead(_ element: T) -> Bool {
    if data[headIndex] != nil && !isFull {
      // tail did an insert first. move over and use the next available space:
      headIndex = (headIndex + 1) % data.count
    }
    data[headIndex] = element
    headIndex = (headIndex + 1) % data.count
    if isFull {
      tailIndex = (tailIndex + 1) % data.count  // also advance tail since it is being overwritten
      return true
    } else {
      elementCount = elementCount + 1
      return false
    }
  }

//  static  func %% (_ left: Int, _ right: Int) -> Int {
//     let mod = left % right
//     return mod >= 0 ? mod : mod + right
//  }

  /*
   Adds the given element to the tail and advances the tail pointer.
   If already full, then the head is overwritten and the head pointer retreats.
   Returns true if the head was overwritten; false if not.
   */
  @discardableResult
  public mutating func appendTail(_ element: T) -> Bool {
    if data[tailIndex] != nil && !isFull {
      // head did an insert first. move over and use the next available space:
      tailIndex = (tailIndex - 1) % data.count
    }
    data[tailIndex] = element
    tailIndex = (tailIndex - 1) % data.count
    if isFull {
      headIndex = (headIndex - 1) % data.count // also advance tail since it is being overwritten
      return true
    } else {
      elementCount = elementCount + 1
      return false
    }
  }

  /*
   Pops and returns the element at the head, retreating the pointer to the head.
   Returns nil if already empty.
   */
  @discardableResult
  public mutating func popHead() -> T? {
    guard !isEmpty else {
      return nil
    }
    defer {
      data[headIndex] = nil
      headIndex = (headIndex - 1) % data.count
      elementCount = elementCount - 1
    }
    return data[headIndex]
  }

  /*
   Pops and returns the element at the tail, retreating the pointer to the tail.
   Returns nil if already empty.
   */
  @discardableResult
  public mutating func popTail() -> T? {
    guard !isEmpty else {
      return nil
    }
    defer {
      data[tailIndex] = nil
      tailIndex = (tailIndex + 1) % data.count
      elementCount = elementCount - 1
    }
    return data[tailIndex]
  }

  public var description: String {
    get {
      var string = ""
      for elem in self {
        if string.isEmpty {
          string = "\(elem)"
        } else {
          string.append(", \(elem)")
        }
      }
      return "[\(string)]"
    }
  }

  public func makeIterator() -> AnyIterator<T> {
    var index = tailIndex
    let endIndex = index + elementCount
    return AnyIterator {
      guard index < endIndex else { return nil }
      defer {
        index = index + 1
      }
      return data[index % data.count]
    }
  }
}
