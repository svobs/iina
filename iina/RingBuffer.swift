/*
  Copyright (c) 2016 Matthijs Hollemans and contributors

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE.

  RingBuffer
  https://github.com/raywenderlich/swift-algorithm-club.git
  Fixed-length ring buffer

  In this implementation, the read and write pointers always increment and
  never wrap around. On a 64-bit platform that should not get you into trouble
  any time soon.

  Not thread-safe, so don't read and write from different threads at the same
  time! To make this thread-safe for one reader and one writer, it should be
  enough to change read/writeIndex += 1 to OSAtomicIncrement64(), but I haven't
  tested this...
*/
public struct RingBuffer<T> {
  private var array: [T?]
  private var readIndex = 0
  private var writeIndex = 0

  public init(count: Int) {
    array = [T?](repeating: nil, count: count)
  }

  /* Returns false if out of space. */
  @discardableResult
  public mutating func write(_ element: T) -> Bool {
    guard !isFull else { return false }
    defer {
        writeIndex += 1
    }
    array[wrapped: writeIndex] = element
    return true
  }

  /* Returns nil if the buffer is empty. */
  public mutating func read() -> T? {
    guard !isEmpty else { return nil }
    defer {
        array[wrapped: readIndex] = nil
        readIndex += 1
    }
    return array[wrapped: readIndex]
  }

  private var availableSpaceForReading: Int {
    return writeIndex - readIndex
  }

  public var isEmpty: Bool {
    return availableSpaceForReading == 0
  }

  private var availableSpaceForWriting: Int {
    return array.count - availableSpaceForReading
  }

  public var isFull: Bool {
    return availableSpaceForWriting == 0
  }
}

extension RingBuffer: Sequence {
  public func makeIterator() -> AnyIterator<T> {
    var index = readIndex
    return AnyIterator {
        guard index < self.writeIndex else { return nil }
        defer {
            index += 1
        }
        return self.array[wrapped: index]
    }
  }
}

private extension Array {
  subscript (wrapped index: Int) -> Element {
    get {
      return self[index % count]
    }
    set {
      self[index % count] = newValue
    }
  }
}
