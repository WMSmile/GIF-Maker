//
//  PixelImageView.swift
//  ImageFun
//
//  Created by Christian Lundtofte on 25/05/2017.
//  Copyright © 2017 Christian Lundtofte. All rights reserved.
//

import Cocoa

fileprivate struct PixelChange {
    var location: (x: Int, y: Int)!
    var oldColor: NSColor!
    var newColor: NSColor!
    var size: Int!
}

fileprivate class UndoOperation {
    var changes:[PixelChange] = []
}

class PixelImageView: NSImageView {
    
    static let imageChangedNotificationName = Notification.Name(rawValue: "ColorChangedOutside")
    
    // Extra image data
    fileprivate var imageBitmapRep : NSBitmapImageRep?
    
    // Drawing variables
    fileprivate var drawing = false
    fileprivate var previousDrawingPosition:(x: Int, y: Int)?
    
    // Undo / redo variables
    fileprivate var undoOperations:[UndoOperation] = []
    fileprivate var redoOperations:[UndoOperation] = []
    fileprivate var currentUndoOperation:UndoOperation?
    
    fileprivate static let maxUndoRedoCount = 30
    
    override func awakeFromNib() {
        super.awakeFromNib()
        NotificationCenter.default.addObserver(self, selector: #selector(PixelImageView.imageChanged),
                                               name: PixelImageView.imageChangedNotificationName,
                                               object: nil)
    }
    
    // Disables antialiasing (No smoothing, clean pixels, makes sense when creating gifs.)
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current()?.imageInterpolation = .none
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
    
    // MARK: Notifications
    @objc func imageChanged() {
        guard let img = self.image else {
            return
        }
        
        self.imageBitmapRep = img.getBitmapRep()
    }
    
    // MARK: Mouse actions
    // Mouse down
    override func mouseDown(with event: NSEvent) {
        let windowLoc = event.locationInWindow
        let pixelLoc = self.convertWindowToPixels(windowLoc: windowLoc)
        
        // User is using eyedropper tool
        if DrawingOptionsHandler.shared.isPickingColor {
            
            // Set color
            if let color = self.getPixelColor(x: pixelLoc.x, y: pixelLoc.y) {
                DrawingOptionsHandler.shared.drawingColor = color
            }
            
            // Disable eyedropper and send notifications
            DrawingOptionsHandler.shared.isPickingColor = false
            NotificationCenter.default.post(name: DrawingOptionsHandler.colorChangedNotificationName, object: nil)
            NotificationCenter.default.post(name: DrawingOptionsHandler.usedEyeDropperNotificationName, object: nil)
            
            return
        }
        
        // Normal drawing procedure
        self.drawing = true
        self.previousDrawingPosition = pixelLoc
        
        self.currentUndoOperation = UndoOperation()
        self.setPixelColor(color: &DrawingOptionsHandler.shared.drawingColorPtr,
                           x: pixelLoc.x,
                           y: pixelLoc.y,
                           canUndo: true,
                           size: DrawingOptionsHandler.shared.brushSize)
    }
    
    // Mouse drag / mouse moved while mouse down
    // If we're drawing, draw new pixels
    override func mouseDragged(with event: NSEvent) {
        if !drawing {
            return
        }
        
        let windowLoc = event.locationInWindow
        let pixelLoc = self.convertWindowToPixels(windowLoc: windowLoc)
        
        if self.previousDrawingPosition == nil {
            self.setPixelColor(color: &DrawingOptionsHandler.shared.drawingColorPtr,
                               x: pixelLoc.x,
                               y: pixelLoc.y,
                               canUndo: true,
                               size: DrawingOptionsHandler.shared.brushSize)
            self.previousDrawingPosition = pixelLoc
            return
        }
        
        // Only draw on changed pixel, no reason to draw more than necessary
        if pixelLoc.x != previousDrawingPosition!.x || pixelLoc.y != previousDrawingPosition!.y {
            self.setPixelColor(color: &DrawingOptionsHandler.shared.drawingColorPtr,
                               x: pixelLoc.x,
                               y: pixelLoc.y,
                               canUndo: true,
                               size: DrawingOptionsHandler.shared.brushSize)
            self.previousDrawingPosition = pixelLoc
        }
    }

