//
//  ViewController.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/17.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import UIKit
import AVFoundation

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let preview = PreviewView.init()
    let session = AVCaptureSession()
    let output = AVCaptureMetadataOutput()
    let rtpBufferQueue = DispatchQueue.init(label: "RTP-buffer")
    let frontCameraQueue = DispatchQueue(label: "Front-camera-buffer",
                                         qos: .userInitiated,
                                         attributes: [],
                                         autoreleaseFrequency: .workItem)
    
    var rptCurrentFrame: CVPixelBuffer? = nil
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        print("GET START")
        
        self.view.addSubview(preview)
        preview.frame = CGRect.init(x: 0, y: 0, width: UIScreen.main.bounds.height * 0.75 / (1280/720), height: UIScreen.main.bounds.height * 0.75)
        preview.center = self.view.center
        self.view.backgroundColor = UIColor.gray
        
        
        self.configCamera()
        
        
        startReadVideo()
    }
    
    func configCamera() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            
            print("Get camera failed")
            return
        }
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: device) else {
            print("Create video input failed")
            return
        }
        
        session.beginConfiguration()
        
        
        if session.canAddInput(videoDeviceInput) {
            session.addInput(videoDeviceInput)
        } else {
            print("Couldn't add video device input to the session.")
            session.commitConfiguration()
            return
        }
        session.sessionPreset = .hd1280x720
        device.supportsSessionPreset(.hd1280x720)
        
        session.commitConfiguration()
        
        let initialVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft
        preview.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
        
        preview.session = session
        
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
        
        let dataOutputQueue = frontCameraQueue
        
        
        videoOutput.setSampleBufferDelegate(self,
                                            queue: dataOutputQueue)
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }else {
            print("Couldn't add video output to the session.")
            session.commitConfiguration()
            return
        }
        
        self.session.startRunning()
        
    }
    
    
    func startReadVideo() -> Void {
        guard let path = Bundle.main.path(forResource: "rptVideo", ofType: "mp4") else {
            print("file not exist")
            return
        }
        
        let tuple = initVideoReader(path: path)
        
        guard let reader = tuple.reader,
            let output = tuple.videoOutput else {
                print("init video reader failed")
                return;
        }
        assert(reader.startReading())
        
        var isFinish = false
        
        rtpBufferQueue.async {
            while !isFinish {
                self.copyFrameVideoVideo(output, &isFinish)
                Thread.sleep(forTimeInterval:1.0/100.0)
            }
        }
    }
    
    func initVideoReader(path:String) ->(reader:AVAssetReader?,
        videoOutput:AVAssetReaderVideoCompositionOutput?) {
            
            let url = URL.init(fileURLWithPath: path)
            let asset = AVAsset.init(url: url)
            
            guard let reader = try? AVAssetReader.init(asset: asset) else {
                print("Asset reader init failed")
                return (nil ,nil)
            }
            
            guard let track  = asset.tracks(withMediaType: .video).last else {
                print("track init failed")
                return (nil, nil)
            }
            
            let videoComposition = AVVideoComposition.init(propertiesOf: asset)
            let output = AVAssetReaderVideoCompositionOutput.init(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            output.videoComposition = videoComposition;
            reader.add(output);
            return (reader, output)
    }
    
    
    var rtpfpsDebugDate =  NSDate()
    var rptfpsDebugCount:NSInteger  = 0;
    
    func copyFrameVideoVideo(_ output:AVAssetReaderVideoCompositionOutput,
                             _ isFinish:inout Bool) {
        
        if let sample = output.copyNextSampleBuffer() {
            autoreleasepool{
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                    print("RTP sample is nil")
                    return
                }
                
                if -rtpfpsDebugDate.timeIntervalSinceNow >= 1.0 {
                    print("Camera count", rptfpsDebugCount);
                    rptfpsDebugCount = 0;
                    rtpfpsDebugDate = NSDate();
                }
                frontCameraQueue.async {
                    self.rptCurrentFrame = pixelBuffer
                }
                rptfpsDebugCount += 1
            }
            
        } else {
            isFinish = true
            print("Finish copyBufferAndAppend")
        }
    }
    
    
    
    var fpsDebugDate =  NSDate()
    var fpsDebugCount:NSInteger  = 0;
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Frount Video pixel buffer not exist")
            return
        }
        
        guard let rptBuffer = self.rptCurrentFrame else {
            print("RTP pixel buffer not exist")
            return
        }
        
        if -fpsDebugDate.timeIntervalSinceNow >= 1.0 {
            print("BFD_ buffer count", fpsDebugCount);
            fpsDebugCount = 0;
            fpsDebugDate = NSDate();
        }
        fpsDebugCount += 1
    }
    
}

