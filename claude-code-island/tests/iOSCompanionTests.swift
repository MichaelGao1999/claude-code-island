import XCTest

/// iOS Companion App 单元测试
final class iOSCompanionTests: XCTestCase {
    
    // MARK: - WebSocketBridge Tests
    
    /// 测试 WebSocket Bridge 初始化
    func testWebSocketBridgeInitialization() {
        let bridge = WebSocketBridge()
        
        XCTAssertFalse(bridge.isConnected)
        XCTAssertNil(bridge.currentEvent)
        XCTAssertEqual(bridge.eventHistory.count, 0)
    }
    
    /// 测试 Mock 模式
    func testWebSocketBridgeMockMode() {
        let bridge = WebSocketBridge()
        
        bridge.enableMockMode()
        
        XCTAssertTrue(bridge.isConnected)
        XCTAssertNil(bridge.connectionError)
    }
    
    /// 测试连接断开
    func testWebSocketBridgeDisconnect() {
        let bridge = WebSocketBridge()
        
        bridge.enableMockMode()
        XCTAssertTrue(bridge.isConnected)
        
        bridge.disconnect()
        XCTAssertFalse(bridge.isConnected)
    }
    
    /// 测试事件接收
    func testWebSocketBridgeEventReception() {
        let bridge = WebSocketBridge()
        bridge.enableMockMode()
        
        let expectation = XCTestExpectation(description: "等待事件")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            XCTAssertNotNil(bridge.currentEvent)
            XCTAssertGreaterThan(bridge.eventHistory.count, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6)
    }
    
    /// 测试审批响应发送
    func testApprovalResponseSending() {
        let bridge = WebSocketBridge()
        bridge.enableMockMode()
        
        // 等待审批事件
        let expectation = XCTestExpectation(description: "等待审批事件")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if let event = bridge.currentEvent, event.type == .approvalRequired {
                let approvalInfo = ApprovalInfo(from: event)
                bridge.sendApprovalResponse(eventId: approvalInfo.eventId, approved: true)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10)
    }
    
    // MARK: - Live Activity Tests
    
    /// 测试 Live Activity Manager 单例
    func testLiveActivityManagerSingleton() {
        if #available(iOS 16.1, *) {
            let manager1 = LiveActivityManager.shared
            let manager2 = LiveActivityManager.shared
            
            XCTAssertEqual(manager1, manager2)
        }
    }
    
    /// 测试 Live Activity 启动
    func testLiveActivityStart() {
        if #available(iOS 16.1, *) {
            let manager = LiveActivityManager.shared
            
            manager.startActivity()
            
            XCTAssertTrue(manager.isActive)
        }
    }
    
    /// 测试 Live Activity 更新
    func testLiveActivityUpdate() {
        if #available(iOS 16.1, *) {
            let manager = LiveActivityManager.shared
            manager.startActivity()
            
            let event = ClaudeEvent.sample(type: .coding)
            manager.updateActivity(with: event)
            
            // Live Activity 应该更新
            XCTAssertTrue(manager.isActive)
        }
    }
    
    /// 测试 Live Activity 结束
    func testLiveActivityEnd() {
        if #available(iOS 16.1, *) {
            let manager = LiveActivityManager.shared
            manager.startActivity()
            
            manager.endActivity()
            
            XCTAssertFalse(manager.isActive)
        }
    }
    
    // MARK: - ApprovalInfo Tests
    
    /// 测试审批信息转换
    func testApprovalInfoConversion() {
        let event = ClaudeEvent.sample(type: .approvalRequired)
        let approvalInfo = ApprovalInfo(from: event)
        
        XCTAssertNotNil(approvalInfo.eventId)
        XCTAssertNotNil(approvalInfo.commandSummary)
        XCTAssertNotNil(approvalInfo.commandDetails)
        XCTAssertNotNil(approvalInfo.riskLevel)
        XCTAssertNotNil(approvalInfo.rawCommand)
    }
    
    /// 测试审批信息风险等级
    func testApprovalInfoRiskLevel() {
        let event = ClaudeEvent.sample(type: .approvalRequired)
        let approvalInfo = ApprovalInfo(from: event)
        
        // 样本事件应该是高风险
        XCTAssertEqual(approvalInfo.riskLevel, .high)
    }
    
    // MARK: - Event History Tests
    
    /// 测试事件历史限制
    func testEventHistoryLimit() {
        let bridge = WebSocketBridge()
        bridge.enableMockMode()
        
        // 添加大量事件
        for i in 0..<100 {
            let event = ClaudeEvent(type: .coding, taskDescription: "Task \(i)")
            bridge.eventHistory.append(event)
        }
        
        // 事件历史应该被限制
        XCTAssertLessThanOrEqual(bridge.eventHistory.count, 50)
    }
    
    // MARK: - ClaudeEvent Tests
    
    /// 测试事件类型枚举完整性
    func testEventTypeEnumCompleteness() {
        let allTypes = EventType.allCases
        
        // 应该有 9 种类型
        XCTAssertEqual(allTypes.count, 9)
        
        // 验证每种类型
        let expectedTypes: Set<EventType> = [
            .thinking, .coding, .waiting, .approvalRequired,
            .approved, .rejected, .error, .connected, .disconnected
        ]
        
        XCTAssertEqual(Set(allTypes), expectedTypes)
    }
    
    /// 测试事件编码解码
    func testEventCodableRoundtrip() {
        let originalEvent = ClaudeEvent.sample(type: .coding)
        
        guard let jsonData = try? JSONEncoder().encode(originalEvent) else {
            XCTFail("编码失败")
            return
        }
        
        guard let decodedEvent = try? JSONDecoder().decode(ClaudeEvent.self, from: jsonData) else {
            XCTFail("解码失败")
            return
        }
        
        XCTAssertEqual(originalEvent.id, decodedEvent.id)
        XCTAssertEqual(originalEvent.type, decodedEvent.type)
        XCTAssertEqual(originalEvent.payload.taskDescription, decodedEvent.payload.taskDescription)
    }
    
    // MARK: - Mock Mode Tests
    
    /// 测试 Mock 模式事件序列
    func testMockModeEventSequence() {
        let bridge = WebSocketBridge()
        bridge.enableMockMode()
        
        let expectation = XCTestExpectation(description: "等待完整事件序列")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            // 应该收到 thinking, coding, waiting, approvalRequired
            let types = bridge.eventHistory.map { $0.type }
            
            XCTAssertTrue(types.contains(.thinking))
            XCTAssertTrue(types.contains(.coding))
            XCTAssertTrue(types.contains(.waiting))
            XCTAssertTrue(types.contains(.approvalRequired))
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 12)
    }
    
    // MARK: - Performance Tests
    
    /// 测试事件解析性能
    func testEventParsingPerformance() {
        let event = ClaudeEvent.sample(type: .coding)
        guard let jsonData = try? JSONEncoder().encode(event) else {
            XCTFail("编码失败")
            return
        }
        
        measure {
            for _ in 0..<1000 {
                _ = try? JSONDecoder().decode(ClaudeEvent.self, from: jsonData)
            }
        }
    }
    
    /// 测试事件生成性能
    func testEventGenerationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = ClaudeEvent.sample(type: .coding)
            }
        }
    }
}