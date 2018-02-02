//
//  UIView+extension.swift
//  Validate
//
//  Created by Daniel Shevenell on 1/26/18.
//  Copyright © 2018 Daniel Shevenell. All rights reserved.
//

import Foundation
import UIKit

public extension UIView {
    func fadeIn(withDuration duration: TimeInterval = 1.0, toAlpha: CGFloat = 1.0, completion:() -> Void) {
        UIView.animate(withDuration: duration, animations: {
            self.alpha = toAlpha
        })
    }
    
    func fadeOut(withDuration duration: TimeInterval = 1.0, toAlpha: CGFloat = 0.0, completion:() -> Void) {
        UIView.animate(withDuration: duration, animations: {
            self.alpha = toAlpha
        })
    }
}
