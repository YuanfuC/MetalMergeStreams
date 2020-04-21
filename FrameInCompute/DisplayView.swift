//
//  DisplayView.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/21.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import Foundation
import UIKit
import AVFoundation

class DisplayView: UIView {
    
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }
}
