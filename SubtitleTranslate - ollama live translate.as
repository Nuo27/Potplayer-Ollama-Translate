/*
 * Real-time subtitle translation for PotPlayer using Ollama
 */

// ========================
// PLUGIN METADATA
// ========================

string GetTitle() {
    return "{$CP949=Ollama번역$}{$CP950=Ollama翻譯$}{$CP0=Ollama live translate$}";
}

string GetVersion() {
    return "2.0";
}

string GetDesc() {
    // return "{$CP949=본지 AI를 사용한 실시간 자막 번역$}{$CP950=使用本地 AI 的實時字幕翻譯$}{$CP0=Real-time subtitle translation using Ollama$}";\
    return "Real-time subtitle translation Plugin using Ollama$}";
}

string GetLoginTitle() {
    return "{$CP949=본지 AI 모델 구성$}{$CP950=本地 AI 模型配置$}{$CP0=Ollama Model Configuration$}";
}

string GetLoginDesc() {
    return "{$CP949=모델 이름을 입력하십시오.$}{$CP950=請輸入模型名稱。$}{$CP0=Enter the model name or edit it in file.$}";
}

string GetUserText() {
    return "{$CP949=모델 이름 (현재: " + g_selectedModel + ")$}{$CP950=模型名稱 (目前: " + g_selectedModel + ")$}{$CP0=Model Name (Current: " + g_selectedModel + ")$}";
}

string GetPasswordText() {
    return "{$CP949=API 키:$}{$CP950=API 密钥:$}{$CP0=API Key:$}";
}

// ========================
// GLOBAL CONFIGURATION
// ========================

// Core Settings
const string DEFAULT_MODEL_NAME = "qwen3:14b";
const string DEFAULT_API_URL = "http://127.0.0.1:11434/v1/chat/completions";
const string DEFAULT_API_BASE = "http://127.0.0.1:11434";
const string USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";

// State Variables
string g_selectedModel = DEFAULT_MODEL_NAME;
string g_apiKey = "";
bool g_isPluginActive = true;

// Model Configuration
class ModelConfig {
    float temperature = 0.2;
    float topP = 0.9;
    int topK = 40;
    float minP = 0.05;
    float repeatPenalty = 1.1;
    int maxTokens = 2048;

    // the defaultParams dictionary should contain the default param values that model supports
    // and will be loaded when login 
    dictionary defaultParams;
    
    void LoadDefaults(const dictionary &in params) {
        defaultParams = params;
    }
    
    dictionary GetActiveParams() {
        dictionary result;
        
        if (defaultParams.exists("temperature"))
            result["temperature"] = temperature;
        if (defaultParams.exists("top_p"))
            result["top_p"] = topP;
        if (defaultParams.exists("top_k"))
            result["top_k"] = topK;
        if (defaultParams.exists("min_p"))
            result["min_p"] = minP;
        if (defaultParams.exists("repeat_penalty"))
            result["repeat_penalty"] = repeatPenalty;
        if (defaultParams.exists("max_tokens"))
            result["max_tokens"] = maxTokens;
        return result;
    }
}

// Reasoning Configuration
class ReasoningConfig {
    bool isReasoningModel = false;
    // modify activateReasoning will allow trying options and think field for qwen3, deepseek-r1 and other models that support thinking in ollama 0.9.0 or later.
    bool activateReasoning = false;
    bool ollamaSupportsNativeThinking = false;
    bool modelSupportsThinking = false;

    
    void DetectModelType(const string &in modelName) {
        string lowerModel = modelName;
        lowerModel.MakeLower();
        
        isReasoningModel = (lowerModel.find("qwen3") != -1) || 
                          (lowerModel.find("deepseek-r1") != -1);
    }
    
    bool IsDeepseekModel() {
        string lowerModel = g_selectedModel;
        lowerModel.MakeLower();
        return lowerModel.find("deepseek-r1") != -1;
    }
}

// Translation Context History Management
class ContextHistory {
    array<string> history;
    int maxSize = 50;
    int contextCount = 10;
    bool enabled = true;
   
