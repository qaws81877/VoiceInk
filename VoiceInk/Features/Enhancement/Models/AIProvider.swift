import Foundation

enum AIProvider: String, CaseIterable {
    case cerebras = "Cerebras"
    case groq = "Groq"
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case mistral = "Mistral"
    case elevenLabs = "ElevenLabs"
    case deepgram = "Deepgram"
    case soniox = "Soniox"
    case speechmatics = "Speechmatics"
    case assemblyAI = "AssemblyAI"
    case ollama = "Ollama"
    case localCLI = "Local CLI"
    case custom = "Custom"

    var baseURL: String {
        switch self {
        case .cerebras:
            return "https://api.cerebras.ai/v1/chat/completions"
        case .groq:
            return "https://api.groq.com/openai/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1/interactions"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .openRouter:
            return "https://openrouter.ai/api/v1/chat/completions"
        case .mistral:
            return "https://api.mistral.ai/v1/chat/completions"
        case .elevenLabs:
            return "https://api.elevenlabs.io/v1/speech-to-text"
        case .deepgram:
            return "https://api.deepgram.com/v1/listen"
        case .soniox:
            return "https://api.soniox.com/v1"
        case .speechmatics:
            return "https://asr.api.speechmatics.com/v2"
        case .assemblyAI:
            return "https://api.assemblyai.com/v2/transcript"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        case .localCLI:
            return ""
        case .custom:
            return UserDefaults.standard.string(forKey: "customProviderBaseURL") ?? ""
        }
    }

    var defaultModel: String {
        switch self {
        case .cerebras:
            return "qwen-3.8-27b"
        case .groq:
            return "qwen/qwen3.8-27b"
        case .gemini:
            return "gemini-3.8-flash"
        case .anthropic:
            return "claude-sonnet-5"
        case .openAI:
            return "gpt-6-luna"
        case .mistral:
            return "mistral-small-latest"
        case .elevenLabs:
            return "scribe_v2"
        case .deepgram:
            return "whisper-1"
        case .soniox:
            return "stt-async-v5"
        case .speechmatics:
            return "speechmatics-enhanced"
        case .assemblyAI:
            return "universal-3-5-pro"
        case .ollama:
            return UserDefaults.standard.string(forKey: "ollamaSelectedModel") ?? "mistral"
        case .localCLI:
            return "local-cli"
        case .custom:
            return CustomAIProviderManager.shared.defaultModelName
        case .openRouter:
            return "qwen/qwen3.8-27b"
        }
    }

    var availableModels: [String] {
        switch self {
        case .cerebras:
            return [
                "qwen-3.8-27b",
                "gpt-oss-120b",
            ]
        case .groq:
            return [
                "qwen/qwen3.8-27b",
                "openai/gpt-oss-120b",
                "openai/gpt-oss-20b",
            ]
        case .gemini:
            return [
                "gemini-3.8-flash",
                "gemini-3.7-flash",
                "gemini-3.6-flash",
                "gemini-3.5-flash-lite",
                "gemini-3.5-flash",
                "gemini-3.1-pro-preview",
                "gemini-3.1-flash-lite",
                "gemini-2.5-flash-lite",
            ]
        case .anthropic:
            return [
                "claude-sonnet-5",
                "claude-haiku-5-5",
                "claude-haiku-4-5",
            ]
        case .openAI:
            return [
                "gpt-6-luna",
                "gpt-6-sol",
                "gpt-5.6-luna",
                "gpt-5.6-terra",
                "gpt-5.6-sol",
                "gpt-5.5",
                "gpt-5.4",
                "gpt-5.4-mini",
                "gpt-5.4-nano",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
            ]
        case .mistral:
            return [
                "mistral-small-latest",
                "mistral-medium-latest",
                "mistral-large-latest",
            ]
        case .elevenLabs:
            return ["scribe_v2", "scribe_v2_medical"]
        case .deepgram:
            return ["whisper-1"]
        case .soniox:
            return ["stt-async-v5"]
        case .speechmatics:
            return ["speechmatics-enhanced"]
        case .assemblyAI:
            return ["universal-3-5-pro"]
        case .ollama:
            return []
        case .localCLI:
            return []
        case .custom:
            return CustomAIProviderManager.shared.availableModelNames
        case .openRouter:
            return []
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama, .localCLI:
            return false
        default:
            return true
        }
    }

    var supportsEnhancement: Bool {
        switch self {
        case .elevenLabs, .deepgram, .soniox, .speechmatics, .assemblyAI:
            return false
        default:
            return true
        }
    }

    var supportsCustomModelID: Bool {
        switch self {
        case .cerebras, .groq, .gemini, .anthropic, .openAI, .mistral:
            return true
        default:
            return false
        }
    }
}
