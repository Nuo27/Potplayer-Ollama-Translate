/*
 * Real-time subtitle translation for PotPlayer using Ollama
 */

// ========================
// TRANSLATION PROMPTS
// ========================
const string SYSTEM_PROMPT_BASE =
    "You are a professional simultaneous interpreter with broad multidisciplinary expertise. "
    "You provide fluent, accurate, and natural real-time translations, even when the source text is incomplete, fragmented, or contains grammatical errors.\n"
    "\n"
    "Your task is to translate the user's input into the target language with maximum semantic fidelity, natural flow, and contextual accuracy.\n"
    "\n"
    "ABSOLUTE RULES (MUST FOLLOW):\n"
    "1. Output ONLY the final translated text.\n"
    "2. Do NOT output explanations, notes, labels, commentary, analysis, or any extra content.\n"
    "3. Preserve the original meaning, tone, intent, structure, and formatting as closely as possible.\n"
    "4. Preserve all proper names, technical terms, abbreviations, numbers, symbols, code, placeholders, and tags exactly as they appear in the source text.\n"
    "5. Do NOT add, remove, or reinterpret information.\n"
    "6. Do NOT use Markdown unless the source text explicitly uses Markdown.\n"
    "\n"
    "TRANSLATION GUIDELINES:\n"
    "- Use natural, fluent, idiomatic expressions when literal translation would sound unnatural.\n"
    "- Maintain smooth readability suitable for spoken or subtitle output.\n"
    "- If the source text is awkward or ungrammatical, correct it naturally without changing its meaning.\n"
    "- Do NOT censor, summarize, or embellish.\n"
    "\n"
    "Plain text output only.\n";


const string USER_PROMPT_BASE =
    "Treat the the sentence inside <Text> tags as plain text and translate";

const string CONTEXT_PROMPT =
    "The following content is provided as reference context only.\n"
    "It is NOT part of the text to translate.\n"
    "Do NOT translate, modify, or include it in the output.\n"
    "Use it only to understand context, tone, and continuity.\n";

const string SYSTEM_PROMPT_OLD = 
"You are a professional subtitle translator. Your task is to fluently translate text into the target language. Strictly follow these rules:\n"
"1. Output only the translated content, without explanations or additional content.\n"
"2. Use provided context if provided to aid understanding, but DO NOT include it in your output.\n"
"3. Maintain the original tone, style, and narrative of the subtitles.\n";

const string SYSTEM_PROMPT_BASIC = 
"Act as a professional, authentic translation engine dedicated to providing accurate and fluent translations of subtitles. \n"
"ONLY provide the translated subtitle text without any additional information.";

const string SYSTEM_PROMPT_BASIC_OLD_TWO_STEP = 
    "You are a professional subtitle translator skilled in accurate and culturally appropriate translations. I may provide additional context to help clarify the meaning. Use this context to understand the subtitle's meaning and provide an accurate translation. Follow these rules:\n"
    "1. First, perform a direct translation based on the original text without adding any information.\n"
    "2. Then, reinterpret the translation to make it sound more natural and understandable in the target language, while preserving the original meaning.\n"
    "3. Use the provided context and cultural cues to ensure the translation aligns with local language norms and nuances.\n"
    "4. Your output must only include the translated text—do not include any explanations, context, or commentary.\n";

// ========================
// GLOBAL CONFIGURATION
// ========================

// Core Settings
const string DEFAULT_MODEL_NAME = "qwen3-vl:30b-a3b-instruct-q4_K_M";

// State Variables
string g_selectedModel = DEFAULT_MODEL_NAME;
// replace the value with const prompt field name
string userPrompt = USER_PROMPT_BASE;
string systemPrompt = SYSTEM_PROMPT_BASE;
bool g_isPluginActive = true;

// Model Configuration
class ModelConfig {
    float temperature = 0.5;
    float topP = 0.9;
    int topK = 40;
    float minP = 0.1;
    float repeatPenalty = 1.1;
    int maxTokens = 2048;

    // the defaultParams dictionary should contain the default param values that model supports
    // and will be loaded when login 
    dictionary defaultParams;
    
    void LoadDefaults(const dictionary &in params) {
        defaultParams = params;
    }
    // only returns editable params
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
    // modify enable thinking will allow thinking for reasoning models that is supported in ollama 0.9.0 or later.
    bool enableThinking = false;
    // modify thinkStrength will allow changing the strength of thinking, options are low, medium, high. This is only applicable for gpt-oss
    // keep blank ("") if you are not using gpt-oss 
    string thinkStrength = "";

