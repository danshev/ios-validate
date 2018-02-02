//
//  IDValidation.swift
//
//  Created by Daniel Shevenell on 10/01/2018.
//  Copyright © 2018 Level of Knowledge LLC. All rights reserved.
//

import Foundation
import AVFoundation

import Alamofire
import SwiftyRSA
import CryptoSwift

class DigitalIDValidator {
    
    var delegate: DigitalIDValidatorDelegate?
    
    var configuration: [String: Any]!
    
    private static var sharedDigitalIDValidator: DigitalIDValidator = {
        let digitalIDValidator = DigitalIDValidator()
        
        // Configuration
        // ...
        digitalIDValidator.syncKeys()
        
        
        return digitalIDValidator
    }()
    
    private init() {
        if let config = PlistFile(named: "Configuration")!.dictionary {
            configuration = config
        }
        dateFormatter.dateFormat = "yyyyMMdd"
    }
    
    class func shared() -> DigitalIDValidator {
        return sharedDigitalIDValidator
    }
    
    struct Address {
        let line1: String
        let line2: String?
        let city: String
        let jurisdiction: String
        let postalCode: String
    }
    
    let ISO_IEC_5218 = [
        0: "Not known",
        1: "Male",
        2: "Female",
        9: "Not applicable"
    ]
    
    let ANSI_D20_79 = [
        "BLK": "Black",
        "BLU": "Blue",
        "BRO": "Brown",
        "GRY": "Gray",
        "GRN": "Green",
        "HAZ": "Hazel",
        "MAR": "Maroon",
        "PNK": "Pink",
        "DIC": "Dichromatic",
        "UNK": "Unknown"
    ]
    
    public struct Customer {
        let familyName: String
        let givenNames: String
        let dateOfBirth: Date
        let dateOfIssue: Date
        let dateOfExpiration: Date
        let issuingCountry: String
        let issuingJurisdiction: String
        let identifier: String
        let classRestrictions: String
        let gender: String
        let height: String
        let eyeColor: String
        let address: Address
    }
    
    let dateFormatter = DateFormatter()
    
    // Define delimiter characters
    let groupDelimiter = "×" as Character
    let fieldDelimiter = "÷" as Character
    let finalDelimiter = "¶" as Character
    
    // Define group--field parameters
    let expectedNumberOfGroups = 12
    let expectedNumberGroup1Fields = 9
    let expectedNumberGroup2Fields = 7
    let expectedNumberGroup10Fields = 1
    
