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
    let rtpView = DisplayView.init()
    let processLable = UILabel.init()
    let rtpFpsLabel = UILabel.init()
    let frontCameraFpsLable = UILabel.init()
    let session = AVCaptureSession()
    var rtpVideoReader: AVAssetReader?
    var rtpOutput: AVAssetReaderVideoCompositionOutput?
    let rtpBufferQueue = DispatchQueue.init(label: "RTP-buffer")
    let frontCameraQueue = DispatchQueue(label: "Front-camera-buffer",
                                         qos: .userInitiated,
                                         attributes: [],
                                         autoreleaseFrequency: .workItem)
    
    var rptCurrentFrame: CVPixelBuffer? = nil
    var mixer = FrameMixer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUIComponents()
        setupMixerFrameConfig()
        self.configCamera()
        startReadVideo()
    }
    
    func setupUIComponents() {
        let rtpViewWidth = UIScreen.main.bounds.width * 0.9
        let rtpViewHeight = rtpViewWidth/(1280/720)
        rtpView.frame = CGRect.init(x: 0, y: 0, width: rtpViewWidth, height: rtpViewHeight)
        rtpView.center = self.view.center
        rtpView.backgroundColor = UIColor.blue
        let previewWidth = rtpViewWidth * 0.25
        let previewHeight = previewWidth/(1280/720)
        preview.frame = CGRect.init(x: rtpViewWidth - previewWidth - 20,
                                    y: rtpViewHeight - previewHeight - 20,
                                    width: previewWidth, height: previewHeight)
        preview.backgroundColor = UIColor.yellow
        self.view.backgroundColor = UIColor.gray
        self.view.addSubview(rtpView)
        rtpView.addSubview(preview)
        processLable.frame = CGRect.init(x: 10, y: 5, width: 200, height: 20)
        processLable.textColor = UIColor.red
        
        rtpFpsLabel.frame = CGRect.init(x: 10, y: 5 + 5 + 20, width: 200, height: 20)
        rtpFpsLabel.textColor = UIColor.blue
        
        frontCameraFpsLable.frame = CGRect.init(x: 10, y: 5 + (5 + 20) * 2, width: 200, height: 20)
        frontCameraFpsLable.textColor = UIColor.green
        rtpView.addSubview(processLable)
        rtpView.addSubview(rtpFpsLabel)
        rtpView.addSubview(frontCameraFpsLable)
    }
    
    func setupMixerFrameConfig(){
        let normalizedTransform = CGAffineTransform(scaleX: 1.0 / rtpView.frame.width,
                                                    y: 1.0 / rtpView.frame.height)
        let frame = preview.frame.applying(normalizedTransform)
        
        self.mixer.inFrame = frame
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
        
        
        
        preview.session = session
        
        let initialVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft
        preview.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
        
        
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
        
        self.rtpOutput = output
        self.rtpVideoReader = reader
        
        assert(reader.startReading())
        
        var isFinish = false
        
        
        rtpBufferQueue.async {
            while !isFinish {
                self.copyFrameVideoVideo(&isFinish)
                Thread.sleep(forTimeInterval:1.0/30.0)
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
    
    func copyFrameVideoVideo(_ isFinish:inout Bool) {
        
        guard let videoOutput = self.rtpOutput else {
            print("RTP video out put is not exist")
            return
        }
        
        if let sample = videoOutput.copyNextSampleBuffer() {
            autoreleasepool{
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                    print("RTP sample is nil")
                    return
                }
                
                DispatchQueue.main.async {
                    let layer = self.rtpView.layer as! AVSampleBufferDisplayLayer
                    layer.enqueue(sample);
                }
                
                if -rtpfpsDebugDate.timeIntervalSinceNow >= 1.0 {
                    DispatchQueue.main.sync {
                        rtpFpsLabel.text = String.init(format: "RTP FPS: %d", rptfpsDebugCount)
                    }
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
        
        if !mixer.isPrepared {
            
            guard let des = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                print("Get buffer des failed")
                return
            }
            mixer.prepare(with: des, outputRetainedBufferCountHint: 3)
        }
        
        let date = NSDate()
        let buffer = mixer.mixFrame(rptBuffer, pixelBuffer)
        
        DispatchQueue.main.sync {
            processLable.text = String.init(format: "process %.02f ms", -date.timeIntervalSinceNow * 1000)
        }
        
        if -fpsDebugDate.timeIntervalSinceNow >= 1.0 {
            DispatchQueue.main.sync {
                frontCameraFpsLable.text = String.init(format: "Camera FPS: %d", fpsDebugCount)
            }
            fpsDebugCount = 0;
            fpsDebugDate = NSDate();
        }
        fpsDebugCount += 1
    }
    
}

