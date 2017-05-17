//
//  ViewController.swift
//  DoubleRemote
//
//  Created by Nicholas Josephson on 2017-05-10.
//  Copyright © 2017 Nicholas Josephson. All rights reserved.
//

import UIKit

class ViewController: UIViewController, DRDoubleDelegate, DRCameraKitImageDelegate, DRCameraKitConnectionDelegate, DRCameraKitControlDelegate,StreamDelegate {
    
    // MARK: IB Outlets
    
    @IBOutlet weak var connectionStatus: UILabel!
    @IBOutlet weak var cameraConnectionStatus: UILabel!
    @IBOutlet weak var poleHeightStatus: UILabel!
    @IBOutlet weak var kickstandStatus: UILabel!
    @IBOutlet weak var robotBatteryStatus: UILabel!
    @IBOutlet weak var cameraView: UIImageView!
    @IBOutlet weak var remoteConnectionStatus: UILabel!
    @IBOutlet weak var ipTextField: UITextField!
    @IBOutlet weak var portTextField: UITextField!
    @IBOutlet weak var slider: UISlider!
    @IBOutlet weak var streamSizeStatus: UILabel!
    @IBOutlet weak var formatSelector: UISegmentedControl!
    
    // MARK: Control Vars
    
    private var drive: Float = 0.0 {
        didSet {
            print("Drive: \(drive)")
        }
    }
    
    private var turn: Float = 0.0 {
        didSet {
            print("Turn: \(turn)")
        }
    }
    
    // MARK: Camera Vars
    
    private var currentFrame: UIImage? {
        didSet {
            cameraView.image = currentFrame
        }
    }
    
    // MARK: Socket Stream Vars
    
    private var inputStream: InputStream!
    private var outputStream: OutputStream!
    
    // MARK: View Controller Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        DRDouble.shared().delegate = self
        DRCameraKit.shared().imageDelegate = self
        DRCameraKit.shared().connectionDelegate = self
        
