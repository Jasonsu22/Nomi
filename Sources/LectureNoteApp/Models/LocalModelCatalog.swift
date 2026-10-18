import Foundation

enum LocalModelRole: String, Codable, CaseIterable, Sendable, Identifiable {
    case asr, translator

    var id: String { rawValue }
    var title: String { self == .asr ? tr("语音识别模型") : tr("翻译模型") }
    var modelType: String { self == .asr ? "qwen3_asr" : "qwen3_5" }
    var preferenceKey: String { "nomi.model.\(rawValue)" }
    var defaultID: String { self == .asr ? "qwen3-asr-1.7b" : "Qwen3.5-2B-MLX-4bit" }
}

struct LocalModelDefinition: Identifiable, Sendable {
    var id: String
    var role: LocalModelRole
    var name: String
    var repository: String
    var revision: String
    var bytes: Int64
    var quantization: String

    var directory: URL { Self.root.appendingPathComponent(id, isDirectory: true) }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".OminiX/models", isDirectory: true)
    }

    static let catalog: [Self] = [
        .init(id: "qwen3-asr-0.6b", role: .asr, name: "Qwen3-ASR 0.6B", repository: "mlx-community/Qwen3-ASR-0.6B-8bit", revision: "89e96d92ba34aca20b3e29fb10cc284097d1219f", bytes: 1_010_773_761, quantization: "8-bit MLX"),
        .init(id: "qwen3-asr-1.7b", role: .asr, name: "Qwen3-ASR 1.7B", repository: "mlx-community/Qwen3-ASR-1.7B-8bit", revision: "a8379a2e2f9e313c9292cdf1af4055ab56d50d55", bytes: 2_467_859_030, quantization: "8-bit MLX"),
        .init(id: "Qwen3.5-0.8B-MLX-4bit", role: .translator, name: "Qwen3.5 0.8B", repository: "mlx-community/Qwen3.5-0.8B-MLX-4bit", revision: "5d894f8cc4ef3e6c88537bf3746ed262f549da6a", bytes: 652_031_020, quantization: "4-bit MLX"),
        .init(id: "Qwen3.5-2B-MLX-4bit", role: .translator, name: "Qwen3.5 2B", repository: "mlx-community/Qwen3.5-2B-MLX-4bit", revision: "93760be4f1f69842a46bc13dbdc0f19e291392a3", bytes: 1_749_083_534, quantization: "4-bit MLX"),
        .init(id: "Qwen3.5-4B-MLX-4bit", role: .translator, name: "Qwen3.5 4B", repository: "mlx-community/Qwen3.5-4B-MLX-4bit", revision: "32f3e8ecf65426fc3306969496342d504bfa13f3", bytes: 3_061_132_920, quantization: "4-bit MLX"),
    ]

    static func selected(for role: LocalModelRole) -> Self {
        let id = UserDefaults.standard.string(forKey: role.preferenceKey) ?? role.defaultID
        return catalog.first { $0.role == role && $0.id == id }
            ?? catalog.first { $0.id == role.defaultID }!
    }
}

struct LocalModelRuntimeStatus: Decodable {
    struct Model: Decodable {
        var path: String
        var files: String
        var loaded: Bool
        var error: String?
    }
    var asr: Model
    var translator: Model

    func model(for role: LocalModelRole) -> Model { role == .asr ? asr : translator }
}

enum LocalModelFiles {
    static func isComplete(_ model: LocalModelDefinition, at directory: URL? = nil) -> Bool {
        let directory = directory ?? model.directory
        func nonempty(_ name: String) -> Bool {
            guard !name.contains("/"), !name.contains("\\"),
                  let values = try? directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }
        guard nonempty("config.json"), nonempty("tokenizer_config.json"),
              let data = try? Data(contentsOf: directory.appendingPathComponent("config.json")),
              let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              config["model_type"] as? String == model.role.modelType else { return false }
        let tokenizer = nonempty("tokenizer.json") || (model.role == .asr && nonempty("vocab.json") && nonempty("merges.txt"))
        guard tokenizer else { return false }
        let index = directory.appendingPathComponent("model.safetensors.index.json")
        if FileManager.default.fileExists(atPath: index.path) {
            guard let data = try? Data(contentsOf: index),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let weights = object["weight_map"] as? [String: String], !weights.isEmpty,
                  Set(weights.values).allSatisfy(nonempty) else { return false }
        } else if !nonempty("model.safetensors") { return false }
        if model.role == .translator {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("tokenizer_config.json")),
                  let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  config["chat_template"] != nil || nonempty("chat_template.jinja") else { return false }
        }
        let receipt = directory.appendingPathComponent(".nomi-model.json")
        if FileManager.default.fileExists(atPath: receipt.path) {
            guard let data = try? Data(contentsOf: receipt),
                  let files = try? JSONDecoder().decode([String: Int64].self, from: data) else { return false }
            for (name, bytes) in files {
                guard nonempty(name),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path),
                      (attributes[.size] as? NSNumber)?.int64Value == bytes else { return false }
            }
        }
        return true
    }
}
