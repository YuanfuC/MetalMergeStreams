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
    
    let deviceCapture = DeviceCapture()
    
    var rtpVideoReader: AVAssetReader?
    var rtpOutput: AVAssetReaderVideoCompositionOutput?
    let rtpBufferQueue = DispatchQueue.init(label: "RTP-buffer")
    let frontCameraQueue = DispatchQueue(label: "Front-camera-buffer",
                                         qos: .userInitiated,
                                         attributes: [],
                                         autoreleaseFrequency: .workItem)
    let videoSavingQueue = DispatchQueue.init(label: "Saving-video")
    
    var rptCurrentFrame: CVPixelBuffer? = nil
    var mixer = FrameMixer()
    
    var videoWriter:AVAssetWriter? = nil
    var videoInput:AVAssetWriterInput? = nil
    var audioInput: AVAssetWriterInput?
    var videoInputAdaptor:AVAssetWriterInputPixelBufferAdaptor? = nil
    var isRecording:Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUIComponents()
        setupMixerFrameConfig()
        launchDevices()
        startReadVideo()
        configVideoCreator()
    }
    
    func configVideoCreator(){
        (videoWriter, videoInput) = initVideoWriter()
        guard let writer = videoWriter,
            let input = videoInput else {
                print("Video writer is not exist")
                return
        }
        
        var videoWriterInputPixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
        let sourcePixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 1280,
            kCVPixelBufferHeightKey as String: 720
        ]
        
        videoWriterInputPixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )
        
        guard let adaptor = videoWriterInputPixelBufferAdaptor else {
            print("Adaptor create failed")
            assert(false)
            return
        }
        videoInputAdaptor = adaptor
    }
    
    func setupMixerFrameConfig(){
        let normalizedTransform = CGAffineTransform(scaleX: 1.0 / rtpView.frame.width,
                                                    y: 1.0 / rtpView.frame.height)
        let frame = preview.frame.applying(normalizedTransform)
        self.mixer.inFrame = frame
    }
    
    func launchDevices(){
        guard let _ = deviceCapture.launchCamera(for: .video, position: .front) else {
            print("Launch camera device failed")
            return
        }
        
        guard let sessoin = deviceCapture.launchMicrophone() else {
            print("Launch microphone device failed")
            return
        }
        deviceCapture.setSampleBufferDelegate(self, queue:frontCameraQueue)
        
        preview.session = sessoin
        let initialVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft
        preview.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
        
        sessoin.startRunning()
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
    
    func createDocPositionURL(_ fileName:String) -> URL? {
        
        guard let dirPath = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).last else {
            return nil
        }
        let filePath = dirPath + "/" + fileName
        return URL.init(fileURLWithPath: filePath)
    }
    
    func initVideoWriter() -> (writer:AVAssetWriter?, videoInput:AVAssetWriterInput?) {
        
        guard let fileURL = createDocPositionURL("resultVideo.mp4") else {
            assert(false)
            return (nil, nil)
        }
        
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            print("Remove file success")
        } catch {
            print("Remove file \(error)")
        }
        
        let assetWriter = try! AVAssetWriter.init(url: fileURL, fileType: .mp4)
        
        let videoConfig = [AVVideoCodecKey: AVVideoCodecType.h264,
                           AVVideoWidthKey: NSNumber(1280),
                           AVVideoHeightKey:NSNumber(720)] as [String : Any]
        let videoAssetInput = AVAssetWriterInput.init(mediaType: .video, outputSettings: videoConfig)
        videoAssetInput.expectsMediaDataInRealTime = true
        // Add an audio input
        let audioSettings = deviceCapture.microphoneOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mp4) as! [String: NSObject]
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings:audioSettings)
        audioInput!.expectsMediaDataInRealTime = true
        
        if assetWriter.canAdd(audioInput!) {
            assetWriter.add(audioInput!)
        } else {
            assert(false)
        }
        
        if assetWriter.canAdd(videoAssetInput) {
            assetWriter.add(videoAssetInput)
        } else {
            assert(false)
        }
        
        return (assetWriter, videoAssetInput)
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
    
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == deviceCapture.cameraOutput {
            receiveCamera(sampleBuffer: sampleBuffer)
        }
        
        if output == deviceCapture.microphoneOutput{
            receiveAudioBuffer(sampleBuffer: sampleBuffer)
        }
    }
    
    var fpsDebugDate =  NSDate()
    var fpsDebugCount:NSInteger  = 0;
    
    
    func receiveCamera(sampleBuffer:CMSampleBuffer)  {
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
        let mixedBuffer = mixer.mixFrame(rptBuffer, pixelBuffer)
        
        DispatchQueue.main.sync {
            processLable.text = String.init(format: "process %.02f ms", -date.timeIntervalSinceNow * 1000)
        }
        
        if let buffer = mixedBuffer,
            isRecording {
            videoSavingQueue.async {
                self.savingVideo(pixelBuffer: buffer, sampleBuffer)
            }
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
    
    var audoiTimeSeconds = 0.0
    
    func receiveAudioBuffer(sampleBuffer:CMSampleBuffer)  {
        if isRecording {
            videoSavingQueue.async {
                if self.audioInput!.isReadyForMoreMediaData {
                    var timeInfo:CMSampleTimingInfo = CMSampleTimingInfo.init()
                    CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timeInfo)
                    
                    let newTime = CMTime.init(seconds: self.audoiTimeSeconds, preferredTimescale: 44100)
                    self.audoiTimeSeconds += 1.0/44100.0
                    
                    if #available(iOS 13.0, *) {
                        try! sampleBuffer.setOutputPresentationTimeStamp(newTime)
                    } else {
                        // Fallback on earlier versions
                    }
                    self.audioInput!.append(sampleBuffer)
                    
                } else {
                    print("")
                }
            }
        }
    }
    
    var videoTimeSeconds = 0.0
    func savingVideo(pixelBuffer:CVPixelBuffer, _ sampleBuffer:CMSampleBuffer) {
        guard let adaptor = videoInputAdaptor else {
            print("Video adaptor not exsit")
            return
        }
        
        guard let writer = videoWriter else {
            print("Video wirter not exsit")
            return
        }
        
        var formatDescription:CMVideoFormatDescription? = nil
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)
        
        let  videoTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        
        if videoWriter!.status == .unknown {
            videoWriter!.startWriting()
            videoWriter!.startSession(atSourceTime: videoTime)
        } else if videoWriter!.status == .writing {
            if !adaptor.assetWriterInput.isReadyForMoreMediaData {
                print("NOT READY");
                return;
            }
            
            if (adaptor.append(pixelBuffer, withPresentationTime: videoTime) == false) {
                print("error:\(String(describing: writer.error))")
                assert(false)
            } else {
                print(String(format: "success append frame: %.03f", videoTime.seconds))
            }
        }
        
        
    }
    
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
        
        recordingButton.frame = CGRect.init(x: 40, y: UIScreen.main.bounds.size.height - 60, width: 80, height: 44)
        self.view.addSubview(recordingButton)
        recordingButton.setTitle("Record", for: .normal)
        recordingButton.addTarget(self, action: #selector(buttonClick), for: .touchUpInside)
        recordingButton.titleLabel?.font = UIFont.systemFont(ofSize: 14)
        recordingButton.setTitleColor(UIColor.orange, for: .normal)
    }
    
    @objc func  buttonClick() {
        
        let title = self.isRecording ? "stop": "Recording"
        recordingButton.setTitle(title, for: .normal)
        
        videoSavingQueue.async {
            if (self.isRecording) {
                self.videoWriter?.finishWriting {
                    print("Write video success")
                    DispatchQueue.main.sync {
                        self.recordingButton.isEnabled = false;
                    }
                    
                    guard let fileURL = self.createDocPositionURL("resultVideo.mp4") else {
                        return 
                    }
                    self.saveMovieToPhotoLibrary(fileURL)
                }
            }
            self.isRecording = !self.isRecording
        }
    }
    
}