        print("Control SDK: \( kDoubleBasicSDKVersion ), Camera SDK: \( kCameraKitSDKVersion )")
    }
    
    // MARK: Socket Stream Methods
    
    func initNetworkCommunication(ip: String, port: Int) {
        var inp :InputStream?
        var out :OutputStream?
        
        Stream.getStreamsToHost(withName: ip, port: port, inputStream: &inp, outputStream: &out)
        
        inputStream = inp!
        outputStream = out!
        
        inputStream.delegate = self
        outputStream.delegate = self
        
        inputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        outputStream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        
        inputStream.open()
        outputStream.open()
    }
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print("got an event")
        switch eventCode {
        case Stream.Event.openCompleted:
            print("\( (aStream == inputStream ) ? "Input" : "Output" ) stream open")
            remoteConnectionStatus.text = "Connected"
        case Stream.Event.hasBytesAvailable:
            if aStream == inputStream {
                var input = ""
                var readByte :UInt8 = 0
                
                while inputStream.hasBytesAvailable {
                    inputStream.read(&readByte, maxLength: 1)
                    input.append(Character(UnicodeScalar(readByte)))
                }
                
                handleCommand(input)
            }
        case Stream.Event.hasSpaceAvailable:
            if aStream == outputStream {
                print("send stuff")
            }
        case Stream.Event.errorOccurred:
            print("CONNECTION ERROR: Connection to the host failed!")
            remoteConnectionStatus.text = "Not Connected"
        case Stream.Event.endEncountered:
            print("\( (aStream == inputStream ) ? "Input" : "Output" ) stream closed")
            remoteConnectionStatus.text = "Not Connected"
        default:
            print("CONNECTION ERROR")
            remoteConnectionStatus.text = "Connection Error"
        }
    }
    
    func handleCommand(_ command: String) {
        switch command {
        case "f\n": //forward
            drive = 1
        case "b\n": //back
            drive = -1
        case "l\n": //left
            turn = -1
        case "r\n": //right
            turn = 1
        case "s\n": //stop drive
            drive = 0
        case "t\n": //stop turn
            turn = 0
        case "x\n": //stop drive and turn
            drive = 0
            turn = 0
        case "u\n": //pole up
            DRDouble.shared().poleUp()
        case "d\n": //pole down
            DRDouble.shared().poleDown()
        case "h\n": //stop drive and turn
            DRDouble.shared().poleStop()
        case "p\n": //park
            toggleKickstand()
        default:
            print("Recived unrecognized command: \"\(command)\"")
        }
    }
    
    // MARK: Camera Kit Delegate Methods
    
    func cameraKitConnectionStatusDidChange(_ theKit: DRCameraKit!) {
        cameraConnectionStatus.text = (theKit.isConnected()) ? "Connected" : "Not Connected"
        if (theKit.isConnected()) {
            camLow()
        }
    }
    
    func cameraKit(_ theKit: DRCameraKit!, didReceive theImage: UIImage!, sizeInBytes length: Int) {
        currentFrame = theImage
        
        if outputStream != nil && outputStream.hasSpaceAvailable {
            let img: Data?
            if formatSelector.selectedSegmentIndex == 0 {
                img = UIImageJPEGRepresentation(theImage, CGFloat(slider.value))
            } else {
                img = UIImagePNGRepresentation(theImage)
            }
            
            let buffer: Data = img!
            let length = buffer.count
            streamSizeStatus.text = String(length)
            
            //Convert Data to [UInt8] array
            var myArray = [UInt8](repeating: 0, count: length)
            buffer.copyBytes(to: &myArray, count: length)
            
            //sent size header
            let header = "\(length)\n"
            let headData: Data = header.data(using: String.Encoding.ascii)! as Data
            var headArray = [UInt8](repeating: 0, count: headData.count)
            headData.copyBytes(to: &headArray, count: headData.count)
            outputStream.write(&headArray, maxLength: headArray.count)
            
            //send data
            var bytesSent = 0
            while bytesSent < length {
                let result = outputStream.write(&myArray + bytesSent, maxLength: length - bytesSent)
                if result > 0 {
                    bytesSent += result
                } else {
                    print(outputStream.streamError.debugDescription)
                    bytesSent = length
                }
            }
        }
    }
    
    func cameraKitReceivedStatusUpdate(_ theKit: DRCameraKit!) {
        theKit.startVideo()
        theKit.startCharging()
        
    }
    
    // MARK: Double Control Delegate Methods
    
    func doubleDidConnect(_ theDouble: DRDouble!) {
        connectionStatus.text = "Connected"
    }
    
    func doubleDidDisconnect(_ theDouble: DRDouble!) {
        connectionStatus.text = "Not Connected"
    }
    
    func doubleStatusDidUpdate(_ theDouble: DRDouble!) {
        poleHeightStatus.text = String(DRDouble.shared().poleHeightPercent)
        kickstandStatus.text = String(DRDouble.shared().kickstandState)
        robotBatteryStatus.text = String(DRDouble.shared().batteryPercent)
    }
    
    func doubleDriveShouldUpdate(_ theDouble: DRDouble!) {
        DRDouble.shared().variableDrive(drive, turn: turn)
    }
    
    // MARK: Double Control
    
    func toggleKickstand() {
        drive = 0
        turn = 0
        
        switch DRDouble.shared().kickstandState {
        case 1:
            DRDouble.shared().retractKickstands()
        case 2:
            DRDouble.shared().deployKickstands()
        default:
            print("error parking/unparking")
        }
    }
    
    // MARK: IB Actions
    
    @IBAction func connectToRemote(_ sender: UIButton) {
        let ip: String = ipTextField.text!
        let port: Int = Int(portTextField.text!)!
        
        initNetworkCommunication(ip: ip, port: port)
    }
    
    @IBAction func charge(_ sender: UIButton) {
        DRCameraKit.shared().startCharging()
    }

    @IBAction func stopCharge(_ sender: UIButton) {
        DRCameraKit.shared().stopCharging()
    }
    
    @IBAction func startCam(_ sender: UIButton) {
        DRCameraKit.shared().startVideo()
    }
    
    @IBAction func stopCam(_ sender: UIButton) {
        DRCameraKit.shared().stopVideo()
    }
    
    @IBAction func setLow(_ sender: UIButton) {
        camLow()
    }
    
    @IBAction func setMedium(_ sender: UIButton) {
        camMedium()
    }
    
    @IBAction func setHigh(_ sender: UIButton) {
        camHigh()
    }
    
    @IBAction func park(_ sender: UIButton) {
        toggleKickstand()
    }
    
    @IBAction func poleUp(_ sender: UIButton) {
        DRDouble.shared().poleUp()
    }
    
    @IBAction func poleDown(_ sender: UIButton) {
        DRDouble.shared().poleDown()
    }
    
    @IBAction func poleStop(_ sender: UIButton) {
        DRDouble.shared().poleStop()
    }
    
    @IBAction func driveForward(_ sender: UIButton) {
        drive = 1
    }
    
    @IBAction func driveBack(_ sender: UIButton) {
        drive = -1
    }
    
    @IBAction func stopDrive(_ sender: UIButton) {
        drive = 0
    }
    
    @IBAction func turnLeft(_ sender: UIButton) {
        turn = -1
    }
    
    @IBAction func turnRight(_ sender: UIButton) {
        turn = 1
    }
    
    @IBAction func stopTurn(_ sender: UIButton) {
        turn = 0
    }
    
}

