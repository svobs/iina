//
//  StateEnum.swift
//  iina
//
//  Created by Matt Svoboda on 2024/07/08.
//

import Foundation

protocol StateEnum {
  associatedtype T
  
  func isAtLeast(_ minStatus: T) -> Bool

  func isNotYet(_ status: T) -> Bool
}
