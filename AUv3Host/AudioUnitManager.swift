/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The manager object used to find and instantiate audio units and manage their presets and view configurations.
*/

import Foundation
import CoreAudioKit
import AVFoundation
import AppKit

public typealias ViewController = NSViewController

enum AudioUnitType: Int {
    case effect
    case instrument
}

enum InstantiationType: Int {
    case inProcess
    case outOfProcess
}

extension Notification.Name {
    static let userPresetsChanged = Notification.Name("userPresetsChanged")
}

public struct Component {
    private let audioUnitType: AudioUnitType
    fileprivate let avAudioUnitComponent: AVAudioUnitComponent?

    fileprivate init(_ component: AVAudioUnitComponent?, type: AudioUnitType) {
        audioUnitType = type
        avAudioUnitComponent = component
    }

    public var name: String {
        guard let component = avAudioUnitComponent else {
            return audioUnitType == .effect ? "(No Effect)" : "(No Instrument)"
        }
        return "\(component.name) (\(component.manufacturerName))"
    }

    public var hasCustomView: Bool {
        avAudioUnitComponent?.hasCustomView ?? false
    }
}

class AudioUnitManager {
    var filterClosure: (AVAudioUnitComponent) -> Bool = {
        let filterlist = ["AUNewPitch", "AURoundTripAAC", "AUNetSend"]
        var allowed = !filterlist.contains($0.name)
        if allowed && $0.typeName == AVAudioUnitTypeEffect {
            allowed = $0.hasCustomView
        }
        return allowed
    }
    
    var observer: NSKeyValueObservation?

    private var audioUnit: AUAudioUnit? {
        didSet {
            observer = nil
        }
    }

    private let componentsAccessQueue = DispatchQueue(label: "com.example.apple-samplecode.ComponentsAccessQueue")

    private var _components = [Component]()

    private var components: [Component] {
        get {
            var array = [Component]()
            componentsAccessQueue.sync {
                array = _components
            }
            return array
        }
        set {
            componentsAccessQueue.sync {
                _components = newValue
            }
        }
    }

    /// The playback engine used to play audio.
    private let playEngine = SimplePlayEngine()

    private var options = AudioComponentInstantiationOptions.loadOutOfProcess

    /// Determines how the audio unit is instantiated.
    @available(iOS, unavailable)
    var instantiationType = InstantiationType.outOfProcess {
        didSet {
            options = instantiationType == .inProcess ? .loadInProcess : .loadOutOfProcess
        }
    }

    var preferredWidth: CGFloat {
        viewConfigurations[currentViewConfigurationIndex].width
    }

    private var currentViewConfigurationIndex = 0

    private var viewConfigurations: [AUAudioUnitViewConfiguration] = {
        let compact = AUAudioUnitViewConfiguration(width: 400, height: 100, hostHasController: false)
        return [compact]
    }()

    var providesUserInterface: Bool {
        audioUnit?.providesUserInterface ?? false
    }

    func loadAudioUnits(ofType type: AudioUnitType, completion: @escaping ([Component]) -> Void) {
        playEngine.reset()

        DispatchQueue.global(qos: .default).async {
            let componentType = type == .effect ? kAudioUnitType_Effect : kAudioUnitType_MusicDevice
            let description = AudioComponentDescription(componentType: componentType,
                                                        componentSubType: 0,
                                                        componentManufacturer: 0,
                                                        componentFlags: 0,
                                                        componentFlagsMask: 0)
            // リストアップ
            let components = AVAudioUnitComponentManager.shared().components(matching: description)

            var wrapped = components.filter(self.filterClosure).map { Component($0, type: type) }

            // Insert a "No Effect" element into array if effect
            if type == .effect {
                wrapped.insert(Component(nil, type: type), at: 0)
            }
            
            self.components = wrapped
            
            // Notify the caller of the loaded components.
            DispatchQueue.main.async {
                completion(wrapped)
            }
        }
    }

    // MARK: Instantiate an Audio Unit

    func selectComponent(at index: Int, completion: @escaping (Result<Bool, Error>) -> Void) {
        // nil out existing component
        audioUnit = nil

        // Get the wrapped AVAudioUnitComponent
        guard let component = components[index].avAudioUnitComponent else {
            // Reset the engine to remove any configured audio units.
            playEngine.reset()
            // Return success, but indicate an audio unit was not selected.
            // This occurrs when the user selects the (No Effect) row.
            completion(.success(false))
            return
        }

        let description = component.audioComponentDescription

        // Instantiate the audio unit and connect it the the play engine.
        AVAudioUnit.instantiate(with: description, options: options) { avAudioUnit, error in
            guard error == nil else {
                DispatchQueue.main.async {
                    completion(.failure(error!))
                }
                return
            }
            self.audioUnit = avAudioUnit?.auAudioUnit
            self.playEngine.connect(avAudioUnit: avAudioUnit) {
                DispatchQueue.main.async {
                    completion(.success(true))
                }
            }
        }
    }

    func loadAudioUnitViewController(completion: @escaping (ViewController?) -> Void) {
        if let audioUnit = audioUnit {
            audioUnit.requestViewController { viewController in
                DispatchQueue.main.async {
                    completion(viewController)
                }
            }
        } else {
            completion(nil)
        }
    }

    // MARK: Audio Transport

    @discardableResult
    func togglePlayback() -> Bool {
        return playEngine.togglePlay()
    }

    func stopPlayback() {
        playEngine.stopPlaying()
    }
}