    void AddEntry(const string &in text) {
        if (!enabled) return;
       
        history.insertLast(text);
        if (history.length() > uint(maxSize)) {
            history.removeAt(0);
        }
    }
   
    string GetContext() {
        if (!enabled || history.length() == 0) return "";

        string context = "Translation Context:\n";
        
        // Add recent original sentences
        int startIdx = max(0, int(history.length()) - contextCount);
        for (int i = startIdx; i < int(history.length()); ++i) {
            context += "- \"" + history[i] + "\"\n";
        }
        
        context += "\nPlease refer to the above sentences to ensure consistency in terminology, tone, and style during translation.\n";
        
        return context;
    }

}
// Global Instances
ModelConfig g_modelConfig;
ReasoningConfig g_reasoningConfig;
ContextHistory g_contextHistory;


// ========================
// TRANSLATION PROMPTS
// ========================

const string SYSTEM_PROMPT = "You are a professional subtitle translator. Your task is to fluently translate text into the target language. Strictly follow these rules:\n"
"1. Output only the translated content, without explanations or additional content.\n"
"2. Use provided context if provided to aid understanding, but DO NOT include it in your output.\n"
"3. Maintain the original tone, style, and narrative of the subtitles.\n";

const string USER_PROMPT_BASE = 
"Please follow these instructions strictly:\n"
"Step 1: Translate faithfully and accurately.\n"
"Step 2: PARAPHRASE the translated text from step 1 if needed to ensure it sounds natural and understandable in the target language.\n"
"Step 3: Output the final translation only, without any additional commentary.\n"
"\n"
"Now treat the following line as plain text and translate";

const string backup_system_prompt = "Act as a professional, authentic translation engine dedicated to providing accurate and fluent translations of subtitles. ONLY provide the translated subtitle text without any additional information.";
const string two_step_process_prompt = 
    "You are a professional subtitle translator skilled in accurate and culturally appropriate translations. I may provide additional context to help clarify the meaning. Use this context to understand the subtitle's meaning and provide an accurate translation. Follow these rules:\n"
    "1. First, perform a direct translation based on the original text without adding any information.\n"
    "2. Then, reinterpret the translation to make it sound more natural and understandable in the target language, while preserving the original meaning.\n"
    "3. Use the provided context and cultural cues to ensure the translation aligns with local language norms and nuances.\n"
    "4. Your output must only include the translated text—do not include any explanations, context, or commentary.\n";
// ========================
// SUPPORTED LANGUAGES
// ========================

array<string> g_supportedLanguages = {
    "Auto", "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca",
    "ceb", "ny", "zh-CN", "zh-TW", "co", "hr", "cs", "da", "nl", "en", "eo", "et",
    "tl", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he",
    "hi", "hmn", "hu", "is", "ig", "id", "ga", "it", "ja", "jw", "kn", "kk", "km",
    "ko", "ku", "ky", "lo", "la", "lv", "lt", "lb", "mk", "ms", "mg", "ml", "mt",
    "mi", "mr", "mn", "my", "ne", "no", "ps", "fa", "pl", "pt", "pa", "ro", "ru",
    "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw",
    "sv", "tg", "ta", "te", "th", "tr", "uk", "ur", "uz", "vi", "cy", "xh", "yi",
    "yo", "zu"
};

array<string> GetSrcLangs() {
    return g_supportedLanguages;
}

array<string> GetDstLangs() {
    return g_supportedLanguages;
}


// ========================
// UTILITY FUNCTIONS
// ========================

int max(int a, int b) {
    return (a > b) ? a : b;
}

string TrimString(const string &in text) {
    if (text.empty()) return "";
    
    int start = 0;
    int end = int(text.length()) - 1;
    
    // Trim from start
    while (start <= end) {
        string ch = text.substr(start, 1);
        if (ch != " " && ch != "\n" && ch != "\r" && ch != "\t") break;
        start++;
    }
    
    // Trim from end
    while (end >= start) {
        string ch = text.substr(end, 1);
        if (ch != " " && ch != "\n" && ch != "\r" && ch != "\t") break;
        end--;
    }
    
    if (start > end) return "";
    return text.substr(uint(start), uint(end - start + 1));
}

