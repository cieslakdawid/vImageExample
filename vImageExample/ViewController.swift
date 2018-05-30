//
//  ViewController.swift
//  vImageExample
//

import UIKit
import Accelerate
import AVFoundation

class ViewController: UIViewController {

    /// Temporary UIImageView for presenting frame from vImage buffer
    @IBOutlet weak var previewImageView: UIImageView!
    
    /// Manager for camera capture activity
    fileprivate var captureSession = AVCaptureSession()
    
    /// Provides access to frames captured with camera
    fileprivate let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    
    /// Indicates if preview is active
    fileprivate var isPreviewActive: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
       

        // Request camera permission
        if AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) ==  AVAuthorizationStatus.authorized {
            print("Permission already granted")
            self.startCaptureSession()
        } else {
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { (granted: Bool) -> Void in
                if granted == true {
                   print("Permission granted")
                    self.startCaptureSession()
                } else {
                   print("Permission not granted")
                }
            })
        }
    }
    
    /// Start capturing video
    private func startCaptureSession() {
        
        let captureQueue = DispatchQueue(label: "moview.capture")
        
        videoDataOutput.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: captureQueue)
        
        captureSession.sessionPreset = AVCaptureSessionPresetiFrame1280x720
        let videoDevice = AVCaptureDevice.defaultDevice(withMediaType:  AVMediaTypeVideo)
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Capture device error")
            return
        }
    
        captureSession.addInput(videoDeviceInput)
        captureSession.addOutput(videoDataOutput)
        
        captureSession.startRunning()
    }
}

// MARK: - Actions
extension ViewController {
     @IBAction func didPressStart(_ sender: Any) {
        isPreviewActive = !isPreviewActive
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        guard isPreviewActive == true else {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        var buffer: vImage_Buffer = vImage_Buffer()
        buffer.data = CVPixelBufferGetBaseAddress(pixelBuffer)
        buffer.rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        buffer.width = vImagePixelCount(CVPixelBufferGetWidth(pixelBuffer))
        buffer.height = vImagePixelCount(CVPixelBufferGetHeight(pixelBuffer))

        let vformat = vImageCVImageFormat_CreateWithCVPixelBuffer(pixelBuffer).takeRetainedValue()
        vImageCVImageFormat_SetColorSpace(vformat, CGColorSpaceCreateDeviceRGB())
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageByteOrderInfo.orderMask.rawValue | CGImageAlphaInfo.last.rawValue)
        
        var cgFormat = vImage_CGImageFormat(bitsPerComponent: 8,
                                            bitsPerPixel: 32,
                                            colorSpace: nil,
                                            bitmapInfo: bitmapInfo,
                                            version: 0,
                                            decode: nil,
                                            renderingIntent: .defaultIntent)

        
        let error = vImageBuffer_InitWithCVPixelBuffer(&buffer, &cgFormat, pixelBuffer, vformat, nil, vImage_Flags(kvImageNoFlags))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        guard error == kvImageNoError else {
            print("Error: Could not create vImageBuffer")
            free(buffer.data)
            return
        }
        

        // For temporary preview convert vImageBuffer to UIImage 
        // https://github.com/hollance/CoreMLHelpers/blob/master/CoreMLHelpers/CVPixelBuffer%2BHelpers.swift
        
        let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, ptr in
            if let ptr = ptr {
                free(UnsafeMutableRawPointer(mutating: ptr))
            }
        }
        
        var dstPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreateWithBytes(nil, Int(buffer.width), Int(buffer.height),
                                                  kCVPixelFormatType_32BGRA, buffer.data,
                                                  Int(buffer.rowBytes), releaseCallback,
                                                  nil, nil, &dstPixelBuffer)

        
        guard status == kCVReturnSuccess else {
            print("Error: could not create new pixel buffer")
            free(buffer.data)
            return
        }
            
        // Convert vImage to UIImage
        let destCGImage = vImageCreateCGImageFromBuffer(&buffer, &cgFormat, nil, nil, numericCast(kvImageNoFlags), nil)?.takeRetainedValue()
        
        // create a UIImage
        let exportedImage = destCGImage.flatMap { UIImage(cgImage: $0, scale: 0.0, orientation: UIImageOrientation.right) }
        
        DispatchQueue.main.async {
            self.previewImageView.image = exportedImage
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didDrop sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        print("Frame did drop")
    }
}
