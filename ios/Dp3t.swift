import Foundation
import DP3TSDK

@objc(Dp3t)
class Dp3t: RCTEventEmitter, DP3TTracingDelegate {
    var observing: Bool = false

    override init() {
        super.init()
        
        DP3TTracing.preInitialize()
    }
    
    override func supportedEvents() -> [String]! {
      return ["Dp3tStatusUpdated"]
    }
    
    override func constantsToExport() -> [AnyHashable : Any]! {
      return [
        "errorStates": [],
        "Dp3tStatusUpdated": "Dp3tStatusUpdated"
      ]
    }
    
    override static func requiresMainQueueSetup() -> Bool {
      return true
    }
    
    override func startObserving() -> Void {
        observing = true
    }
    
    func DP3TTracingStateChanged(_ state: TracingState) {
        if (observing) {
            sendEvent(withName: "Dp3tStatusUpdated", body: toJSStatus(state))
        }
    }
    
    override func stopObserving() -> Void {
        observing = false
    }
    
    func toJSStatus(_ state: TracingState) -> [AnyHashable : Any]! {
        var errors: [String] = []
        var nativeErrors: [String] = []
        var nativeErrorArg: Any? = nil
        var tracingState = ""
        switch state.trackingState {
        case .active:
            tracingState = "started"
        case .stopped:
            tracingState = "stopped"
        case let .inactive(error):
            tracingState = "error"
            nativeErrors.append(error.localizedDescription)
            switch error {
            case .bluetoothTurnedOff:
                errors.append("bluetoothDisabled")
            case .permissonError:
                errors.append("permissionMissing")
            case .caseSynchronizationError(errors: let error):
                nativeErrorArg = error
                errors.append("sync")
            case .networkingError(error: let error):
                nativeErrorArg = error
                errors.append("sync")
            case .cryptographyError(error: let error):
                nativeErrorArg = error
                errors.append("other")
            case .databaseError(error: let error):
                nativeErrorArg = error
                errors.append("other")
            case .userAlreadyMarkedAsInfected:
                errors.append("other")
            case .coreBluetoothError(error: let error):
                nativeErrorArg = error
                errors.append("other")
            }
        }
        
        var healthStatus = ""
        var exposedDays: [[String : Any]] = []
        var nativeStatusArg: Int? = nil
        switch state.infectionStatus {
        case .healthy:
            healthStatus = "healthy"
        case .infected:
            healthStatus = "infected"
        case .exposed(days: let days):
            healthStatus = "exposed"
            exposedDays = days.map { contact in
                return [
                    "id": contact.identifier,
                    "exposedDate": (contact.exposedDate.timeIntervalSince1970 * 1000).description,
                    "reportDate": (contact.reportDate.timeIntervalSince1970 * 1000).description
                ]
            }
            nativeStatusArg = days.count
        }
        
        var res = [
            "tracingState": tracingState,
            "numberOfHandshakes": state.numberOfHandshakes,
            "numberOfContacts": state.numberOfContacts,
            "healthStatus": healthStatus,
            "errors": errors,
            "nativeErrors": nativeErrors,
            "exposedDays": exposedDays
        ] as [String : Any]
        if (state.lastSync != nil) {
            res["lastSyncDate"] = (state.lastSync!.timeIntervalSince1970 * 1000).description
        }
        if (nativeErrorArg != nil) {
            res["nativeErrorArg"] = nativeErrorArg
        }
        if (nativeStatusArg != nil) {
            res["nativeStatusArg"] = nativeStatusArg
        }
        
        return res
    }
    
    @objc
    func isInitialized(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        resolve(DP3TTracing.isInitialized)
    }
    
    @objc
    func initWithDiscovery(_ backendAppId: String, publicKeyBase64: String, dev: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.main.async {
            do {
                try DP3TTracing.initialize(with: .discovery(backendAppId, enviroment: dev ? .dev : .prod))
                DP3TTracing.delegate = self
                resolve(nil)
            } catch {
                reject("DP3TError", "DP3TError in initWithDiscovery", error)
            }
        }
    }

    @objc
    func initManually(_ backendAppId: String, reportBaseUrl: String, bucketBaseUrl: String, publicKeyBase64: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
        DispatchQueue.main.async {
            do {
                let reportUrl = URL(string: reportBaseUrl)!
                let bucketUrl = URL(string: bucketBaseUrl)!
                try DP3TTracing.initialize(with: .manual(.init(appId: backendAppId, bucketBaseUrl: bucketUrl, reportBaseUrl: reportUrl, jwtPublicKey: Data(base64Encoded: publicKeyBase64))))
                DP3TTracing.delegate = self
                resolve(nil)
            } catch {
                reject("DP3TError", "DP3TError in initManually", error)
            }
        }
    }

    @objc
    func start(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard DP3TTracing.isInitialized else {
            reject("DP3TNotInitialized", "DP3T was not initialized.", nil)
            return
        }
        
        do {
            try DP3TTracing.startTracing()
            resolve(nil)
        } catch {
            reject("DP3TError", "DP3TError in start", error)
        }
    }

    @objc
    func stop(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard DP3TTracing.isInitialized else {
            reject("DP3TNotInitialized", "DP3T was not initialized.", nil)
            return
        }
        
        DP3TTracing.stopTracing()
        resolve(nil)
    }
    
    @objc
    func currentTracingStatus(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard DP3TTracing.isInitialized else {
            reject("DP3TNotInitialized", "DP3T was not initialized.", nil)
            return
        }
        
        DP3TTracing.status { result in
            switch result {
            case let .success(state):
                resolve(toJSStatus(state))
            case let .failure(error):
                reject("DP3TError", "Failed to get currentTracingStatus", error)
            }
        }
    }
    
    @objc
    func sendIAmInfected(_ onset: Date, auth: Dictionary<String, String>, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        guard DP3TTracing.isInitialized else {
            reject("DP3TNotInitialized", "DP3T was not initialized.", nil)
            return
        }
        
        let authentication = auth["authorization"] != nil
            ? ExposeeAuthMethod.HTTPAuthorizationBearer(token: auth["authorization"]!)
            : auth["json"] != nil
            ? ExposeeAuthMethod.JSONPayload(token: auth["json"]!)
            : nil
        
        guard authentication != nil else {
            reject("DP3TError", "Bad auth type", nil)
            return
        }
        
        DP3TTracing.iWasExposed(onset: onset, authentication: authentication!) { result in
            switch result {
            case .success:
                resolve(nil)
            case let .failure(error):
                reject("DP3TError", "Failed to sendIWasExposed", error)
            }
        }
    }
    
    @objc
    func sync(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DP3TTracing.sync { result in
            switch result {
            case .success:
                resolve(true)
            case let .failure(error):
                print(error)
                reject("DP3TError", "Failed to sync", error)
            }
        }
    }
    
    @objc
    func clearData(_ resolve: RCTPromiseResolveBlock, reject: RCTPromiseRejectBlock) {
        guard DP3TTracing.isInitialized else {
            reject("DP3TNotInitialized", "DP3T was not initialized.", nil)
            return
        }
        
        do {
            try DP3TTracing.reset()
            resolve(nil)
        } catch {
            reject("DP3TError", "DP3TError in clearData", error)
        }
    }
}