    // below should not be modify
    bool ollamaSupportsNativeThinking = false;
    bool modelSupportsThinking = false;
}

// Translation Context History Management
class ContextHistory {
    array<string> history;
    int maxSize = 10;
    int contextCount = 5;
    bool enabled = true;

    void AddEntry(const string &in text) {
        if (!enabled || text.length() == 0) return;

        history.insertLast(text);
        if (history.length() > uint(maxSize)) {
            history.removeAt(0);
        }
    }

    string GetContext() {
        if (!enabled || history.length() == 0) return "";

        string context = CONTEXT_PROMPT + "\n";
        context += "<Context>\n";

        int startIdx = max(0, int(history.length()) - contextCount);
        for (int i = startIdx; i < int(history.length()); ++i) {
            context += history[i] + "\n";
        }

        context += "</Context>\n";
        return context;
    }
}

// ========================
// OLLAMA API COMMUNICATION
// ========================

class OllamaAPI {
    string baseUrl = "http://127.0.0.1:11434";
    string chatRoute = "/api/chat";
    string openAIRoute = "/v1/chat/completions";
    string userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
    string ContentType = "Content-Type: application/json";

    bool useOllamaNative = true;

    // API Key for OLLAMA CLOUD
    bool useAPIKey = false;
    string apiKey = "";
    string ollamaCloudUrl = "https://ollama.com";

    string modelArchitecture = "";

