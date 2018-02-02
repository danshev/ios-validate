//
//  ViewController.swift
//  Validate
//
//  Created by Daniel Shevenell on 1/24/18.
//  Copyright © 2018 Daniel Shevenell. All rights reserved.
//

import UIKit
import AVFoundation
import CoreBluetooth
import CoreLocation
import Alamofire
import UICircularProgressRing

class ValidateController: UIViewController, CBPeripheralManagerDelegate, DigitalIDValidatorDelegate {
    
    var digitalIDvalidator: DigitalIDValidator!
    
    var captureSession = AVCaptureSession()
    
    var player: AVAudioPlayer?
    var validationServiceAvailable = true
    var retrieveImageSwitch: UISwitch!
    var showingCustomerData = false
    
    var infoResultBlock: UIView!
    let infoLeftOffset:CGFloat = 10.0
    let infoWidth:CGFloat = 120.0
    var retrieveImageLabel: UILabel!
    
    // iBeacon variables (for relevance presentation)
    var localBeacon: CLBeaconRegion!
    var beaconPeripheralData: NSDictionary!
    var peripheralManager: CBPeripheralManager!
    let beaconUUID = "04CAB66E-7BFF-43EB-9E85-F2F3AC23DC75"
    let beaconMajor: CLBeaconMajorValue = 123
    let beaconMinor: CLBeaconMinorValue = 456
    let beaconID = "gov.dhs.digital-drivers-license"
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var qrCodeFrameView: UIView?
    
    // UI element constants
    let bottomTrayHeight: CGFloat = 50.0
    let sidePadding: CGFloat = 15.0
    
    enum IDType {
        case Digital
        case Legacy
    }
    
    private let supportedCodeTypes = [AVMetadataObject.ObjectType.pdf417, AVMetadataObject.ObjectType.qr]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        digitalIDvalidator = DigitalIDValidator.shared()
        digitalIDvalidator.delegate = self
        
        // Start broadcasting as an iBeacon
        initLocalBeacon()
        
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { response in
            if response {
                //access granted
            } else {
                
            }
        }
        
