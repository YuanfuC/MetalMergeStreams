//
//  AppDelegate.swift
//  FrameInCompute
//
//  Created by ChenYuanfu on 2020/4/17.
//  Copyright © 2020 ChenYuanfu. All rights reserved.
//

import UIKit
import GCDWebServers

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    var webServer: GCDWebServer?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        // Override point for customization after application launch.
        let logPath = NSHomeDirectory();
        webServer = GCDWebUploader.init(uploadDirectory: logPath)
        webServer!.start(withPort: 33123, bonjourName: "HI!!!")
        return true
    }
    
    
}

