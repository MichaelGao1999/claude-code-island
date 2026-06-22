import Foundation
import CryptoKit

/// HMAC 签名器
/// 使用 CryptoKit 实现事件签名和验证
/// 确保 WebSocket 通信的安全性
final class HMACSigner {
    
    // MARK: - Properties
    
    private let key: SymmetricKey
    
    // MARK: - Initialization
    
    /// 使用预定义密钥初始化
    init(key: SymmetricKey) {
        self.key = key
    }
    
    /// 使用随机密钥初始化
    init() {
        self.key = SymmetricKey(size: .bits256)
    }
    
    /// 使用字符串密钥初始化
    init(keyString: String) {
        let keyData = keyString.data(using: .utf8) ?? Data()
        self.key = SymmetricKey(data: keyData)
    }
    
    // MARK: - Public Methods
    
    /// 签名事件
    /// - Parameter event: 要签名的事件
    /// - Returns: 签名后的 JSON 字符串
    func sign(event: ClaudeEvent) -> String? {
        guard let eventData = try? JSONEncoder().encode(event) else {
            return nil
        }
        
        // 生成 HMAC 签名
        let signature = HMAC<SHA256>.authenticationCode(for: eventData, using: key)
        let signatureData = Data(signature)
        let signatureString = signatureData.base64EncodedString()
        
        // 构建签名后的消息
        let signedMessage: [String: Any] = [
            "event": event,
            "signature": signatureString,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: signedMessage),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    /// 验证签名
    /// - Parameter signedMessage: 签名后的消息
    /// - Returns: 验证成功返回原始事件，失败返回 nil
    func verify(signedMessage: String) -> ClaudeEvent? {
        guard let jsonData = signedMessage.data(using: .utf8),
              let messageDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let eventDict = messageDict["event"],
              let signatureString = messageDict["signature"] as? String else {
            return nil
        }
        
        // 解码事件
        guard let eventData = try? JSONSerialization.data(withJSONObject: eventDict),
              let event = try? JSONDecoder().decode(ClaudeEvent.self, from: eventData) else {
            return nil
        }
        
        // 验证签名
        guard let signatureData = Data(base64Encoded: signatureString) else {
            return nil
        }
        
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: eventData, using: key)
        let expectedData = Data(expectedSignature)
        
        if signatureData == expectedData {
            return event
        } else {
            return nil
        }
    }
    
    /// 签名审批响应
    /// - Parameters:
    ///   - eventId: 审批事件 ID
    ///   - approved: 是否批准
    /// - Returns: 签名后的响应 JSON
    func signApprovalResponse(eventId: String, approved: Bool) -> String? {
        let response: [String: Any] = [
            "type": approved ? "APPROVED" : "REJECTED",
            "eventId": eventId,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let responseData = try? JSONSerialization.data(withJSONObject: response) else {
            return nil
        }
        
        // 生成签名
        let signature = HMAC<SHA256>.authenticationCode(for: responseData, using: key)
        let signatureString = Data(signature).base64EncodedString()
        
        // 构建签名后的响应
        let signedResponse: [String: Any] = [
            "response": response,
            "signature": signatureString
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: signedResponse),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        return jsonString
    }
    
    /// 验证审批响应签名
    /// - Parameter signedResponse: 签名后的响应
    /// - Returns: 验证成功返回响应字典，失败返回 nil
    func verifyApprovalResponse(signedResponse: String) -> [String: Any]? {
        guard let jsonData = signedResponse.data(using: .utf8),
              let responseDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let response = responseDict["response"] as? [String: Any],
              let signatureString = responseDict["signature"] as? String else {
            return nil
        }
        
        // 验证签名
        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let signatureData = Data(base64Encoded: signatureString) else {
            return nil
        }
        
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: responseData, using: key)
        let expectedData = Data(expectedSignature)
        
        if signatureData == expectedData {
            return response
        } else {
            return nil
        }
    }
    
