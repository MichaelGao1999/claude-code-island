import XCTest

/// macOS Island App 单元测试
final class IslandAppTests: XCTestCase {
    
    // MARK: - ClaudeEvent Tests
    
    /// 测试事件初始化
    func testEventInitialization() {
        let event = ClaudeEvent(
            type: .thinking,
            taskDescription: "分析代码结构",
            message: "正在思考..."
        )
        
        XCTAssertEqual(event.type, .thinking)
        XCTAssertNotNil(event.payload.taskDescription)
        XCTAssertNotNil(event.payload.message)
        XCTAssertNotNil(event.id)
    }
    
    /// 测试事件编码解码
    func testEventCodable() {
        let event = ClaudeEvent.sample(type: .coding)
        
        // 编码
        guard let jsonData = try? JSONEncoder().encode(event) else {
            XCTFail("编码失败")
            return
        }
        
        // 解码
        guard let decodedEvent = try? JSONDecoder().decode(ClaudeEvent.self, from: jsonData) else {
            XCTFail("解码失败")
            return
        }
        
        XCTAssertEqual(event.id, decodedEvent.id)
        XCTAssertEqual(event.type, decodedEvent.type)
    }
    
    /// 测试事件类型枚举
    func testEventTypeEnum() {
        let allTypes = EventType.allCases
        
        XCTAssertEqual(allTypes.count, 9)
        XCTAssertTrue(allTypes.contains(.thinking))
        XCTAssertTrue(allTypes.contains(.coding))
        XCTAssertTrue(allTypes.contains(.approvalRequired))
    }
    
    /// 测试风险等级枚举
    func testRiskLevelEnum() {
        let allLevels = RiskLevel.allCases
        
        XCTAssertEqual(allLevels.count, 4)
        XCTAssertTrue(allLevels.contains(.low))
        XCTAssertTrue(allLevels.contains(.medium))
        XCTAssertTrue(allLevels.contains(.high))
        XCTAssertTrue(allLevels.contains(.critical))
    }
    
    /// 测试风险等级颜色映射
    func testRiskLevelColor() {
        XCTAssertEqual(RiskLevel.low.color, "green")
        XCTAssertEqual(RiskLevel.medium.color, "orange")
        XCTAssertEqual(RiskLevel.high.color, "red")
        XCTAssertEqual(RiskLevel.critical.color, "purple")
    }
    
    /// 测试事件类型显示名称
    func testEventTypeDisplayName() {
        XCTAssertEqual(EventType.thinking.displayName, "思考中")
        XCTAssertEqual(EventType.coding.displayName, "编码中")
        XCTAssertEqual(EventType.approvalRequired.displayName, "需要审批")
    }
    
    /// 测试风险等级显示名称
    func testRiskLevelDisplayName() {
        XCTAssertEqual(RiskLevel.low.displayName, "低风险")
        XCTAssertEqual(RiskLevel.medium.displayName, "中风险")
        XCTAssertEqual(RiskLevel.high.displayName, "高风险")
        XCTAssertEqual(RiskLevel.critical.displayName, "严重风险")
    }
    
    // MARK: - ApprovalInfo Tests
    
    /// 测试审批信息初始化
    func testApprovalInfoInitialization() {
        let event = ClaudeEvent.sample(type: .approvalRequired)
        let approvalInfo = ApprovalInfo(from: event)
        
        XCTAssertNotNil(approvalInfo.eventId)
        XCTAssertNotNil(approvalInfo.commandSummary)
        XCTAssertNotNil(approvalInfo.riskLevel)
    }
    
    // MARK: - EventStreamManager Tests
    
    /// 测试 Mock 模式
    func testMockMode() {
        let manager = EventStreamManager()
        
        manager.enableMockMode()
        
        XCTAssertTrue(manager.isConnected)
        XCTAssertNil(manager.connectionError)
    }
    
    /// 测试连接状态
    func testConnectionState() {
        let manager = EventStreamManager()
        
        XCTAssertFalse(manager.isConnected)
        
        manager.enableMockMode()
        
        XCTAssertTrue(manager.isConnected)
        
        manager.disconnect()
        
        XCTAssertFalse(manager.isConnected)
    }
    
    /// 测试事件历史
    func testEventHistory() {
        let manager = EventStreamManager()
        manager.enableMockMode()
        
        // 等待事件生成
        let expectation = XCTestExpectation(description: "等待事件")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            XCTAssertGreaterThan(manager.eventHistory.count, 0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 6)
    }
    
    // MARK: - Sample Data Tests
    
    /// 测试样本事件生成
    func testSampleEventGeneration() {
        let thinkingEvent = ClaudeEvent.sample(type: .thinking)
        XCTAssertEqual(thinkingEvent.type, .thinking)
        
        let codingEvent = ClaudeEvent.sample(type: .coding)
        XCTAssertEqual(codingEvent.type, .coding)
        XCTAssertNotNil(codingEvent.payload.progress)
        
        let approvalEvent = ClaudeEvent.sample(type: .approvalRequired)
        XCTAssertEqual(approvalEvent.type, .approvalRequired)
        XCTAssertNotNil(approvalEvent.payload.riskLevel)
    }
    
    /// 测试审批样本事件
    func testSampleApprovalEvent() {
        let event = ClaudeEvent.sampleApprovalEvent
        
        XCTAssertEqual(event.type, .approvalRequired)
        XCTAssertNotNil(event.payload.commandSummary)
        XCTAssertNotNil(event.payload.riskLevel)
    }
}