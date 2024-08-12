//
//  StateEnum.swift
//  iina
//
//  Created by Matt Svoboda on 7/8/24.
//  Copyright © 2024 lhc. All rights reserved.
//

import Foundation

protocol StateEnum {
  associatedtype T
  
  func isAtLeast(_ minStatus: T) -> Bool

  func isNotYet(_ status: T) -> Bool
}