string EscapeJsonString(const string &in input) {
    string output = input;
    output.replace("\\", "\\\\");
    output.replace("\"", "\\\"");
    output.replace("\n", "\\n");
    output.replace("\r", "\\r");
    output.replace("\t", "\\t");
    return output;
}

string RemoveThinkingTags(const string &in text) {
    string result = text;
    int startPos = 0;
    
    while (true) {
        int openPos = result.find("<think>", startPos);
        if (openPos == -1) break;
        
        int closePos = result.find("</think>", openPos);
        if (closePos == -1) break;
        
        result = result.substr(0, openPos) + result.substr(closePos + 8);
        startPos = openPos;
    }
    
    return result;
}

array<string> SplitString(const string &in text, const string &in delimiter) {
    array<string> result;
    if (text.empty()) return result;

    int start = 0;
    int pos = text.findFirst(delimiter, start);

    while (pos >= 0) {
        string token = text.substr(start, pos - start);
        if (!token.empty()) result.insertLast(token);
        start = pos + int(delimiter.length());
        pos = text.findFirst(delimiter, start);
    }

    string token = text.substr(start);
    if (!token.empty()) result.insertLast(token);
    return result;
}


// ========================
// API COMMUNICATION
// ========================

class OllamaAPI {
    string baseUrl = DEFAULT_API_BASE;
    string chatUrl = DEFAULT_API_URL;

    array<string> GetAvailableModels() {
        string url = baseUrl + "/api/tags";
        string response = HostUrlGetString(url, USER_AGENT, "Content-Type: application/json", "");
        
        if (response.empty()) {
            return array<string>();
        }
        
        JsonReader reader;
        JsonValue root;
        
        if (!reader.parse(response, root)) {
            HostPrintUTF8("Failed to parse models list response\n");
            return array<string>();
        }
        
        JsonValue models = root["models"];
        if (!models.isArray()) {
            return array<string>();
        }
        
        array<string> result;
        for (int i = 0; i < models.size(); i++) {
            JsonValue model = models[i];
            if (model.isObject() && model["name"].isString()) {
                result.insertLast(model["name"].asString());
            }
        }
        
        return result;
    }
    
    string GetModelInfo(const string &in modelName) {
        string url = baseUrl + "/api/show";
        string requestBody = "{\"model\":\"" + modelName + "\"}";
        string response = HostUrlGetString(url, USER_AGENT, "Content-Type: application/json", requestBody);
        
        if (response.empty()) {
            return "";
        }
        
        JsonReader reader;
        JsonValue root;
        
        if (!reader.parse(response, root)) {
            return "";
        }
        
        return FormatModelInfo(root);
    }
    
    string GetVersion() {
        string url = baseUrl + "/api/version";
        string response = HostUrlGetString(url, USER_AGENT, "Content-Type: application/json", "");
        
        if (response.empty()) {
            return "";
        }
        
        JsonReader reader;
        JsonValue root;
        
        if (!reader.parse(response, root)) {
            return "";
        }
        
        return root["version"].asString();
    }
    
    bool SupportsNativeThinking() {
        string version = GetVersion();
        if (version.empty()) return false;
        
        return CompareVersion(version, "0.9.0") >= 0;
    }
    
    string SendTranslationRequest(const string &in requestData) {
        return HostUrlGetString(chatUrl, USER_AGENT, "Content-Type: application/json", requestData);
    }
    