        // Get the back-facing camera for capturing videos
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: AVMediaType.video, position: .back)
        
        guard let captureDevice = deviceDiscoverySession.devices.first else {
            print("Failed to get the camera device")
            return
        }
        
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            // Set the input device on the capture session.
            captureSession.addInput(input)
            
            // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession.addOutput(captureMetadataOutput)
            
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = supportedCodeTypes
            //            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
            
        } catch {
            // If any error occurs, simply print it out and don't continue any more.
            print(error)
            return
        }
        
        // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
        videoPreviewLayer?.frame = view.layer.bounds
        view.layer.addSublayer(videoPreviewLayer!)
        
        // Start video capture.
        captureSession.startRunning()
        
        // Initialize QR Code Frame to highlight the QR code
        qrCodeFrameView = UIView()
        
        if let qrCodeFrameView = qrCodeFrameView {
            qrCodeFrameView.layer.borderColor = UIColor.green.cgColor
            qrCodeFrameView.layer.borderWidth = 2
            view.addSubview(qrCodeFrameView)
            view.bringSubview(toFront: qrCodeFrameView)
        }
        
        view.addSubview(buildBottomTray())
        //view.bringSubview(toFront: qrCodeFrameView)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    // MARK: - UI Builder Helpers
    
    func buildBottomTray() -> UIVisualEffectView {
        let bottomTrayLayer = UIView()
        let lightBlur = UIBlurEffect(style: .light)
        let visualEffectView = UIVisualEffectView(effect: lightBlur)
        
        // Dimensions
        let trayWidth = view.frame.size.width - 2*sidePadding
        let trayYCoordinate = view.frame.size.height - bottomTrayHeight - sidePadding
        
        visualEffectView.frame = CGRect(x: sidePadding, y: trayYCoordinate, width: trayWidth, height: bottomTrayHeight)
        visualEffectView.layer.cornerRadius = 25
        visualEffectView.layer.masksToBounds = true
        visualEffectView.contentView.addSubview(bottomTrayLayer)
        
        retrieveImageSwitch = UISwitch()
        retrieveImageSwitch.frame = CGRect(x: (trayWidth - retrieveImageSwitch.frame.width - 10.0), y: (bottomTrayHeight - retrieveImageSwitch.frame.height) / 2, width: retrieveImageSwitch.frame.width, height: retrieveImageSwitch.frame.height)
        visualEffectView.contentView.addSubview(retrieveImageSwitch)
        
        retrieveImageLabel = UILabel()
        retrieveImageLabel.font = UIFont(name: "AvenirNext-Medium", size: 18.0)
        retrieveImageLabel.textColor = UIColor.white
        retrieveImageLabel.text = "Use online validation service?"
        retrieveImageLabel.textAlignment = .right
        
        retrieveImageLabel.frame = CGRect(x: (trayWidth - retrieveImageSwitch.frame.width - 5 - 235 - 25.0), y: (bottomTrayHeight - 25) / 2, width: 245, height: 25)
        visualEffectView.contentView.addSubview(retrieveImageLabel)
        
        return visualEffectView
    }
    


    // MARK: - iBeacon Helper Methods
    
    func initLocalBeacon() {
        if localBeacon != nil { stopLocalBeacon() }
        let uuid = UUID(uuidString: beaconUUID)!
        localBeacon = CLBeaconRegion(proximityUUID: uuid, major: beaconMajor, minor: beaconMinor, identifier: beaconID)
        beaconPeripheralData = localBeacon.peripheralData(withMeasuredPower: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    func stopLocalBeacon() {
        peripheralManager.stopAdvertising()
        peripheralManager = nil
        beaconPeripheralData = nil
        localBeacon = nil
    }
    
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print(" - iBeacon broadcasting started")
            peripheralManager.startAdvertising(beaconPeripheralData as! [String: AnyObject]!)
        } else if peripheral.state == .poweredOff {
            peripheralManager.stopAdvertising()
            print(" - iBeacon broadcasting stopped")
        }
    }
    
  // MARK: - DigitalIDValidator Delegate Functions
    
    func downloadProgressDidChange(to percent: Double) {
        if let progressRing = view.viewWithTag(15) as? UICircularProgressRingView {
            if percent == 1.0 {
                progressRing.isHidden = true
            } else {
                progressRing.setProgress(value: CGFloat(percent) * 100, animationDuration: 0.1)
            }
        }
    }
    
    
    func didReceiveProfileImage(_ profileImage: UIImage?) {
        if showingCustomerData {
            if let imageView = view.viewWithTag(10) as? UIImageView {
                imageView.image = profileImage
            }
        }
    }
    
    
    func validationServiceDidChange(_ available: Bool) {
        validationServiceAvailable = available
        if !available {
            retrieveImageSwitch.setOn(false, animated: true)
            retrieveImageSwitch.isEnabled = false
            retrieveImageLabel.textAlignment = .right
            retrieveImageLabel.text = "Validation service unavailable"
        }
    }
    
    
    func showResult(idIsValid: Bool, reason: String? = nil) {

        let validColor = UIColor(hue: 0.3944, saturation: 0.6, brightness: 0.7, alpha: 1.0) /* #48b570 */
        let invalidColor = UIColor(hue: 0.0028, saturation: 0.72, brightness: 0.88, alpha: 1.0) /* #e2413e */
        
        showingCustomerData = true
        captureSession.stopRunning()
        
        // Draw bottom, INFO holder
        let customerInfoHolder = UIView()
        customerInfoHolder.backgroundColor = idIsValid ? validColor : invalidColor
        
        let customerCardWidth = view.frame.size.width - 2*sidePadding
        let customerCardHeight = 0.45*customerCardWidth
        customerInfoHolder.frame = CGRect(x: sidePadding,
                                          y: view.frame.size.height - bottomTrayHeight - 2*sidePadding - customerCardHeight,
                                          width: customerCardWidth,
                                          height: customerCardHeight)
        
        customerInfoHolder.tag = 20
        customerInfoHolder.layer.cornerRadius = 8
        customerInfoHolder.layer.masksToBounds = true
        customerInfoHolder.alpha = 0.0
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(clearCustomerCard))
        customerInfoHolder.isUserInteractionEnabled = true
        customerInfoHolder.addGestureRecognizer(tapGestureRecognizer)
        
        if idIsValid {
            
            self.playSound(name: "validateSuccess")
            
            // - Family name label
            let familyNameLabel = UILabel()
            familyNameLabel.font = UIFont(name: "Avenir-Light", size: 24.0)
            familyNameLabel.textColor = UIColor.white
            familyNameLabel.text = digitalIDvalidator.customerData.familyName
            familyNameLabel.frame = CGRect(x: sidePadding,
                                           y:  10,
                                           width: customerCardWidth,
                                           height: 24.0)
            
            // - Given name label
            let givenNameLabel = UILabel()
            givenNameLabel.font = UIFont(name: "Avenir-Medium", size: 26.0)
            givenNameLabel.textColor = UIColor.white
            givenNameLabel.text = digitalIDvalidator.customerData.givenNames
            givenNameLabel.frame = CGRect(x: sidePadding,
                                          y:  10 + 28.0,
                                          width: customerCardWidth,
                                          height: 26.0)
            // - Gender & age label
            var extraInfo = ""
            if let diffInYears = Calendar.current.dateComponents([.year],
                                                                 from: digitalIDvalidator.customerData.dateOfBirth,
                                                                 to: Date()).year {
                extraInfo = ", \(diffInYears)"
            }
            
            let genderLabel = UILabel()
            genderLabel.font = UIFont(name: "Avenir-Light", size: 18.0)
            genderLabel.textColor = UIColor.white
            genderLabel.text = "\(digitalIDvalidator.customerData.gender)\(extraInfo)"
            genderLabel.frame = CGRect(x: sidePadding,
                                          y:  10 + 28.0 + 30.0 + 16.0,
                                          width: customerCardWidth,
                                          height: 18.0)
            
            customerInfoHolder.addSubview(familyNameLabel)
            customerInfoHolder.addSubview(givenNameLabel)
            customerInfoHolder.addSubview(genderLabel)
            
            // - Date of Birth
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM dd, yyyy"
            
            // If valid AND using online validation service, draw the IMAGE holder
            if retrieveImageSwitch.isOn {
                let customerImageHolder = UIImageView()
                customerImageHolder.backgroundColor = validColor
                
                let customerImageHolderTopOffset: CGFloat = 70.0
                let profileImageHolderWidth = (view.frame.size.width / 2) - 2*sidePadding
                let profileImageHolderHeight = profileImageHolderWidth
                customerImageHolder.frame = CGRect(x: sidePadding,
                                                   y:  customerImageHolderTopOffset,
                                                   width: profileImageHolderWidth,
                                                   height: profileImageHolderHeight)
                
                customerImageHolder.tag = 10
                customerImageHolder.layer.cornerRadius = 8
                customerImageHolder.layer.masksToBounds = true
                customerImageHolder.layer.borderWidth = 3
                customerImageHolder.layer.borderColor = UIColor.white.cgColor
                customerImageHolder.alpha = 0.0
                
                let downloadProgressRing = UICircularProgressRingView(frame: CGRect(x: customerImageHolder.bounds.minX + 10,
                                                                                    y: customerImageHolder.bounds.minY + 10,
                                                                                    width: customerImageHolder.frame.width - 20,
                                                                                    height: customerImageHolder.frame.height - 20))
                downloadProgressRing.tag = 15
                downloadProgressRing.maxValue = 100.0
                downloadProgressRing.shouldShowValueText = false
                downloadProgressRing.outerRingColor = UIColor(hue: 118/360, saturation: 18/100, brightness: 98/100, alpha: 1.0) /* #cefccd */
                downloadProgressRing.innerRingColor = UIColor(hue: 141/360, saturation: 67/100, brightness: 94/100, alpha: 1.0) /* #4ff28a */
                
                customerImageHolder.addSubview(downloadProgressRing)
                
                view.addSubview(customerImageHolder)
                customerImageHolder.fadeIn(withDuration: 1.0, toAlpha: 1.0) {}
            }
        } else {
            if let errorMessage = reason {
                let errorLabel = UILabel()
                let fontSize: CGFloat = 20.0
                errorLabel.numberOfLines = 0
                errorLabel.font = UIFont(name: "Avenir-Light", size: fontSize)
                errorLabel.textColor = UIColor.white
                errorLabel.text = errorMessage
                errorLabel.frame = CGRect(x: 10,
                                          y:  10,
                                          width: customerCardWidth - 10,
                                          height: customerCardHeight * 0.8)
                
                errorLabel.lineBreakMode = .byWordWrapping
                errorLabel.textAlignment = .center
                
                customerInfoHolder.addSubview(errorLabel)
            }
            
            
            self.playSound(name: "validateFailure")
        }
        
        view.addSubview(customerInfoHolder)
        customerInfoHolder.fadeIn(withDuration: 1.0, toAlpha: 1.0) {}
    }
    
    @objc private func clearCustomerCard() {
        showingCustomerData = false
        captureSession.startRunning()
        
        if let customerInfoHolderView = view.viewWithTag(20) {
            customerInfoHolderView.fadeOut(withDuration: 0.6, completion: {})
            customerInfoHolderView.removeFromSuperview()
        }
        
        if let customerImageHolderView = view.viewWithTag(10) {
            customerImageHolderView.fadeOut(withDuration: 0.6, completion: {})
            customerImageHolderView.removeFromSuperview()
        }
    }
    
    func playSound(name: String){
        let url = Bundle.main.url(forResource: name, withExtension:"m4a")!
        do {
            let sound = try AVAudioPlayer(contentsOf: url)
            self.player = sound
            sound.numberOfLoops = 0
            sound.prepareToPlay()
            sound.play()
        } catch {
            print("error loading file")
            // couldn't load file :(
        }
    }
}