    // MARK: - Key Management
    
    /// 导出密钥（用于共享给 iOS App）
    func exportKey() -> String {
        let keyData = key.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
        return keyData.base64EncodedString()
    }
    
    /// 从导出的字符串导入密钥
    static func importKey(keyString: String) -> HMACSigner? {
        guard let keyData = Data(base64Encoded: keyString) else {
            return nil
        }
        
        let key = SymmetricKey(data: keyData)
        return HMACSigner(key: key)
    }
    
    /// 生成新的密钥对
    static func generateKeyPair() -> (macOSKey: String, iOSKey: String) {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
        let keyString = keyData.base64EncodedString()
        
        return (macOSKey: keyString, iOSKey: keyString)
    }
}

// MARK: - Usage Example

/// 使用示例
func exampleHMACUsage() {
    // 生成密钥对
    let (macKey, iOSKey) = HMACSigner.generateKeyPair()
    
    print("macOS 密钥: \(macKey)")
    print("iOS 密钥: \(iOSKey)")
    
    // macOS 端签名
    let macSigner = HMACSigner.importKey(keyString: macKey)!
    let event = ClaudeEvent.sample(type: .approvalRequired)
    
    let signedMessage = macSigner.sign(event: event)
    print("签名消息: \(signedMessage ?? "nil")")
    
    // iOS 端验证
    let iOSSigner = HMACSigner.importKey(keyString: iOSKey)!
    let verifiedEvent = iOSSigner.verify(signedMessage: signedMessage ?? "")
    
    if verifiedEvent != nil {
        print("验证成功: \(verifiedEvent!.type.displayName)")
    } else {
        print("验证失败")
    }
    
    // 签名审批响应
    let signedResponse = iOSSigner.signApprovalResponse(eventId: "evt_abc123", approved: true)
    print("签名响应: \(signedResponse ?? "nil")")
    
    // macOS 验证响应
    let verifiedResponse = macSigner.verifyApprovalResponse(signedResponse: signedResponse ?? "")
    print("验证响应: \(verifiedResponse ?? [:])")
}

// MARK: - Integration with EventStreamManager

/// 扩展 EventStreamManager 以支持签名验证
extension EventStreamManager {
    
    /// 使用签名验证接收消息
    func handleSignedMessage(_ signedMessage: String, signer: HMACSigner) {
        guard let event = signer.verify(signedMessage: signedMessage) else {
            print("签名验证失败，丢弃消息")
            return
        }
        
        handleEvent(event)
    }
    
    /// 发送签名审批响应
    func sendSignedApprovalResponse(eventId: String, approved: Bool, signer: HMACSigner) {
        guard let signedResponse = signer.signApprovalResponse(eventId: eventId, approved: approved) else {
            print("签名失败")
            return
        }
        
        webSocketTask?.send(.string(signedResponse), completionHandler: { error in
            if let error = error {
                print("发送签名响应失败: \(error.localizedDescription)")
            }
        })
    }
}

// MARK: - Integration with WebSocketBridge

/// 扩展 WebSocketBridge 以支持签名验证
extension WebSocketBridge {
    
    /// 使用签名验证接收消息
    func handleSignedMessage(_ signedMessage: String, signer: HMACSigner) {
        guard let event = signer.verify(signedMessage: signedMessage) else {
            print("签名验证失败，丢弃消息")
            return
        }
        
        handleEvent(event)
    }
    
    /// 发送签名审批响应
    func sendSignedApprovalResponse(eventId: String, approved: Bool, signer: HMACSigner) {
        guard let signedResponse = signer.signApprovalResponse(eventId: eventId, approved: approved) else {
            print("签名失败")
            return
        }
        
        webSocketTask?.send(.string(signedResponse), completionHandler: { error in
            if let error = error {
                print("发送签名响应失败: \(error.localizedDescription)")
            }
        })
    }
}