    private string FormatModelInfo(JsonValue &in root) {
        string result = "";
        
        // Parameters
        if (root["parameters"].isString()) {
            string params = root["parameters"].asString();
            if (!params.empty()) {
                result += "Parameters:\n";
                array<string> lines = SplitString(params, "\n");
                for (uint i = 0; i < lines.length(); ++i) {
                    string line = TrimString(lines[i]);
                    if (!line.empty()) {
                        result += "  " + line + "\n";
                    }
                }
                // Parse parameters for model config
                g_modelConfig.LoadDefaults(ParseParameterString(params));
            }
        }
        
        // Model Info
        if (root["model_info"].isObject()) {
            JsonValue modelInfo = root["model_info"];
            array<string> keys = modelInfo.getKeys();
            
            if (keys.length() > 0) {
                result += "Model Info:\n";
                for (uint i = 0; i < keys.length(); ++i) {
                    string key = keys[i];
                    string value = JsonValueToString(modelInfo[key]);
                    result += "  " + key + ": " + value + "\n";
                }
            }
        }
        
        // Capabilities
        if (root["capabilities"].isArray()) {
            JsonValue capabilities = root["capabilities"];
            array<string> caps;
            
            for (int i = 0; i < capabilities.size(); i++) {
                if (capabilities[i].isString()) {
                    caps.insertLast(capabilities[i].asString());
                }
            }
            g_reasoningConfig.modelSupportsThinking = caps.find("thinking") != -1;
        }
        
        return result;
    }
    
    string JsonValueToString(JsonValue &in value)
    {
        try{
            if (value.isNull()) return "null";
            if (value.isString()) return value.asString();
            if (value.isBool()) return value.asBool() ? "true" : "false";
            if (value.isInt()) return "" + value.asInt();
            if (value.isUInt()) return "" + value.asUInt();
            if (value.isFloat()) return "" + value.asFloat();
            return "(unknown type)";
        }
        catch {
            return "Error converting JSON to string";
        }


    }

    
    private int CompareVersion(const string &in version1, const string &in version2) {
        array<string> v1Parts = SplitString(version1, ".");
        array<string> v2Parts = SplitString(version2, ".");
        
        uint maxLen = max(v1Parts.length(), v2Parts.length());
        
        for (uint i = 0; i < maxLen; i++) {
            int val1 = (i < v1Parts.length()) ? parseInt(v1Parts[i]) : 0;
            int val2 = (i < v2Parts.length()) ? parseInt(v2Parts[i]) : 0;
            
            if (val1 > val2) return 1;
            if (val1 < val2) return -1;
        }
        
        return 0;
    }
}

OllamaAPI g_api;

// ========================
// PARAMETER PARSING
// ========================

dictionary ParseParameterString(const string &in paramString) {
    dictionary result;
    array<string> lines = SplitString(paramString, "\n");
    
    for (uint i = 0; i < lines.length(); ++i) {
        string line = TrimString(lines[i]);
        if (line.empty()) continue;
        
        array<string> parts = SplitString(line, " ");
        if (parts.length() >= 2) {
            string key = TrimString(parts[0]);
            string value = TrimString(parts[1]);
            if (!key.empty() && !value.empty()) {
                result[key] = value;
            }
        }
    }
    
    return result;
}

// ========================
// REQUEST BUILDING
// ========================

