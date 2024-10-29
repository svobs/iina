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

 From Swift Algorithm Club (https://github.com/raywenderlich/swift-algorithm-club)
 (modified heavily for better efficiency & usability)
 */
enum LinkedListError: Error {
  case listIsEmpty
  case indexInvalid(_ msg: String)
  case indexOutOfBounds(_ msg: String)
}

final class LinkedList<T> {

  class Node {
    var value: T
    var next: Node?
    weak var prev: Node?

    init(value: T) {
      self.value = value
    }
  }

  /// The first element of the LinkedList (index `0`).
  var firstNode: Node?

  /// The last element of the LinkedList (index `count - 1`)
  var lastNode: Node?

  /// Computed property to check if the linked list is empty. O(1) operation.
  var isEmpty: Bool {
    return count == 0
  }

  fileprivate(set) var count: Int = 0

  var first: T? {
    firstNode?.value
  }

  var last: T? {
    lastNode?.value
  }
  
  /// Subscript function to return the element at the given `index`.
  subscript(index: Int) -> T?  {
    return self.item(at: index)
  }

  /// Returns the element at the given `index`.
  ///
  /// Throws `LinkedListError` if `index < 0` or `index > self.count`.
  func item(at index: Int) -> T? {
    return node(at: index)?.value
  }

  private func node(at index: Int) -> Node? {
    if firstNode == nil || index < 0 || index >= count {
      return nil
    }

    if index == 0 {
      return firstNode
    } else if index == count - 1 {
      return lastNode
    } else {
      var node = firstNode!.next
      for _ in 1..<index {
        node = node?.next
        assert (node != nil)
      }

      return node
    }
  }

  /// Function to return the first element which meets the given condition.
  ///
  /// Throws `LinkedListError` if `index < 0` or `index > self.count`.
  func item(_ whereCondition: (T) -> Bool) -> T? {
    var node = firstNode

    while node != nil {
      if whereCondition(node!.value) {
        return node!.value
      } else {
        node = node!.next
      }
    }
    return nil
  }

  /// Inserts `value` to the beginning of this `LinkedList`.
  ///
  /// This is equivalent to: `insert(_, at: 0)`.
  /// The new value becomes the new head of the list.
  func prepend(_ value: T) {
    let newNode = Node(value: value)
    try! insert(newNode, at: 0)
  }

  /// Inserts `value` to the end of this `LinkedList`.
  ///
  /// This is equivalent to: `insert(_, at: self.count)`.
  /// The new value becomes the new tail of the list.
  func append(_ value: T) {
    let newNode = Node(value: value)
    try! insert(newNode, at: count)
  }

  /// Append the contents of the given `LinkedList` to the end of this `LinkedList`.
  ///
  /// New nodes are constructed in this `LinkedList` to hold each element from the source list,
  /// but the data inside each node is not copied.
  func appendAll(_ list: LinkedList) {
    var nodeToCopy = list.firstNode
    while let node = nodeToCopy {
      append(node.value)
      nodeToCopy = node.next
    }
  }

  /// Append the contents of the given array to the end of this `LinkedList`.
  func appendAll(_ list: [T]) {
    for value in list {
      append(value)
    }
  }

  /// Insert the given `value` at `index`.
  ///
  /// Throws `LinkedListError` if `index < 0` or `index > self.count`.
  func insert(_ value: T, at index: Int) throws {
    let newNode = Node(value: value)
    try insert(newNode, at: index)
  }

  /// Insert the given `value` at `index`.
  ///
  /// Throws `LinkedListError` if `index < 0` or `index > self.count`.
  private func insert(_ newNode: Node, at index: Int) throws {
    if index == 0 {
      if let firstNode {
        newNode.next = firstNode
        firstNode.prev = newNode
      } else {
        lastNode = newNode
      }
      firstNode = newNode
    } else {
      guard let prev = node(at: index - 1) else {
        throw LinkedListError.indexOutOfBounds("Requested index is longer than this list: \(index)")
      }
      let next = prev.next
      newNode.prev = prev
      if let next = next {
        newNode.next = next
        next.prev = newNode
      } else {
        lastNode = newNode
      }
      prev.next = newNode
    }

    count += 1
  }

  /// Append the contents of the given `LinkedList` at the given `index` in this `LinkedList`.
  ///
  /// Throws `LinkedListError` if `index < 0` or `index > self.count`.
  func insertAll(_ list: LinkedList, at index: Int) throws {
    guard !list.isEmpty else { return }

    let insertCount = list.count

    if index == 0 {
      list.lastNode?.next = firstNode
      firstNode = list.firstNode
    } else {
      guard let prev = node(at: index - 1) else {
        throw LinkedListError.indexOutOfBounds("Invalid index: \(index)")
      }
      let next = prev.next

      prev.next = list.firstNode
      list.firstNode?.prev = prev

      if let next = next {
        list.lastNode?.next = next
        next.prev = list.lastNode
      } else {
        if list.lastNode != nil {
          lastNode = list.lastNode
        }
      }
    }

    count += insertCount
  }

  /// Removes all elements from this `LinkedList`.
  ///
  /// This is an O(n) operation because all links are set to nil in each node.
  func removeAll() {
    var node = lastNode
    while let nodeToRemove = node {
      node = nodeToRemove.prev
      nodeToRemove.prev = nil
      nodeToRemove.next = nil
      count -= 1
    }

    lastNode = nil
    firstNode = nil
  }

  /// Removes all elements from this `LinkedList`.
  ///
  /// This is an O(n) operation because all links are set to nil in each node.
  /// Equivalent to `removeAll()`.
  func clear() {
    removeAll()
  }

  @discardableResult
  func remove(_ whereCondition: (T) -> Bool) -> T? {
    var node = firstNode

    while node != nil {
      if whereCondition(node!.value) {
        return remove(node: node!)
      } else {
        node = node!.next
      }
    }
    return nil
  }


  // Function to remove a specific node.
  // - Parameter node: The node to be deleted
  // - Returns: The data value contained in the deleted node.
  @discardableResult
  private func remove(node: Node) -> T {
    let prev = node.prev
    let next = node.next

    if let prev = prev {
      prev.next = next
    } else {
      firstNode = next
    }
    if let next = next {
      next.prev = prev
    } else {
      lastNode = prev
    }

    node.prev = nil
    node.next = nil

    count -= 1
    return node.value
  }

  /// Function to remove the first node/value in the list. Returns nil if the list is empty
  /// - Returns: The data value contained in the deleted node.
  @discardableResult
  func removeFirst() -> T? {
    guard !isEmpty else {
      return nil
    }
    return remove(node: firstNode!)
  }
  
  /// Function to remove the last node/value in the list. Returns nil if the list is empty
  /// - Returns: The data value contained in the deleted node.
  @discardableResult
  func removeLast() -> T? {
    guard !isEmpty else {
      return nil
    }
    return remove(node: lastNode!)
  }

  /// Function to remove a node/value at a specific index. Returns nil if index is out of bounds (0...self.count)
  /// - Parameter index: Integer value of the index of the node to be removed
  /// - Returns: The data value contained in the deleted node
  @discardableResult
  func remove(at index: Int) -> T? {
    guard let node = self.node(at: index) else {
      return nil
    }
    return remove(node: node)
  }

  func makeIterator() -> AnyIterator<T> {
    var node = firstNode
    return AnyIterator {
      if let thisExistingNode = node {
        node = thisExistingNode.next
        return thisExistingNode.value
      }
      return nil
    }
  }
}  // end class LinkedList

// Extension to enable the standard conversion of a list to String
extension LinkedList: CustomStringConvertible {
  var description: String {
    var s = "["
    var node = firstNode
    while let nd = node {
      s += "\(nd.value)"
      node = nd.next
      if node != nil { s += ", " }
    }
    return s + "]"
  }
}

// Extension to add a 'reverse' function to the list
extension LinkedList {
  func reverse() {
    var node = firstNode
    while let currentNode = node {
      node = currentNode.next
      swap(&currentNode.next, &currentNode.prev)
      firstNode = currentNode
    }
  }
}

// An extension with an implementation of 'map' & 'filter' functions
extension LinkedList {
  func map<U>(transform: (T) -> U) -> LinkedList<U> {
    let result = LinkedList<U>()
    var node = firstNode
    while let nd = node {
      result.append(transform(nd.value))
      node = nd.next
    }
    return result
  }

  func filter(predicate: (T) -> Bool) -> LinkedList<T> {
    let result = LinkedList<T>()
    var node = firstNode
    while let nd = node {
      if predicate(nd.value) {
        result.append(nd.value)
      }
      node = nd.next
    }
    return result
  }
}

// Extension to enable initialization from an Array
extension LinkedList {
  convenience init(array: Array<T>) {
    self.init()
    array.forEach { append($0) }
  }
}

// Extension to enable initialization from an Array Literal
extension LinkedList: ExpressibleByArrayLiteral {
  convenience init(arrayLiteral elements: T...) {
    self.init()
    elements.forEach { append($0) }
  }
}

extension LinkedList: Collection {
  typealias Index = LinkedListIndex<T>

  /// The position of the first element in a nonempty collection.
  /// If the collection is empty, `startIndex` is equal to `endIndex`.
  /// - Complexity: O(1)
  var startIndex: Index {
    get {
      return LinkedListIndex<T>(node: firstNode, tag: 0)
    }
  }

  /// The collection's "past the end" position---that is, the position one greater than the last valid subscript argument.
  /// - Complexity: O(n), where n is the number of elements in the list. This can be improved by keeping a reference
  ///   to the last node in the collection.
  var endIndex: Index {
    if let h = self.firstNode {
      return LinkedListIndex<T>(node: h, tag: count)
    } else {
      return LinkedListIndex<T>(node: nil, tag: startIndex.tag)
    }
  }

  subscript(position: Index) -> T {
    return position.node!.value
  }

  func index(after idx: Index) -> Index {
    return LinkedListIndex<T>(node: idx.node?.next, tag: idx.tag + 1)
  }
}

// MARK: - Collection Index

/// Custom index type that contains a reference to the node at index 'tag'
struct LinkedListIndex<T>: Comparable {
  let node: LinkedList<T>.Node?
  let tag: Int

  static func==<I>(lhs: LinkedListIndex<I>, rhs: LinkedListIndex<I>) -> Bool {
    return (lhs.tag == rhs.tag)
  }

  static func< <I>(lhs: LinkedListIndex<I>, rhs: LinkedListIndex<I>) -> Bool {
    return (lhs.tag < rhs.tag)
  }
}
