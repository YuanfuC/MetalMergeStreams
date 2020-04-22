//
//  ViewController.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/17.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

class ViewController: UIViewController, CaptureDataOutputDelegate {
    
    let preview = PreviewView.init()
    let rtpView = DisplayView.init()
    let processLable = UILabel.init()
    let rtpFpsLabel = UILabel.init()
    let frontCameraFpsLable = UILabel.init()
    let recordingLable = UILabel.init()
    let recordingButton = UIButton.init(type: .custom)
    
    var rtpVideoReader: AVAssetReader?
    var rtpOutput: AVAssetReaderVideoCompositionOutput?
    
    let rtpBufferQueue = DispatchQueue.init(label: "rtp-data")
    let deviceLaunchQueue = DispatchQueue.init(label: "device-launch")
    let videoSavingQueue = DispatchQueue.init(label: "video-save")
    
    var rptCurrentFrame: CVPixelBuffer? = nil
    var mixer = FrameMixer()
    var recorder:FrameRecorder? = nil
    let deviceCapture = DeviceCapture()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUIComponents()
        setupMIxerPipLocation()
        launchDevices()
        startReadVideo()
        configVideoRecorder()
    }
        
    // MARK: - Init recorder
    
    func configVideoRecorder() {
        let videoSettings = deviceCapture.cameraOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mp4)  as! [String: NSObject]
        let audioSettings = deviceCapture.microphoneOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as! [String: NSObject]
        recorder = FrameRecorder.init(videoSettings: videoSettings, audioSettings: audioSettings)
    }
        
    // MARK: - Read rtp video
    
    func initVideoReader(path:String) ->(reader:AVAssetReader?,
        videoOutput:AVAssetReaderVideoCompositionOutput?) {
            
            let url = URL.init(fileURLWithPath: path)
            let asset = AVAsset.init(url: url)
            
            guard let reader = try? AVAssetReader.init(asset: asset) else {
                print("Asset reader init failed")
                return (nil ,nil)
            }
            
            guard let track  = asset.tracks(withMediaType: .video).last else {
                print("Track init failed")
                return (nil, nil)
            }
            
            let videoComposition = AVVideoComposition.init(propertiesOf: asset)
            let output = AVAssetReaderVideoCompositionOutput.init(videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA])
            output.videoComposition = videoComposition;
            reader.add(output);
            return (reader, output)
    }
    
    func startReadVideo() -> Void {
        guard let path = Bundle.main.path(forResource: "rptVideo", ofType: "mp4") else {
            print("Video file not exist")
            return
        }
        
        let tuple = initVideoReader(path: path)
        guard let reader = tuple.reader,
            let output = tuple.videoOutput else {
                print("Init video reader failed")
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
                
                var timeInfo:CMSampleTimingInfo = CMSampleTimingInfo.init()
                CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timeInfo)
                
                
                if -rtpfpsDebugDate.timeIntervalSinceNow >= 1.0 {
                    DispatchQueue.main.sync {
                        rtpFpsLabel.text = String.init(format: "RTP FPS: %d", rptfpsDebugCount)
                    }
                    rptfpsDebugCount = 0;
                    rtpfpsDebugDate = NSDate();
                }
                deviceLaunchQueue.async {
                    self.rptCurrentFrame = pixelBuffer
                }
                rptfpsDebugCount += 1
            }
            
        } else {
            isFinish = true
            print("Finish copyBufferAndAppend")
        }
    }
    
    //MARK: - Open camera and microphone
    
    func launchDevices(){
        guard let _ = deviceCapture.launchCamera(for: .video, position: .front) else {
            print("Launch camera device failed")
            return
        }
        
        guard let sessoin = deviceCapture.launchMicrophone() else {
            print("Launch microphone device failed")
            return
        }
        deviceCapture.setSampleBufferDelegate(self, queue:deviceLaunchQueue)
        
        preview.session = sessoin
        let initialVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft
        preview.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
        
        sessoin.startRunning()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == deviceCapture.cameraOutput {
            let pixelBuffer = mixFrame(sampleBuffer: sampleBuffer)
            let  pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            videoSavingQueue.async {
                self.recorder?.recordVideo(pixelBuffer: pixelBuffer!, withPresentationTime: pts)
            }
            //            receiveCamera(sampleBuffer: sampleBuffer)
        }
        
        if output == deviceCapture.microphoneOutput{
            videoSavingQueue.async {
                self.recorder?.recordAudio(sampleBuffer: sampleBuffer)
            }
            //            receiveAudioBuffer(sampleBuffer: sampleBuffer)
        }
    }
    
    //MARK: - Mix frame
    
    func setupMIxerPipLocation(){
        let normalizedTransform = CGAffineTransform(scaleX: 1.0 / rtpView.frame.width,
                                                    y: 1.0 / rtpView.frame.height)
        let frame = preview.frame.applying(normalizedTransform)
        self.mixer.inFrame = frame
    }
    
    var fpsDebugDate =  NSDate()
    var fpsDebugCount:NSInteger  = 0;
    
    func mixFrame(sampleBuffer:CMSampleBuffer) -> CVPixelBuffer? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Frount Video pixel buffer not exist")
            return nil
        }
        
        guard let rptBuffer = self.rptCurrentFrame else {
            print("RTP pixel buffer not exist")
            return pixelBuffer
        }
        
        if !mixer.isPrepared {
            
            guard let des = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                print("Get buffer des failed")
                return pixelBuffer
            }
            mixer.prepare(with: des, outputRetainedBufferCountHint: 3)
        }
        
        let date = NSDate()
        let mixedBuffer = mixer.mixFrame(rptBuffer, pixelBuffer)
        
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
        return mixedBuffer
    }
    
}