string BuildTranslationRequest(const string &in text, const string &in srcLang, const string &in dstLang) {
    // Build prompt
    string prompt = "";
    
    // Add reasoning prefix for Qwen models
    if (g_reasoningConfig.isReasoningModel) {
        string modelLower = g_selectedModel;
        modelLower.MakeLower();
        if (modelLower.find("qwen3") != -1) {
            prompt += g_reasoningConfig.activateReasoning ? "/think " : "/no_think ";
        }
    }
    
    // Add context if enabled
    string context = "\n";
    if (g_contextHistory.enabled) {
        context += g_contextHistory.GetContext();
    }
    
    // Add main translation request
    prompt += USER_PROMPT_BASE;
    if (!srcLang.empty()) {
        prompt += " from " + srcLang;
    }
    prompt += " to " + dstLang + ":\n";
    prompt += text;
    
    // Build messages array
    string escapedSystem = EscapeJsonString(SYSTEM_PROMPT+context);
    string escapedUser = EscapeJsonString(prompt);
    
    string messages = "["
        + "{\"role\":\"system\",\"content\":\"" + escapedSystem + "\"},"
        + "{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}"
        + "]";
    
    // Build request data
    string requestData = "{"
        + "\"model\":\"" + g_selectedModel + "\","
        + "\"messages\":" + messages;
    
    // Add model parameters
    dictionary params = g_modelConfig.GetActiveParams();
    if (params.getSize() > 0) {
        requestData += ",\"options\":{";
        array<string> keys = params.getKeys();
        
        for (uint i = 0; i < keys.length(); i++) {
            string key = keys[i];
            requestData += "\"" + key + "\":";
            
            // Handle different value types
            float fVal;
            int iVal;
            if (params.get(key, fVal)) {
                requestData += "" + fVal;
            } else if (params.get(key, iVal)) {
                requestData += "" + iVal;
            }
            
            if (i < keys.length() - 1) {
                requestData += ",";
            }
        }
        requestData += "}";
    }
    
    // Add native thinking support if available
    if (g_reasoningConfig.ollamaSupportsNativeThinking) {
        requestData += ",\"think\":" + (g_reasoningConfig.activateReasoning ? "true" : "false");
    }
    
    // Add deep thinking for Deepseek models
    if (g_reasoningConfig.IsDeepseekModel()) {
        requestData += ",\"deep_thinking\":" + (g_reasoningConfig.activateReasoning ? "true" : "false");
    }
    
    requestData += "}";
    
    return requestData;
}

// ========================
// SERVER AUTHENTICATION
// ========================

string ServerLogin(string User, string Pass) {
    g_selectedModel = TrimString(User);
    g_apiKey = TrimString(Pass);
    
    if (g_selectedModel.empty()) {
        g_selectedModel = DEFAULT_MODEL_NAME;
    }
    
    // Test ollama connection and get available models
    array<string> availableModels = g_api.GetAvailableModels();
    if (availableModels.length() == 0) {
        return "Unable to connect to Ollama. Please ensure Ollama is running and has models available.";
    }
    
    // Validate selected model
    string selectedLower = g_selectedModel;
    selectedLower.MakeLower();
    
    bool modelFound = false;
    for (uint i = 0; i < availableModels.length(); i++) {
        string availableLower = availableModels[i];
        availableLower.MakeLower();
        if (selectedLower == availableLower) {
            modelFound = true;
            g_selectedModel = availableModels[i]; // Use exact case from server
            break;
        }
    }
    
    if (!modelFound) {
        return "Model '" + g_selectedModel + "' not found.";
    }
    
    // Initialize configuration
    g_reasoningConfig.DetectModelType(g_selectedModel);
    g_reasoningConfig.ollamaSupportsNativeThinking = g_api.SupportsNativeThinking();
    
    // Get model information
    string modelInfo = g_api.GetModelInfo(g_selectedModel);
    if (modelInfo.empty()) {
        HostPrintUTF8("Warning: Could not retrieve model information\n");
        return "Unable to retrieve model information.";
    }
    // HostMessageBox(modelInfo, "Model Information", 0);
    HostPrintUTF8("Model information retrieved successfully\n" + modelInfo);
    
    // Save settings
    HostSaveString("api_key_ollama", g_apiKey);
    HostSaveString("selected_model_ollama", g_selectedModel);
    
    g_isPluginActive = true;
    
    HostPrintUTF8("Successfully configured Ollama translation plugin\n");
    HostPrintUTF8("Model: " + g_selectedModel + "\n");
    HostPrintUTF8("Native thinking support: " + (g_reasoningConfig.ollamaSupportsNativeThinking ? "Yes" : "No") + "\n");


    // TEST request and response
    // Consider comment out the following test code when you are done testing and the translation is working as expected.
    // This is just for testing purposes to ensure that the translation function works correctly.

    // Send a test request and check the response 
    string test_srcLang = "en";
    string test_dstLang = "fr";
    string test_text = "Hello, how are you?";

    string translated_text = Translate(test_text, test_srcLang, test_dstLang);

    string test_request = BuildTranslationRequest(test_text, test_srcLang, test_dstLang);
    // HostMessageBox(test_request, "Test Request", 0);

    
    if(!translated_text.empty() && translated_text != "") {
        HostPrintUTF8("Translation task completed successfully!\n" + "Test Text: " + test_text + "\n" + "Translated Text: " + translated_text + "\n" );
        // HostMessageBox("TEST Translation task completed successfully!\n" + "Test Text: " + test_text + "\n" + "Translated Text: " + translated_text + "\n", "Success", 0);
    }
    else {
        HostMessageBox("Translation task failed. Please check the settings", "Error", 0);
        return "Translation task failed. Please check the settings";
    }
    
    return "200 ok";
}

