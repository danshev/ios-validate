//
//  LegacyIDValidator.swift
//
//  Created by Daniel Shevenell on 10/01/2018.
//  Copyright © 2018 Level of Knowledge LLC. All rights reserved.
//

import Foundation
import AVFoundation

import Alamofire
import SwiftyRSA

class LegacyIDValidator {
    
    private static var sharedLegacyIDValidator: LegacyIDValidator = {
        let legacyIDValidator = LegacyIDValidator()
        
        // Configuration
        // ...
        
        return legacyIDValidator
    }()
    
    private init() { }
    
    class func shared() -> LegacyIDValidator {
        return sharedLegacyIDValidator
    }
    
    struct Customer {
        let familyName: String
        let givenNames: String
        let dateOfBirth: Date
        let dateOfIssue: Date
        let dateOfExpiration: Date
        let issuingCountry: String
        let issuingJurisdiction: String
        let identifier: String
        let classRestrictions: String
    }
    
    var customerData: Customer!

    func validate(metadataObjects: [AVMetadataObject], usingValidationService: Bool = true) -> (properFormat: Bool?, customerData: Customer?) {
            
            // Ensure there are objects to be analyzed
            guard metadataObjects.count != 0 else {
                return (nil, nil)
            }
            
            // Select the first object and ensure it's a QR code
            let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
            guard metadataObj.type == AVMetadataObject.ObjectType.pdf417 else {
                return (nil, nil)
            }
            
            // Get the data contained by the QR code and ensure it's a string
            guard let dataString = metadataObj.stringValue else {
                return (nil, nil)
            }
        
            /*
            // Format dates into a usable format (required because of the 'compact encoding' standard to which the ID adheres)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
        
            let dateOfBirthStr = (String(group1fields[2])).replacingOccurrences(of: " ", with: "", options: NSString.CompareOptions.literal, range:nil).replacingOccurrences(of: "'", with: "", options: NSString.CompareOptions.literal, range:nil)
            let dateOfIssueStr = String(group1fields[3]).replacingOccurrences(of: " ", with: "", options: NSString.CompareOptions.literal, range:nil).replacingOccurrences(of: "'", with: "", options: NSString.CompareOptions.literal, range:nil)
            let dateOfExpirationStr = String(group1fields[4]).replacingOccurrences(of: " ", with: "", options: NSString.CompareOptions.literal, range:nil).replacingOccurrences(of: "'", with: "", options: NSString.CompareOptions.literal, range:nil)
        
            let dateOfBirth = dateFormatter.date(from: dateOfBirthStr)
            let dateOfIssue = dateFormatter.date(from: dateOfIssueStr)
            let dateOfExpiration = dateFormatter.date(from: dateOfExpirationStr)
            */
            // Build return object

            return (nil, nil)
    }
    
    
    // MARK: - Helper Functions
}