    // Holder variables for working values
    var signatureVerified = false
    var assertionHash: String!
    var digitalWatermark: Int!
    var customerData: Customer!
    public var serviceAvailable = false
    private var currentlyPosting = false
    
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    
    public func validate(metadataObjects: [AVMetadataObject], useValidationService usingValidationService: Bool = true) ->
        (primaryQrResult: Bool?, secondaryQrResult: Bool?) {
            
            // Ensure there are objects to be analyzed
            guard metadataObjects.count != 0 else { return (nil, nil) }
            
            // Select the first object and ensure it's a QR code
            let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
            guard metadataObj.type == AVMetadataObject.ObjectType.qr else { return (nil, nil) }
            
            // Get the data contained by the QR code and ensure it's a string
            guard let dataString = metadataObj.stringValue else { return (nil, nil) }

            // Parse the string with the expected "group delimiter"
            let groups = dataString.split(separator: groupDelimiter,
                                          maxSplits: expectedNumberOfGroups,
                                          omittingEmptySubsequences: false)
            
            // A properly-encoded, primary QR code will contain 12 groups (header + 11 data fields)
            if groups.count == 12 {
                
                // Extract groups for convenience (currently, only groups 1 and 10 are used)
                let group1 = groups[1]
                let group2 = groups[2]
                let group10 = groups[10]
                
                // Build the assertion
                let assertedString = "\(group1)\(groupDelimiter)\(group2)"
                let assertion = try! ClearMessage(string: assertedString, using: .utf8)
                
                // Extract, build the signature
                let signatureHex = String(group10)
                
                guard let signatureData = Data(hexString: signatureHex) else { return (false, false) }
                let signature = Signature(data: signatureData)
                
                // Attempt to validate the assertion with any of the keys in the keychain
                var validSignature = false
                guard var keychainIds = UserDefaults.standard.array(forKey: "keychain") as? [Int] else {
                    return (nil, nil)
                }
                repeat {
                    let keyId = keychainIds.first
                    keychainIds.remove(object: keyId!)
                    
                    if let pemString = getKey(withId: keyId!) {
                        let publicKey = try! PublicKey(pemEncoded: pemString)
                        validSignature = try! assertion.verify(with: publicKey, signature: signature, digestType: .sha512)
                    }
                } while !validSignature && keychainIds.count > 0

                if validSignature {
                    signatureVerified = true
                    assertionHash = assertedString.md5()
                    digitalWatermark = calculateDigitalWatermark(fromHash: assertionHash)
                    
                    // Ensure "Group 1" is/was properly-encoded
                    let group1fields = group1.split(separator: fieldDelimiter,
                                                    maxSplits: expectedNumberGroup1Fields,
                                                    omittingEmptySubsequences: false)
                    guard group1fields.count == expectedNumberGroup1Fields else {
                        return (nil, nil)
                    }
                    
                    // Ensure "Group 2" is/was properly-encoded
                    let group2fields = group2.split(separator: fieldDelimiter,
                                                    maxSplits: expectedNumberGroup1Fields,
                                                    omittingEmptySubsequences: false)
                    guard group2fields.count == expectedNumberGroup2Fields else {
                        return (nil, nil)
                    }
                    
                    // Format dates into a usable format (required because of the 'compact encoding' standard to which the ID adheres)
                    let dateOfBirth = convertBCDdate(dateString: String(group1fields[2]))
                    let dateOfIssue = convertBCDdate(dateString: String(group1fields[3]))
                    let dateOfExpiration = convertBCDdate(dateString: String(group1fields[4]))
                    
                    let address = String(group2fields[6])
                    let addressPieces = address.split(separator: ";")
                    let street2 = (addressPieces[1] == "") ? nil : String(addressPieces[1])
                    
                    let customerAddress = Address(line1: String(addressPieces[0]),
                                                  line2: street2,
                                                  city: String(addressPieces[2]),
                                                  jurisdiction: String(addressPieces[3]),
                                                  postalCode: String(addressPieces[4])
                                                )
                    
                    // Build return object
                    customerData = Customer(familyName: String(group1fields[0]),
                                            givenNames: String(group1fields[1]),
                                            dateOfBirth: dateOfBirth,
                                            dateOfIssue: dateOfIssue,
                                            dateOfExpiration: dateOfExpiration,
                                            issuingCountry: String(group1fields[5]),
                                            issuingJurisdiction: String(group1fields[6]),
                                            identifier: String(group1fields[7]),
                                            classRestrictions: String(group1fields[8]),
                                            gender: ISO_IEC_5218[Int(group2fields[0])!]!,
                                            height: String(group2fields[2]),
                                            eyeColor: ANSI_D20_79[String(group2fields[3])]!,
                                            address: customerAddress
                    )
                    
                    return (true, nil)
                } else {
                    return(false, false)
                }
            }
            // The secondary QR code -- the "digital watermark" -- will contain only 1 field (an Integer value)
            else if groups.count == 1 && !usingValidationService && signatureVerified {
                
                guard let qrCodeIntegerValue = Int(groups[0]) else {
                    clearExistingResults()
                    return(true, false)
                }
                
                if digitalWatermark == qrCodeIntegerValue {
                    clearExistingResults()
                    return(true, true)
                    
                } else {
                    clearExistingResults()
                    return(true, false)
                }
            }
            
            return(nil, nil)
    }
    