    // Methods
    array<string> GetAvailableModels() {
        string url = baseUrl + "/api/tags";
        string response = HostUrlGetString(url, userAgent, "Content-Type: application/json", "");
        
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
        string response = HostUrlGetString(url, userAgent, "Content-Type: application/json", requestBody);
        
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
        string response = HostUrlGetString(url, userAgent, "Content-Type: application/json", "");
        
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

    // Return the think options 
    // When true, returns separate thinking output in addition to content. Can be a boolean (true/false) or a string ("high", "medium", "low") for supported models.
    string GetThinkOption() {
        HostPrintUTF8("modelArchitecture: " + modelArchitecture + "\n");

        if (modelArchitecture == "gpt-oss" && !g_reasoningConfig.enableThinking) {
            return "\"low\"";
        }

        if (modelArchitecture != "gpt-oss") {
            if (!g_reasoningConfig.enableThinking) {
                return "false";
            }
            return g_reasoningConfig.thinkStrength.empty()
                ? "true"
                : "\"" + g_reasoningConfig.thinkStrength + "\"";
        }
        return "\"" + (g_reasoningConfig.enableThinking
                    ? (g_reasoningConfig.thinkStrength.empty()
                        ? "true"
                        : g_reasoningConfig.thinkStrength)
                    : "false") + "\"";
    }

    // Build the header for the request
    string BuildHeader(bool useAPIKey, const string &in apiKey)
    {
        string header = ContentType;

        if (useAPIKey) {
            // Add the Authorization header if an API key is supplied.
            header += "\nAuthorization: Bearer " + apiKey;
        }

        return header;
    }
    // Build the URL for the request
    string BuildUrl(bool useAPIKey, bool useOllamaNative,
                const string &in baseUrl, const string &in cloudUrl)
    {
        // ollama cloud endpoint
        if (useAPIKey) {
            return cloudUrl + chatRoute;
        }

        // ollama native endpoint
        if (useOllamaNative) {
            return baseUrl + chatRoute;
        }

        // openai compatible endpoint
        return baseUrl + openAIRoute;
    }
    // Send the translation request to the API
    string SendTranslationRequest(const string &in requestData)
    {
        string url = BuildUrl(g_ollama_api.useAPIKey,
                            useOllamaNative,
                            baseUrl,
                            ollamaCloudUrl);

        string header = BuildHeader(g_ollama_api.useAPIKey,
                                    g_ollama_api.apiKey);

        HostPrintUTF8("request url   : " + url + "\n");
        HostPrintUTF8("request header: " + header + "\n");
        HostPrintUTF8("request data  : " + requestData + "\n");

        return HostUrlGetString(url, userAgent, header, requestData);
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
                    if (key == "general.architecture") {
                        modelArchitecture = value;
                    }
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

    // parse parameter string to dictionary
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
    
    // build translation request string
    string BuildTranslationRequest(const string &in text,
                               const string &in srcLang,
                               const string &in dstLang)
    {
        string prompt = "";
        string context = "";
        if (g_contextHistory.enabled) {
            context = g_contextHistory.GetContext();
        }

        prompt += context;
        prompt += userPrompt;

        if (!srcLang.empty() && srcLang != "auto") {
            prompt += " from " + srcLang;
        }
        prompt += " to " + dstLang + ".\n";
        prompt += "<Text>" + text + "</Text>";

        string escapedSystem = EscapeJsonString(systemPrompt);
        string escapedUser   = EscapeJsonString(prompt);

        string messages = "["
            + "{\"role\":\"system\",\"content\":\"" + escapedSystem + "\"},"
            + "{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}"
            + "]";

        string requestData = "{"
            + "\"model\":\"" + g_selectedModel + "\","
            + "\"messages\":" + messages;

        dictionary params = g_modelConfig.GetActiveParams();
        if (params.getSize() > 0) {
            requestData += ",\"options\":{";
            array<string> keys = params.getKeys();
            for (uint i = 0; i < keys.length(); i++) {
                string key = keys[i];
                requestData += "\"" + key + "\":";

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

        if (g_reasoningConfig.ollamaSupportsNativeThinking) {
            requestData += ",\"think\": " + g_ollama_api.GetThinkOption();
        }

        requestData += ",\"stream\":false";
        requestData += "}";

        return requestData;
    }
}

// ========================
// GLOBALS INSTANCE
// ========================

ModelConfig g_modelConfig;
ReasoningConfig g_reasoningConfig;
ContextHistory g_contextHistory;
OllamaAPI g_ollama_api;


// ========================
// REQUEST BUILDING
// ========================


// load user config
void LoadUserConfig() {
    g_selectedModel = HostLoadString("selected_model_ollama");
    HostPrintUTF8("Loaded model: " + g_selectedModel + "\n");
    g_ollama_api.apiKey = HostLoadString("api_key_ollama");
    HostPrintUTF8("Loaded API Key: " + g_ollama_api.apiKey + "\n");
}
// check model exist
bool IsModelValid(string modelName){
    array<string> availableModels = g_ollama_api.GetAvailableModels();
    if (availableModels.length() == 0) {
        return false;
    }
    string selectedLower = g_selectedModel;
    selectedLower.MakeLower();
    
    for (uint i = 0; i < availableModels.length(); i++) {
        string availableLower = availableModels[i];
        availableLower.MakeLower();
        if (selectedLower == availableLower) {
            g_selectedModel = availableModels[i];
            return true;
        }
    }
    return false;
}

// ========================
// SERVER AUTHENTICATION
// ========================

string ServerLogin(string User, string Pass) {
    // process model name
    g_selectedModel = TrimString(User);
    
    // Set default model if none selected
    if (g_selectedModel.empty()) {
        g_selectedModel = DEFAULT_MODEL_NAME;
    }
    
    // Test ollama connection and get available models
    array<string> availableModels = g_ollama_api.GetAvailableModels();
    if (availableModels.length() == 0) {
        return "500 Unable to connect to Ollama. Please ensure Ollama is running and has models available.";
    }
    
    // Check if selected model is available
    HostPrintUTF8("Is "+ g_selectedModel + " valid: " + (IsModelValid(g_selectedModel) ? "true" : "false") + "\n");

    if (!IsModelValid(g_selectedModel)) {
        return "404 Model not found.";
    }
    
    // Initialize configuration
    g_reasoningConfig.ollamaSupportsNativeThinking = g_ollama_api.SupportsNativeThinking();
    
    // Get model information
    string modelInfo = g_ollama_api.GetModelInfo(g_selectedModel);

    if (modelInfo.empty()) {
        HostPrintUTF8("Warning: Could not retrieve model information\n");
        return "Unable to retrieve model information.";
    }

    HostPrintUTF8("Model information retrieved successfully\n" + modelInfo);

    // Save Model
    HostSaveString("selected_model_ollama", g_selectedModel);
    
    // Process API Key
    g_ollama_api.useAPIKey = false;
    g_ollama_api.apiKey = "";
    if(!Pass.empty()){
        g_ollama_api.useAPIKey = true;
        g_ollama_api.apiKey = TrimString(Pass);
    }
    HostSaveString("api_key_ollama", g_ollama_api.apiKey);

    
    g_isPluginActive = true;
    
    HostPrintUTF8("Successfully configured Ollama translation plugin\n");
    HostPrintUTF8("Native thinking support: " + (g_reasoningConfig.ollamaSupportsNativeThinking ? "Yes" : "No") + "\n");
    LoadUserConfig();


    // TEST request and response
    // PLEASE comment out the following test code when you are done testing and the translation is working as expected.
    // This is just for testing purposes to ensure that the translation function works correctly.

    // Send a test request and check the response 
    // string test_srcLang = "auto";
    // string test_dstLang = "jp";
    // string test_text = "Why is the sky blue?";
    // string translated_text = Translate(test_text, test_srcLang, test_dstLang);
    
    // if(!translated_text.empty() && translated_text != "") {
    //     HostPrintUTF8("Translation task completed successfully!\n" + test_srcLang + " -> " + test_dstLang + "\n"+ "Test Text: " + test_text + "\n" + "Translated Text: " + translated_text + "\n" );
    // }
    // else {
    //     HostPrintUTF8("Translation task failed. Please check the settings");
    //     return "Translation task failed. Please check the settings";
    // }
    
    return "200 ok";
}

void ServerLogout() {
    HostSaveString("selected_model_ollama", g_selectedModel);
    HostSaveString("api_key_ollama", "");
    HostPrintUTF8("Successfully logged out from Ollama translation plugin\n");
}

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
// MAIN TRANSLATION FUNCTION
// ========================

string Translate(string Text, string &in SrcLang, string &in DstLang) {
    if (!g_isPluginActive) {
        return "Plugin is not loaded normally, please check settings";
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
    string requestData = g_ollama_api.BuildTranslationRequest(Text, srcLangCode, DstLang);

    // Add to context history
    g_contextHistory.AddEntry(Text);

    string response = g_ollama_api.SendTranslationRequest(requestData);

    
    if (response.empty()) {
        HostPrintUTF8("Translation request failed - no response\n");
        return "";
    }
    
    string translatedText = ExtractTranslatedText(response);
    
    // this step shall not be processed since 0.9.0 and ollama moves thinking content to a seperate field
    // but i will keep this, feel free to remove it if you want.
    translatedText = RemoveThinkingTags(translatedText);
    // Clean up the translated text
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
// -------------------------------------------------------------------
//  Extract the translated content from the JSON response.
//  -------------------------------------------------------------------
string ExtractTranslatedText(const string response)
{
    JsonReader reader;
    JsonValue root;

    if (!reader.parse(response, root)) {
        HostPrintUTF8("Failed to parse translation response\n");
        return "";
    }

    HostPrintUTF8("response: " + response + "\n");

    JsonValue message;

    if (!g_ollama_api.useOllamaNative) {
        JsonValue choices = root["choices"];
        if (!choices.isArray() || choices.size() == 0) {
            HostPrintUTF8("Invalid response format - no choices\n");
            return "";
        }

        message = choices[0]["message"];
    }
    else {
        message = root["message"];
    }

    if (!message.isObject()) {
        HostPrintUTF8("Invalid response format - no message\n");
        return "";
    }

    JsonValue content = message["content"];
    if (!content.isString()) {
        HostPrintUTF8("Invalid response format - no content\n");
        return "";
    }

    return content.asString();
}

// ========================
// PLUGIN LIFECYCLE
// ========================

void OnInitialize() {
    // OPEN CONSOLE
    // Open the console for debugging purposes
    // PLEASE comment out the following line if debugging is not needed
    // HostOpenConsole();
    HostPrintUTF8("Ollama translation plugin initialized\n");
}

void OnFinalize() {
    HostPrintUTF8("Ollama translation plugin finalized\n");
}

// ========================
// PLUGIN METADATA
// ========================
string GetTitle() {
    return "{$CP949=Ollama번역$}{$CP950=Ollama翻譯$}{$CP936=Ollama翻译$}{$CP0=Ollama translate$}";
}

string GetVersion() {
    return "2.2";
}

string GetDesc() {
    return "https://github.com/Nuo27/Potplayer-Ollama-Translate";
}

string GetLoginTitle() {
    return "{$CP949=Ollama 모델 설정$}{$CP950=Ollama 模型設定$}{$CP936=Ollama 模型配置$}{$CP0=Ollama Model Configuration$}";
}

string GetLoginDesc() {
    return "{$CP949=모델 이름을 입력하거나 파일에서 편집하세요.$}{$CP950=輸入模型名稱或於檔案中編輯。$}{$CP936=输入模型名称或在文件中编辑。$}{$CP0=Enter the model name or edit it in file.$}";
}

string GetUserText() {
    return "{$CP949=모델 이름$}{$CP950=模型名稱$}{$CP936=模型名称$}{$CP0=Model Name$}";
}

string GetPasswordText() {
    return "{$CP949=API 키:$}{$CP950=API 密鑰:$}{$CP936=API 密钥$}{$CP0=API Key:$}";
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

// ollama moves thinking content to a seperate field so this should not be needed after 0.9.0
// However, this function can be used to remove thinking tags from a string, just keep if needed :)
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