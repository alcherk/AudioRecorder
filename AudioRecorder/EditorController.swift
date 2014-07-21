//
//  EditorController.swift
//  AudioRecorder
//
//  Created by Harshad Dange on 20/07/2014.
//  Copyright (c) 2014 Laughing Buddha Software. All rights reserved.
//

import Cocoa
import AVFoundation
import CoreMedia

protocol EditorControllerDelegate {
    func editorControllerDidFinishExporting(editor: EditorController)
}

enum RecordingPreset: Int {
    case Low = 0
    case Medium
    case High

    func settings() -> Dictionary<String, Int> {
        switch self {
        case .Low:
            return [AVLinearPCMBitDepthKey: 16, AVNumberOfChannelsKey : 1, AVSampleRateKey : 12_000, AVLinearPCMIsBigEndianKey : 0, AVLinearPCMIsFloatKey : 0]

        case .Medium:
            return [AVLinearPCMBitDepthKey: 16, AVNumberOfChannelsKey : 1, AVSampleRateKey : 24_000, AVLinearPCMIsBigEndianKey : 0, AVLinearPCMIsFloatKey : 0]

        case .High:
            return [AVLinearPCMBitDepthKey: 16, AVNumberOfChannelsKey : 1, AVSampleRateKey : 48_000, AVLinearPCMIsBigEndianKey : 0, AVLinearPCMIsFloatKey : 0]
        }
    }

    func exportSettings() -> Dictionary <String, Int> {

        var recordingSetting = self.settings()
        recordingSetting[AVFormatIDKey] = kAudioFormatLinearPCM
        recordingSetting[AVLinearPCMIsNonInterleaved] = 0

        return recordingSetting
    }
}

class EditorController: NSWindowController, EditorViewDelegate {

    override func windowDidLoad() {
        super.windowDidLoad()

        refreshView()
        // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
        editorView.delegate = self
        startField.stringValue = NSTimeInterval(0).hhmmss()
        endField.stringValue = duration.hhmmss()
    }
    
    @IBOutlet var editorView : EditorView
    @IBOutlet var startField : NSTextField
    @IBOutlet var endField : NSTextField
    @IBOutlet var qualitySelector : NSMatrix
    
    var recordingURL: NSURL?
    var exportSession: AVAssetExportSession?
    var delegate: EditorControllerDelegate?
    var assetReadingQueue: dispatch_queue_t?
    var assetReader: AVAssetReader?
    var assetWriter: AVAssetWriter?
    
    var powerTrace: Float[]? {
    didSet {
        refreshView()
    }
    }
    
    var duration: NSTimeInterval = 0.0 {
    didSet {
        refreshView()
    }
    }
    @IBAction func clickSave(sender : NSButton) {
        
        if let assetURL = recordingURL {
            let selectedRange = editorView.selectedRange()
            let asset: AVAsset = AVAsset.assetWithURL(assetURL) as AVAsset
            let startTime = CMTimeMakeWithSeconds(selectedRange.start, 600)
            let duration = CMTimeMakeWithSeconds((selectedRange.end - selectedRange.start), 600)
            let timeRange = CMTimeRange(start: startTime, duration: duration)
            let exportPath = assetURL.path.stringByDeletingPathExtension + "-edited.wav"

            assetReader = AVAssetReader(asset: asset, error: nil)
            let assetTrack = asset.tracksWithMediaType(AVMediaTypeAudio).firstObject() as? AVAssetTrack
            let readerOutput = AVAssetReaderTrackOutput(track: assetTrack, outputSettings: nil)
            assetReader!.addOutput(readerOutput)
            assetReader!.timeRange = timeRange

            assetWriter = AVAssetWriter(URL: NSURL(fileURLWithPath: exportPath), fileType: AVFileTypeWAVE, error: nil)
            let selectedQuality = RecordingPreset.fromRaw(qualitySelector.selectedColumn)
            let writerInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: selectedQuality?.exportSettings())
            writerInput.expectsMediaDataInRealTime = false
            assetWriter!.addInput(writerInput)

            assetWriter!.startWriting()
            assetWriter!.startSessionAtSourceTime(kCMTimeZero)

            assetReader!.startReading()

            assetReadingQueue = dispatch_queue_create("com.lbs.audiorecorder.assetreadingqueue", DISPATCH_QUEUE_SERIAL)
            writerInput.requestMediaDataWhenReadyOnQueue(assetReadingQueue){
                while writerInput.readyForMoreMediaData {
                    var nextBuffer: CMSampleBufferRef? = readerOutput.copyNextSampleBuffer()
                    if (self.assetReader!.status == AVAssetReaderStatus.Reading) && (nextBuffer != nil) {
                        writerInput.appendSampleBuffer(nextBuffer)
                    } else {
                        writerInput.markAsFinished()

                        switch self.assetReader!.status {

                        case .Failed:
                            self.assetWriter!.cancelWriting()
                            println("Failed :(")

                        case .Completed:
                            println("Done!")
                            self.assetWriter!.endSessionAtSourceTime(duration)
                            self.assetWriter!.finishWriting()

                            dispatch_async(dispatch_get_main_queue()){
                                if let theDelegate = self.delegate {
                                    theDelegate.editorControllerDidFinishExporting(self)
                                }
                            }

                        default:
                            println("This should not happen :/")
                        }

                        break;
                    }
                }
            }
        }
    }
    
    func refreshView() -> () {
        if editorView != nil {
            editorView.duration = duration
            if let trace = powerTrace {
                editorView.audioLevels = trace
            }
        }
    }
    
    // MARK: EditorViewDelegate methods
    func timeRangeChanged(editor: EditorView, timeRange: (start: NSTimeInterval, end: NSTimeInterval))  {
        startField.stringValue = timeRange.start.hhmmss()
        endField.stringValue = timeRange.end.hhmmss()
    }
    
}