    public func performOnlineValidation(completion: @escaping (_ valid: Bool, _ reason: String?) -> Void) {
        if !currentlyPosting{
            self.currentlyPosting = true

            let serverErrorMsg = configuration["server-error-message"] as! String
            let invalidMsg = configuration["invalid-id-error-message"] as! String
            let endpoint = configuration["online-validation-endpoint"] as! String
            Alamofire.request("\(endpoint)\(assertionHash!)").responseJSON(completionHandler: { (response) in
                self.currentlyPosting = false
                if let _ = response.error {
                    print(response)
                    self.delegate?.validationServiceDidChange(false)
                    completion(false, serverErrorMsg)
                } else {
                    switch response.response?.statusCode as! Int {
                    case 200:
                        if let jsonData = response.result.value {
                            let jsonDict = jsonData as! [String: String]
                            self.fetchProfileImage(for: jsonDict["serialNumber"]!)
                        }
                        completion(true, nil)
                        
                    case 403:
                        print("403")
                        completion(false, invalidMsg)
                        
                    default:
                        print("other")
                        self.delegate?.validationServiceDidChange(false)
                        completion(false, serverErrorMsg)
                    }
                }
            })
        }
    }
    
    
    private func fetchProfileImage(for serialNumber: String) {
        let destination: DownloadRequest.DownloadFileDestination = { _, _ in
            let documentsURL = URL(fileURLWithPath: self.documentsPath, isDirectory: true)
            let fileURL = documentsURL.appendingPathComponent("thumbnail.jpg")
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        let endpoint = configuration["fetch-profile-image-endpoint"] as! String
        Alamofire.download("\(endpoint)\(serialNumber)", to: destination).downloadProgress { progress in
            self.delegate?.downloadProgressDidChange(to: progress.fractionCompleted)
            }.responseData { response in
                if let data = response.result.value {
                    self.delegate?.didReceiveProfileImage(UIImage(data: data))
                } else {
                    
                }
        }
    }

    
  // MARK: - Private helper Functions
    
    private func convertBCDdate(dateString: String) -> Date {
        let dateStr = dateString.replacingOccurrences(of: " ", with: "", options: NSString.CompareOptions.literal, range: nil).replacingOccurrences(of: "'", with: "", options: NSString.CompareOptions.literal, range: nil)
        return dateFormatter.date(from: dateStr)!
    }
    
    private func syncKeys() {
        let endpoint = configuration["sync-keys-endpoint"] as! String
        Alamofire.request(endpoint).responseJSON(completionHandler: { (response) in
            if let _ = response.error {
                self.serviceAvailable = false
                self.delegate?.validationServiceDidChange(false)
            } else {
                self.delegate?.validationServiceDidChange(true)
                self.serviceAvailable = true
                if let jsonData = response.result.value {
                    let serverKeys = jsonData as! [Int]
                    
                    var needKeys = serverKeys
                    if let localKeys = UserDefaults.standard.array(forKey: "keychain") as? [Int] {
                        let localKeySet = Set(localKeys)
                        needKeys = serverKeys.filter { !localKeySet.contains($0) }
                    }

                    for keyId in needKeys {
                        self.fetchKey(withId: keyId)
                    }
                }
            }
        })
    }
    
    private func fetchKey(withId id: Int) {
        let endpoint = configuration["sync-keys-endpoint"] as! String
        
        let destination: DownloadRequest.DownloadFileDestination = { _, _ in
            let documentsURL = URL(fileURLWithPath: self.documentsPath, isDirectory: true)
            let fileURL = documentsURL.appendingPathComponent("\(id).pub.pem")
            return (fileURL, [.removePreviousFile, .createIntermediateDirectories])
        }
        
        Alamofire.download("\(endpoint)?\(id)", to: destination).responseData { (response) in
            if let err = response.error {
                print(err)
            } else {
                var localKeys = [Int]()
                if let existingKeys = UserDefaults.standard.array(forKey: "keychain") as? [Int] {
                    localKeys = existingKeys
                }
                localKeys.append(id)
                localKeys.sort()
                UserDefaults.standard.set(localKeys, forKey: "keychain")
            }
        }
    }
    
    private func getKey(withId id: Int) -> String? {
        let keyURL = URL(fileURLWithPath: documentsPath).appendingPathComponent("\(id).pub.pem")
        return try! String(contentsOf: keyURL as URL)
    }
    
    private func clearExistingResults() {
        assertionHash = ""
        digitalWatermark = 0
        signatureVerified = false
    }
    
    // The "digital watermark" is created from the SHA-1 hash value of the profile image (packaged inside the Digital ID).
    //  The non-numeric characters are removed from hash, the individual, residual (numeric) characters are summed, and the 
    //  value is multiplied by the current hour, day, month, and year.  To defeat this method, an attacker would have to
    //  either build/side-load an app to spoof this behavior -or- generate a unique image for every hour remaining in their lives.
    private func calculateDigitalWatermark(fromHash: String) -> Int {
        let numberString = fromHash.replacingOccurrences( of:"[^0-9]", with: "", options: .regularExpression)
        let sum = numberString.flatMap{Int(String($0))}.reduce(0, +)
        let hour = Calendar.current.component(.hour, from: Date())
        let day = Calendar.current.component(.day, from: Date())
        let month = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        
        return sum * hour * day * month * year
    }
    
    // MARK: - Plist Helper
    /* Credit: https://stackoverflow.com/a/43644844/2203324 */
    
    struct PlistFile {
        
        enum PlistError: Error {
            case failedToWrite
            case fileDoesNotExist
        }
        
        let name: String
        
        var sourcePath: String? {
            return Bundle.main.path(forResource: name, ofType: "plist")
        }
        
        var destPath: String? {
            if let _ = sourcePath {
                let dir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
                return (dir as NSString).appendingPathComponent("\(name).plist")
            } else {
                return nil
            }
        }
        
        var dictionary : [String:Any]? {
            get{
                return getDictionary()
            } set{
                if let newDict = newValue {
                    try? write(dictionary: newDict)
                }
            }
        }
        
        var array : [Any]? {
            get{
                return getArray()
            } set{
                if let newArray = newValue {
                    try? write(array: newArray)
                }
            }
        }
        
        private let fileManager = FileManager.default
        
        init?(named :String) {
            self.name = named
            
            guard let source = sourcePath, let destination = destPath, fileManager.fileExists(atPath: source)  else {
                return nil
            }
            
            if !fileManager.fileExists(atPath: destination) {
                do {
                    try fileManager.copyItem(atPath: source, toPath: destination)
                } catch let error {
                    print("Unable to copy file. ERROR: \(error.localizedDescription)")
                    return nil
                }
            }
        }
        
        
        private func getDictionary() -> [String:Any]? {
            guard let destPath = self.destPath, fileManager.fileExists(atPath: destPath) else {
                return nil
            }
            return NSDictionary(contentsOfFile: destPath) as? [String:Any]
        }
        
        private func getArray() -> [Any]? {
            guard let destPath = self.destPath, fileManager.fileExists(atPath: destPath) else {
                return nil
            }
            return NSArray(contentsOfFile: destPath) as? [Any]
        }
        
        func write(dictionary : [String:Any]) throws{
            guard let destPath = self.destPath, fileManager.fileExists(atPath: destPath) else {
                throw PlistError.fileDoesNotExist
            }
            
            if !NSDictionary(dictionary: dictionary).write(toFile: destPath, atomically: false) {
                print("Failed to write the file")
                throw PlistError.failedToWrite
            }
        }
        
        func write(array : [Any] ) throws {
            guard let destPath = self.destPath, fileManager.fileExists(atPath: destPath) else {
                throw PlistError.fileDoesNotExist
            }
            
            if !NSArray(array: array).write(toFile: destPath, atomically: false) {
                print("Failed to write the file")
                throw PlistError.failedToWrite
            }
        }
    }
}

protocol DigitalIDValidatorDelegate {
    func downloadProgressDidChange(to percent: Double)
    func didReceiveProfileImage(_ profileImage: UIImage?)
    func validationServiceDidChange(_ available: Bool)
}


extension Data {
    
    // Credit: https://stackoverflow.com/a/46663290/2203324
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0..<len {
            let j = hexString.index(hexString.startIndex, offsetBy: i*2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}

extension Array where Element: Equatable {
    mutating func remove(object: Element) {
        if let index = index(of: object) {
            remove(at: index)
        }
    }
}
