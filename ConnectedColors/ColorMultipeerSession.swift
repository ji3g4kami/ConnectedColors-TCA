import ComposableArchitecture
import Combine
import MultipeerConnectivity
import os

enum NamedColor: String, CaseIterable, Equatable {
    case red, green, yellow
}

class ColorMultipeerSession: NSObject, ObservableObject {
    private let serviceType = "example-color"

    private let session: MCSession
    private let myPeerId = MCPeerID(displayName: UIDevice.current.name)
    private let serviceAdvertiser: MCNearbyServiceAdvertiser
    private let serviceBrowser: MCNearbyServiceBrowser
    private let log = Logger()

    @Published var currentColor: NamedColor? = nil
    @Published var connectedPeers: [MCPeerID] = []

    override init() {
        precondition(Thread.isMainThread)
        self.session = MCSession(peer: myPeerId)
        self.serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
        self.serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)

        super.init()

        session.delegate = self
        serviceAdvertiser.delegate = self
        serviceBrowser.delegate = self

        serviceAdvertiser.startAdvertisingPeer()
        serviceBrowser.startBrowsingForPeers()
    }

    deinit {
        self.serviceAdvertiser.stopAdvertisingPeer()
        self.serviceBrowser.stopBrowsingForPeers()
    }

    func send(color: NamedColor) {
        precondition(Thread.isMainThread)
        log.info("sendColor: \(String(describing: color)) to \(self.session.connectedPeers.count) peers")
        self.currentColor = color

        if !session.connectedPeers.isEmpty {
            do {
                try session.send(color.rawValue.data(using: .utf8)!, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                log.error("Error for sending: \(String(describing: error))")
            }
        }
    }
}

extension ColorMultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        precondition(Thread.isMainThread)
        log.error("ServiceAdvertiser didNotStartAdvertisingPeer: \(String(describing: error))")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        precondition(Thread.isMainThread)
        log.info("didReceiveInvitationFromPeer \(peerID)")
        invitationHandler(true, session)
    }
}

extension ColorMultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        log.error("ServiceBrowser didNotStartBrowsingForPeers: \(String(describing: error))")
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        log.info("ServiceBrowser found peer: \(peerID)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        log.info("ServiceBrowser lost peer: \(peerID)")
    }
}

extension ColorMultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        log.info("peer \(peerID) didChangeState: \(state.debugDescription)")
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let string = String(data: data, encoding: .utf8), let color = NamedColor(rawValue: string) {
            log.info("didReceive color \(string)")
            DispatchQueue.main.async {
                self.currentColor = color
            }
        } else {
            log.info("didReceive invalid value \(data.count) bytes")
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        log.error("Receiving streams is not supported")
    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        log.error("Receiving resources is not supported")
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        log.error("Receiving resources is not supported")
    }
}

extension MCSessionState: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .notConnected:
            return "notConnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        @unknown default:
            return "\(rawValue)"
        }
    }
}


// MARK: For TCA


struct PeerClient {
    enum Action: Equatable {
        case updatePeers([String])
        case updateColor(NamedColor)
    }
    
    var create: (UUID) -> Effect<Action, Never>
    var send: (UUID, NamedColor) -> Effect<Never, Never>
}

private var dependencies: [UUID: Dependencies] = [:]

extension PeerClient {
    static var live = PeerClient { id in
        Effect.run { subscriber in
            let serviceType = "example-color"
            let myPeerId = MCPeerID(displayName: UIDevice.current.name)
            let session = MCSession(peer: myPeerId)
            let serviceAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: serviceType)
            let serviceBrowser = MCNearbyServiceBrowser(peer: myPeerId, serviceType: serviceType)

            let delegate = Delegate(session, subscriber)

            session.delegate = delegate
            serviceAdvertiser.delegate = delegate
            serviceBrowser.delegate = delegate

            serviceAdvertiser.startAdvertisingPeer()
            serviceBrowser.startBrowsingForPeers()
            
            dependencies[id] = Dependencies(session: session, myPeerId: myPeerId, serviceAdvertiser: serviceAdvertiser, serviceBrowser: serviceBrowser, delegate: delegate, subscriber: subscriber)

            return AnyCancellable {
                dependencies[id]?.serviceAdvertiser.delegate = nil
                dependencies[id]?.serviceBrowser.delegate = nil
                dependencies[id]?.session.delegate = nil
                dependencies[id] = nil
            }
        }
    } send: { id, color in
        return .fireAndForget {
            guard let session = dependencies[id]?.session else {
                return
            }
            try? session.send(color.rawValue.data(using: .utf8)!, toPeers: session.connectedPeers, with: .reliable)
        }
        
    }

    static var preview = PeerClient { id in
            .run { sbuscriber in
                return AnyCancellable {
                    
                }
            }
    } send: { id, color in
            .fireAndForget {
                print("do nothing")
            }
    }


}

private struct Dependencies {
    let session: MCSession
    let myPeerId: MCPeerID
    let serviceAdvertiser: MCNearbyServiceAdvertiser
    let serviceBrowser: MCNearbyServiceBrowser
    let delegate: Delegate
    let subscriber: Effect<PeerClient.Action, Never>.Subscriber
}

private class Delegate: NSObject, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        precondition(Thread.isMainThread)
        print("ServiceAdvertiser didNotStartAdvertisingPeer: \(String(describing: error))")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        precondition(Thread.isMainThread)
        print("didReceiveInvitationFromPeer \(peerID)")
        invitationHandler(true, session)
    }
    
    let session: MCSession
    let subscriber: Effect<PeerClient.Action, Never>.Subscriber
    
    init(_ session: MCSession, _ subscriber: Effect<PeerClient.Action, Never>.Subscriber) {
        self.session = session
        self.subscriber = subscriber
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("ServiceBrowser didNotStartBrowsingForPeers: \(String(describing: error))")
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("ServiceBrowser found peer: \(peerID)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("ServiceBrowser lost peer: \(peerID)")
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("peer \(peerID) didChangeState: \(state.debugDescription)")
        DispatchQueue.main.async {
            self.subscriber.send(.updatePeers(session.connectedPeers.map(
                \.displayName)))
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let string = String(data: data, encoding: .utf8), let color = NamedColor(rawValue: string) {
            print("didReceive color \(string)")
            DispatchQueue.main.async {
                self.subscriber.send(.updateColor(color))
            }
        } else {
            print("didReceive invalid value \(data.count) bytes")
        }
    }

    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Receiving streams is not supported")
    }

    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        print("Receiving resources is not supported")
    }

    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        print("Receiving resources is not supported")
    }
}