extension ValidateController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        if !showingCustomerData {
            
            // 1. Call the validation function from the shared DigitalIDValidator instance,
            //     supplying the metadata objects detected from AVCapture + a boolean as to
            //     whether or not the User wants to use the online validation service.
            let (primaryQrResult, secondaryQrResult) = digitalIDvalidator.validate(metadataObjects: metadataObjects,
                                                                                   useValidationService: retrieveImageSwitch.isOn)
            
            // 2. Unwrap and check the results
            if let primaryQRisValid = primaryQrResult {
                if primaryQRisValid {       // <--- the data contained within the QR code is signed with a valid, digital signature
                    if retrieveImageSwitch.isOn {
                        // (Optional) Perform an additional check with the central validation server.
                        //  This will provide an unequivocable response as to whethet the ID is valid.  Additionaly, it
                        //   will the on-file image of the Customer, which should match the image on the ID.
                        digitalIDvalidator.performOnlineValidation(completion: { (isValid, reason) in
                            self.showResult(idIsValid: isValid, reason: reason)
                        })
                    } else if let secondaryQRisValid = secondaryQrResult {
                        if secondaryQRisValid {
                            showResult(idIsValid: true)
                        } else {
                            showResult(idIsValid: false, reason: "The secondary QR code contained invalid data")
                        }
                    }
                } else {
                    print("Primary QR data does not have a valid digital signature")
                    showResult(idIsValid: false)
                }
            }
        }
    }
}
