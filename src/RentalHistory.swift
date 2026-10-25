import Foundation

struct RentalReceipt: Decodable {
    let orderId: String
    let timestamp: String
    let status: String
    let region: String
    let gpuModel: String
    let gpuCount: String
    let billingMode: String
    let imageType: String
    let imageName: String
    let configPrice: Double
    let hostLabel: String
    let instanceId: String?
    let message: String

    var statusTitle: String {
        switch status {
        case "confirmed": return "租用成功"
        case "submitted": return "订单已提交"
        case "failed": return "创建失败"
        default: return "结果待确认"
        }
    }

    var priceUnit: String {
        ["按量计费": "元/小时", "包日": "元/天", "包周": "元/周", "包月": "元/月"][billingMode] ?? "元"
    }

    var displayTime: String {
        guard let date = ISO8601DateFormatter().date(from: timestamp) else { return timestamp }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum RentalHistory {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoDLMonitor", isDirectory: true)
            .appendingPathComponent("rental-history.jsonl")
    }

    static func decode(_ data: Data) -> RentalReceipt? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(RentalReceipt.self, from: data)
    }

    static func read(from url: URL = fileURL) throws -> [RentalReceipt] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        var latest: [String: RentalReceipt] = [:]
        for line in data.split(separator: 10) {
            if let receipt = decode(Data(line)) {
                latest[receipt.orderId] = receipt
            }
        }
        return latest.values.sorted { $0.timestamp > $1.timestamp }
    }
}
