/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The view controller presenting the main view.
*/

import Cocoa

protocol Coordinator: AnyObject {
    func didSelectComponent(at index: Int)
    func didChangeAudioUnitType(to type: AudioUnitType)
}

extension MainViewController: Coordinator {
    func showError(with message: String) {
        NSAlert.showError(with: message)
    }
    
    func didChangeAudioUnitType(to type: AudioUnitType) {
        loadAudioUnits(ofType: type)
    }
    
    func didSelectComponent(at index: Int) {
        selectedIndex = index
        audioUnitManager.selectComponent(at: index) { result in
            switch result {
            case .success:
                self.loadViewController()
                
            case .failure(let error):
                print("Unable to select audio unit: \(error)")
            }
        }
    }
}

class MainViewController: NSSplitViewController {
    var selectedIndex = 0
    var audioUnitType = AudioUnitType.effect
    let audioUnitManager = AudioUnitManager()

    unowned var listViewController: ListViewController!
    unowned var componentViewController: ComponentViewController!

    override var splitViewItems: [NSSplitViewItem] {
        didSet {
            splitViewItems.forEach {
                switch $0.viewController {
                case let viewController as ListViewController:
                    listViewController = viewController
                    listViewController.coordinator = self
                    
                case let viewController as ComponentViewController:
                    componentViewController = viewController
                    
                default:
                    fatalError("Unsupported view controller type found")
                }
            }
        }
    }
    
    @IBAction func togglePlayback(_ sender: NSButton) {
        audioUnitManager.togglePlayback()
    }
    
    @IBAction func loadVST3(_ sender: NSButton) {
        NSLog("loadVST3")
        testVST3()
    }
    
    @IBAction func unloadVST3(_ sender: NSButton) {
        NSLog("unloadVST3")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.translatesAutoresizingMaskIntoConstraints = false
        loadAudioUnits(ofType: .effect)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        view.window?.delegate = self
    }
    
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        return super.validateUserInterfaceItem(item)
    }
    
    func loadAudioUnits(ofType type: AudioUnitType) {
        audioUnitType = type

        // Ensure audio playback is stopped before loading.
        audioUnitManager.stopPlayback()

        // Load audio units.
        audioUnitManager.loadAudioUnits(ofType: type) { [weak self] audioUnits in
            guard let self else {
                return
            }
            self.listViewController.audioUnitComponents = audioUnits
        }
    }
    
    @IBAction func toggleLoadInProcessOption(sender: NSMenuItem) {
        switch sender.state {
        case .on:
            sender.state = .off
            audioUnitManager.instantiationType = .outOfProcess
            
        default:
            sender.state = .on
            audioUnitManager.instantiationType = .inProcess
        }
    }

    func loadViewController() {
        audioUnitManager.loadAudioUnitViewController() { viewController in
            // Determine if the user selected the "No Effect" row
            let isNoEffect = self.audioUnitType == .effect && self.selectedIndex == 0
            let labelText = isNoEffect ? "Please select an audio unit" :
                                         "No user interface"
            self.componentViewController.presentUserInterface(viewController?.view,
                                                              labelText: labelText)
        }
    }
}

// MARK: - NSWindowDelegate
extension MainViewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        audioUnitManager.stopPlayback()
    }
}

// MARK: - Custom Views
class SplitView: NSSplitView {
    override var dividerThickness: CGFloat { return 0.5 }
}

class BarView: NSView {
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fill(dirtyRect)
    }
}

class ToggleToolbarItem: NSToolbarItem {
    override func validate() {
        if let control = self.view as? NSControl, let action = self.action,
            let validator = NSApp.target(forAction: action, to: self.target, from: self) as? NSUserInterfaceValidations {
            control.isHidden = validator.validateUserInterfaceItem(self)
        } else {
            super.validate()
        }
    }
}