    // Mouse up
    override func mouseUp(with event: NSEvent) {
        drawing = false
        
        // Add current undo to list
        self.closeCurrentUndo()
    }
    
    
    // MARK: Undo and Redo
    func undo() {
        if let undoOp = self.undoOperations.last {
            undoOp.changes.reversed().forEach({ (change) in
                var tmps:[Int] = change.oldColor.getRGBAr()
                self.setPixelColor(color: &tmps, x: change.location.x, y: change.location.y, canUndo: false)
            })
            self.undoOperations.removeLast()
            self.redoOperations.append(undoOp)
            
            if self.redoOperations.count > PixelImageView.maxUndoRedoCount {
                self.redoOperations.removeFirst()
            }
        }
    }
    
    func redo() {
        if let redoOp = self.redoOperations.last {
            redoOp.changes.reversed().forEach({ (change) in
                var tmps:[Int] = change.newColor.getRGBAr()
                self.setPixelColor(color: &tmps, x: change.location.x, y: change.location.y, canUndo: false)
            })
            self.redoOperations.removeLast()
            self.undoOperations.append(redoOp)
        }
    }
    
    func resetUndoRedo() {
        self.redoOperations.removeAll()
        self.undoOperations.removeAll()
    }
    
    func closeCurrentUndo() {
        if let op = self.currentUndoOperation {
            self.undoOperations.append(op)
            
            if self.undoOperations.count > PixelImageView.maxUndoRedoCount {
                self.undoOperations.removeFirst()
            }
            
            
            self.currentUndoOperation = nil
        }
    }
    
    func createUndoOperation(x: Int, y: Int, newColor: NSColor, size: Int) {
        // Create undo operation
        guard let curColor = getPixelColor(x: x, y: y) else {
//            
//            if !drawing {
//                return
//            }
//            
//            // Dragged outside window
//            self.closeCurrentUndo()
//            
//            drawing = false
//            
            return
        }
        
        self.currentUndoOperation?.changes.append(PixelChange(location: (x: x, y: y), oldColor: curColor, newColor: newColor, size: size))
    }
    
    
    // MARK: Helpers
    // Images and NSViews have flipped Y coordinates, this turns them
    func pointInFlippedRect(inPoint: NSPoint, aRect: NSRect) -> NSPoint {
        return NSMakePoint(inPoint.x, NSHeight(aRect) - inPoint.y)
    }
    
    // Converts window event position go pixel coordinates
    func convertWindowToPixels(windowLoc: NSPoint) -> (x: Int, y: Int) {
        guard let imgRep = self.imageBitmapRep else { return (x: 0, y: 0) }
        
        let localLoc = self.pointInFlippedRect(inPoint: self.convert(windowLoc, from: nil), aRect: self.frame)
        
        let height = self.frame.height
        let width = self.frame.width
        let pixelHeight = CGFloat(imgRep.pixelsHigh)
        let pixelWidth = CGFloat(imgRep.pixelsWide)
        
        let clickX = Int(ceil((pixelWidth/width)*localLoc.x))-1
        let clickY = Int(ceil((pixelHeight/height)*localLoc.y))-1
        
        return (x: clickX, y: clickY)
    }
    
    
    // MARK: Drawing
    // Sets a color at a given coordinate
    func setPixelColor(color: UnsafeMutablePointer<Int>, x: Int, y: Int, canUndo: Bool, size: Int = 1) {
        guard let imgRep = self.imageBitmapRep else { Swift.print("Error"); return }
        
        self.image?.lockFocus()
        if canUndo {
            self.createUndoOperation(x: x, y: y, newColor: DrawingOptionsHandler.shared.drawingColor, size: size)
        }
        
        if size == 1 { // Draw single pixel
            imgRep.setPixel(color, atX: x, y: y)
        }
        else {
            // Draw all pixels inside radius
            let r = Int(size/2)
            let r2 = r*r
            
            var i:Int = y - r
            while i < y + r {
                let di2:Int = (i-y)*(i-y)
                var j:Int = x-r
                
                while j < x+r {
                    if (j-x)*(j-x) + di2 <= r2 {
                        imgRep.setPixel(color, atX: x, y: y)
                    }
                    j += 1
                }
                i += 1
            }
        }
        self.image?.unlockFocus()
 
        
//        let newImg = NSImage()
//        newImg.addRepresentation(imgRep)
//        self.image = newImg
    }
    
    // Returns NSColor at given coordinates
    func getPixelColor(x: Int, y: Int) -> NSColor? {
        guard let image = self.image else { return nil }
        guard let imgRep = image.getBitmapRep() else { return nil }
        
        return imgRep.colorAt(x:x, y:y)
    }
}
