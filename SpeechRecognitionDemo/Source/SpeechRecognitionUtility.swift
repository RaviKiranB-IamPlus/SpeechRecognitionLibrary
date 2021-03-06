//
//  SpeechRecognitionUtility.swift
//  SpeechRecognitionDemo
//
//  Created by Jayesh Kawli on 3/17/17.
//  Copyright © 2017 Jayesh Kawli. All rights reserved.
//

import Foundation
import Speech

enum SpeechRecognitionOperationError: Error {
    case denied
    case notDetermined
    case restricted
    case audioSessionUnavailable
    case inputNodeUnavailable
    case invalidRecognitionRequest
    case audioEngineUnavailable
}

enum SpeechRecognitionOperationState {
    case authorized
    case audioEngineStart
    case audioEngineStop
    case recognitionTaskCancelled
    case speechRecognized(String)
    case speechNotRecognized
    case availabilityChanged(Bool)
    case speechRecognitionStopped(String)
}

enum RecordingState {
    case oneWordAtTime
    case continuous
}

@available(iOS 10.0, *)
class SpeechRecognitionUtility: NSObject, SFSpeechRecognizerDelegate {

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine: AVAudioEngine
    private let recognitionStateUpdateBlock: (SpeechRecognitionOperationState) -> Void
    private var speechRecognitionPermissionState: SFSpeechRecognizerAuthorizationStatus
    private let speechRecognitionAuthorizedBlock: () -> Void
    private let recordingState: RecordingState
    private var recognizedText: String

    init(speechRecognitionAuthorizedBlock : @escaping () -> Void, stateUpdateBlock: @escaping (SpeechRecognitionOperationState) -> Void, recordingState: RecordingState = .oneWordAtTime) {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        audioEngine = AVAudioEngine()
        recognitionStateUpdateBlock = stateUpdateBlock
        speechRecognitionPermissionState = .notDetermined
        self.speechRecognitionAuthorizedBlock = speechRecognitionAuthorizedBlock
        self.recordingState = recordingState
        self.recognizedText = ""


        super.init()
        speechRecognizer?.delegate = self

        SFSpeechRecognizer.requestAuthorization { (status) in
            self.speechRecognitionPermissionState = status
            if status == .authorized {
                // Need to return it on Main queue since this block is returned on serial queue. Assuming user wants to do UI actions once request is authorized.
                OperationQueue.main.addOperation {
                    speechRecognitionAuthorizedBlock()
                }
            }
        }
    }

    func startSpeechRecognition() throws {
        switch self.speechRecognitionPermissionState {
        case .denied:
            throw SpeechRecognitionOperationError.denied
        case .notDetermined:
            throw SpeechRecognitionOperationError.notDetermined
        case .restricted:
            throw SpeechRecognitionOperationError.restricted
        case .authorized:
            print("User authorized app to access microphone and speech recognition")
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            recognitionRequest?.endAudio()
        } else {
            try self.runSpeechRecognition()
        }
    }

    func runSpeechRecognition() throws  {

        if recognitionTask != nil {
            recognitionTask?.cancel()
            self.updateSpeechRecognitionState(with: .recognitionTaskCancelled)
            recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(AVAudioSessionCategoryRecord)
            try audioSession.setMode(AVAudioSessionModeMeasurement)
            try audioSession.setActive(true, with: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechRecognitionOperationError.audioSessionUnavailable
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let inputNode = audioEngine.inputNode else {
            throw SpeechRecognitionOperationError.inputNodeUnavailable
        }

        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionOperationError.invalidRecognitionRequest
        }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest, resultHandler: { (result, error) in

            var isFinal = false

            if result != nil {
                if let recognizedSpeechString = result?.bestTranscription.formattedString {
                    self.recognizedText = recognizedSpeechString
                    self.updateSpeechRecognitionState(with: .speechRecognized(recognizedSpeechString))
                    isFinal = true
                } else {
                    self.recognizedText = ""
                    self.updateSpeechRecognitionState(with: .speechNotRecognized)
                }
            }

            if (error != nil || isFinal) && (self.recordingState == .oneWordAtTime) {
                self.stopAudioRecognition()
            }
        })

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, time) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        if let _ = try? audioEngine.start() {
            self.updateSpeechRecognitionState(with: .audioEngineStart)
        } else {
            throw SpeechRecognitionOperationError.audioEngineUnavailable
        }
    }

    func toggleSpeechRecognitionActivity() throws {
        if self.isSpeechRecognitionOn() == true {
            self.stopAudioRecognition()
        } else {
            try self.runSpeechRecognition()
        }
    }

    private func stopAudioRecognition() {
        if self.audioEngine.isRunning {
            self.audioEngine.stop()
            self.recognitionRequest?.endAudio()
            self.updateSpeechRecognitionState(with: .audioEngineStop)
            self.updateSpeechRecognitionState(with: .speechRecognitionStopped(recognizedText))
            self.audioEngine.inputNode?.removeTap(onBus: 0)
        }

        self.recognitionRequest = nil

        if self.recognitionTask != nil {
            self.recognitionTask?.cancel()            
            self.updateSpeechRecognitionState(with: .recognitionTaskCancelled)
            self.recognitionTask = nil
        }
    }

    private func updateSpeechRecognitionState(with state: SpeechRecognitionOperationState) {
        OperationQueue.main.addOperation {
            self.recognitionStateUpdateBlock(state)
        }
    }

    private func isSpeechRecognitionOn() -> Bool {
        return self.audioEngine.isRunning
    }

    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        self.updateSpeechRecognitionState(with: .availabilityChanged(available))
    }

    
}