extension ViewController {
    
    func setupUIComponents() {
        let mutiple:CGFloat = UIScreen.main.bounds.width >= 812 ? 0.8: 0.9
        let rtpViewWidth = UIScreen.main.bounds.width * mutiple
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
        
        recordingButton.frame = CGRect.init(x: 80, y: UIScreen.main.bounds.size.height - 60, width: 80, height: 44)
        self.view.addSubview(recordingButton)
        recordingButton.setTitle("Record", for: .normal)
        recordingButton.addTarget(self, action: #selector(buttonClick), for: .touchUpInside)
        recordingButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        recordingButton.setTitleColor(UIColor.systemPink, for: .normal)
        
        let gesture = UIPanGestureRecognizer.init(target: self, action: #selector(gestureCallback))
        self.rtpView.addGestureRecognizer(gesture)
    }
    
    @objc func gestureCallback(ges: UIGestureRecognizer){
        let point = ges.location(in: self.rtpView)
        preview.center = point
        setupMIxerPipLocation()
    }
    
    @objc func  buttonClick() {
        
        let title = self.recorder!.isRecording ? "stop": "Recording"
        recordingButton.setTitle(title, for: .normal)
        
        if !self.recorder!.isRecording  {
            //开始
            videoSavingQueue.async {
                self.recorder?.startRecording()
            }
        } else {
            //结束
            videoSavingQueue.async {
                self.recorder?.stopRecording(completion: { (url) in
                    self.saveMovieToPhotoLibrary(url)
                    DispatchQueue.main.async {
                        self.recordingButton.setTitle("Record", for: .normal)
                    }
                })
            }
        }
        return
    }
    
}

extension ViewController {
    private func saveMovieToPhotoLibrary(_ movieURL: URL) {
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // Save the movie file to the photo library and clean up.
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    creationRequest.addResource(with: .video, fileURL: movieURL, options: options)
                }, completionHandler: { success, error in
                    if !success {
                        print("\("Mixer") couldn't save the movie to your photo library: \(String(describing: error))")
                    } else {
                        
                        DispatchQueue.main.async {
                            let alertMessage = "Saving video success"
                            let message = NSLocalizedString("success saving the process video", comment: alertMessage)
                            let alertAction = UIAlertAction.init(title: "OK", style: .default, handler: nil)
                            let alertController = UIAlertController(title: "Mixer", message: message, preferredStyle: .alert)
                            alertController.addAction(alertAction)
                            self.present(alertController, animated: true, completion: nil)
                        }
                        
                        // Clean up
                        if FileManager.default.fileExists(atPath: movieURL.path) {
                            do {
                                try FileManager.default.removeItem(atPath: movieURL.path)
                            } catch {
                                print("Could not remove file at url: \(movieURL)")
                            }
                        }
                        
                    }
                })
            } else {
                DispatchQueue.main.async {
                    let alertMessage = "Alert message when the user has not authorized photo library access"
                    let message = NSLocalizedString("Mixer does not have permission to access the photo library", comment: alertMessage)
                    let alertController = UIAlertController(title: "Mixer", message: message, preferredStyle: .alert)
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
    }

}