void ServerLogout() {
    g_apiKey = "";
    g_selectedModel = DEFAULT_MODEL_NAME;
    g_isPluginActive = false;
    
    HostSaveString("api_key_ollama", "");
    HostSaveString("selected_model_ollama", g_selectedModel);
    HostPrintUTF8("Successfully logged out from Ollama translation plugin\n");
}

// ========================
// MAIN TRANSLATION FUNCTION
// ========================

string Translate(string Text, string &in SrcLang, string &in DstLang) {
    if (!g_isPluginActive) {
        return "";
    }
    
    // Validate target language
    if (DstLang.empty() || DstLang == "Auto" || DstLang.find("자동") != -1 || DstLang.find("自動") != -1) {
        HostPrintUTF8("Target language not specified\n");
        return "";
    }
    
    // Handle source language
    string srcLangCode = SrcLang;
    if (srcLangCode.empty() || srcLangCode == "Auto" || srcLangCode.find("자동") != -1 || srcLangCode.find("自動") != -1) {
        srcLangCode = "";
    }
        
    // Build and send request
    string requestData = BuildTranslationRequest(Text, srcLangCode, DstLang);
    
    // Add to context history
    g_contextHistory.AddEntry(Text);

    string response = g_api.SendTranslationRequest(requestData);

    
    if (response.empty()) {
        HostPrintUTF8("Translation request failed - no response\n");
        return "";
    }
    
    // Parse response
    JsonReader reader;
    JsonValue root;
    
    if (!reader.parse(response, root)) {
        HostPrintUTF8("Failed to parse translation response\n");
        return "";
    }
    
    // Extract translated text
    JsonValue choices = root["choices"];
    if (!choices.isArray() || choices.size() == 0) {
        HostPrintUTF8("Invalid response format - no choices\n");
        return "";
    }
    
    JsonValue firstChoice = choices[0];
    JsonValue message = firstChoice["message"];
    if (!message.isObject()) {
        HostPrintUTF8("Invalid response format - no message\n");
        return "";
    }
    
    JsonValue content = message["content"];
    if (!content.isString()) {
        HostPrintUTF8("Invalid response format - no content\n");
        return "";
    }
    
    string translatedText = content.asString();
    
    // Clean up the translated text
    translatedText = RemoveThinkingTags(translatedText);
    translatedText = TrimString(translatedText);
    
    // Add RTL marker for certain languages
    if (DstLang == "fa" || DstLang == "ar" || DstLang == "he") {
        translatedText = "\u202B" + translatedText;
    }
    
    // Set output language encoding
    SrcLang = "UTF8";
    DstLang = "UTF8";
    
    return translatedText;
}

// ========================
// PLUGIN LIFECYCLE
// ========================

void OnInitialize() {
    HostPrintUTF8("Ollama translation plugin loaded\n");
    
    // Load saved settings
    g_apiKey = HostLoadString("api_key_ollama", "");
    g_selectedModel = HostLoadString("selected_model_ollama", DEFAULT_MODEL_NAME);
    
    // Initialize API configuration
    g_reasoningConfig.DetectModelType(g_selectedModel);
    
    if (!g_apiKey.empty()) {
        HostPrintUTF8("Loaded saved configuration\n");
        g_isPluginActive = true;
    } else {
        g_isPluginActive = false;
    }
}

void OnFinalize() {
    HostPrintUTF8("Ollama translation plugin unloaded\n");
}