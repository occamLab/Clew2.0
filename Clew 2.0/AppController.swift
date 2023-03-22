//
//  AppController.swift
//  Clew 2.0
//
//  Created by Joyce Chung & Gabby Blake on 3/4/23.
//  Copyright © 2023 Occam Lab. All rights reserved.
//

import Foundation

protocol AppController {
    associatedtype AppCommand
    associatedtype AppEvent
    
    func process(commands: [AppCommand])
    func process(event: AppEvent)
}
