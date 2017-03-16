//
//  PreviewViewController.swift
//  Smart GIF Maker
//
//  Created by Christian Lundtofte on 16/03/2017.
//  Copyright © 2017 Christian Lundtofte. All rights reserved.
//

import Cocoa

class PreviewViewController: NSViewController {
    @IBOutlet var previewImageView:NSImageView!
    var previewImage:NSImage?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let previewImage = previewImage {
            previewImageView.image = previewImage
        }
    }
    
    
    @IBAction func closeButtonClicked(sender: AnyObject?) {
        self.dismiss(self)
    }
}
