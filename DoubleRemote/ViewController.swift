//
//  ViewController.swift
//  DoubleRemote
//
//  Created by Nicholas Josephson on 2017-05-10.
//  Copyright © 2017 Nicholas Josephson. All rights reserved.
//

import UIKit

class ViewController: UIViewController, DRDoubleDelegate, DRCameraKitImageDelegate, DRCameraKitConnectionDelegate, StreamDelegate {
    
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
            if drive == 0 {
                DRCameraKit.shared().setLED(UIColor.red)
            } else {
                DRCameraKit.shared().setLED(UIColor.green)
            }
        }
    }
    
    private var turn: Float = 0.0 {
        didSet {
            print("Turn: \(turn)")
            if drive == 0 && turn != 0 {
                DRCameraKit.shared().setLED(UIColor.yellow)
            } else {
                DRCameraKit.shared().setLED(UIColor.red)
            }
        }
    }
    
    // MARK: Camera Vars
    
    private var currentFrame: UIImage? {
        didSet {
            cameraView.image = currentFrame
        }
    }
    
    // MARK: Socket Stream Vars
    
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var connected = false {
        didSet {
            if connected {
                remoteConnectionStatus.text = "Connected"
            } else {
                inputStream?.close();
                inputStream?.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                outputStream?.close();
                outputStream?.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
                remoteConnectionStatus.text = "Not Connected"
            }
        }
    }
    
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
        Stream.getStreamsToHost(withName: ip, port: port, inputStream: &inputStream, outputStream: &outputStream)
        
        inputStream!.delegate = self
        outputStream!.delegate = self
        
        inputStream!.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        outputStream!.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
        
        inputStream!.open()
        outputStream!.open()
    }
    
    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        print("got an event")
        switch eventCode {
        case Stream.Event.openCompleted:
            print("\( (aStream == inputStream ) ? "Input" : "Output" ) stream open")
            connected = true
        case Stream.Event.hasBytesAvailable:
            if aStream == inputStream {
                while inputStream!.hasBytesAvailable {
                    var readByte :UInt8 = 0
                    inputStream!.read(&readByte, maxLength: 1)
                    
                    handle(command: Character(UnicodeScalar(readByte)))
                }
            }
        case Stream.Event.hasSpaceAvailable:
            if aStream == outputStream {
                print("Output stream has space available")
            }
        case Stream.Event.errorOccurred:
            print("CONNECTION ERROR: Connection to the host failed!")
            connected = false
        case Stream.Event.endEncountered:
            print("\( (aStream == inputStream ) ? "Input" : "Output" ) stream closed")
            connected = false
        default:
            print("CONNECTION ERROR")
            connected = false
        }
    }
    
    func handle(command: Character) {
        switch command {
        case "f": //forward
            drive = 1
        case "b": //back
            drive = -1
        case "l": //left
            turn = -1
        case "r": //right
            turn = 1
        case "s": //stop drive
            drive = 0
        case "t": //stop turn
            turn = 0
        case "x": //stop drive and turn
            drive = 0
            turn = 0
        case "u": //pole up
            DRDouble.shared().poleUp()
        case "d": //pole down
            DRDouble.shared().poleDown()
        case "h": //stop pole
            DRDouble.shared().poleStop()
        case "p": //park
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
            theKit.startVideo()
        }
    }
    
    func cameraKit(_ theKit: DRCameraKit!, didReceive theImage: UIImage!, sizeInBytes length: Int) {
        currentFrame = theImage
        
        if connected && outputStream!.hasSpaceAvailable {
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
            outputStream!.write(&headArray, maxLength: headArray.count)
            
            //send data
            var bytesSent = 0
            while bytesSent < length {
                let result = outputStream!.write(&myArray + bytesSent, maxLength: length - bytesSent)
                if result > 0 {
                    bytesSent += result
                } else {
                    print(outputStream!.streamError.debugDescription)
                    bytesSent = length
                }
            }
        }
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

