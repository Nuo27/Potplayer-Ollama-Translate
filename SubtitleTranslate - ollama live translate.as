/*
 * Real-time subtitle translation for PotPlayer using Ollama
 */

// ========================
// PLUGIN METADATA & LIFECYCLE
// ========================

string GetTitle() {
    return "{$CP949=Ollama translate$}{$CP950=Ollama translate$}{$CP936=Ollama translate$}{$CP0=Ollama translate$}";
}

string GetVersion() { return "2.3"; }

string GetDesc() { return "https://github.com/Nuo27/Potplayer-Ollama-Translate"; }

string GetLoginTitle() {
    return "{$CP949=Ollama Model Configuration$}{$CP950=Ollama Model Configuration$}{$CP936=Ollama Model Configuration$}{$CP0=Ollama Model Configuration$}";
}

string GetLoginDesc() {
    return "{$CP949=Enter the model name or edit it in file.$}{$CP950=Enter the model name or edit it in file.$}{$CP936=Enter the model name or edit it in file.$}{$CP0=Enter the model name or edit it in file.$}";
}

string GetUserText() {
    return "{$CP949=Model Name$}{$CP950=Model Name$}{$CP936=Model Name$}{$CP0=Model Name$}";
}

string GetPasswordText() {
    return "{$CP949=API Key:$}{$CP950=API Key:$}{$CP936=API Key:$}{$CP0=API Key:$}";
}

void OnInitialize() {
    // Uncomment the following func for debugging
    // HostOpenConsole();
    HostPrintUTF8("Ollama translation plugin initialized\n");
}

void OnFinalize() {
    HostPrintUTF8("Ollama translation plugin finalized\n");
}

// ========================
// PROMPTS
// ========================
const string SYSTEM_PROMPT_BASE =
"You are a real-time interpreter.\n"
"Translate the input from {{from}} to {{to}}.\n"
"\n"
"Core Requirements:\n"
"- Output ONLY the translation in {{to}}\n"
"- Preserve original meaning, tone, and intent\n"
"- Keep names, numbers, symbols, and formatting unchanged\n"
"\n"
"Context Handling:\n"
"- Context/history may be provided for reference\n"
"- Use it only to maintain tone and continuity\n"
"- NEVER translate or repeat context/history\n"
"\n"
"Style Rules:\n"
"- Produce natural, fluent, native-sounding output in {{to}}\n"
"- Lightly smooth disfluencies if needed for clarity\n"
"- Do NOT add, omit, or change meaning\n"
"- If input is incomplete, translate it as-is\n"
"\n"
"Strict Rules:\n"
"- No explanations, comments, or extra text\n"
"- Output plain text only\n";

const string USER_PROMPT_BASE =
"{{context_prompt}}"
"\n"
"Translate ONLY the text inside <Text> into {{to}}.\n"
"The context is for tone and continuity only and must NOT be translated.\n"
"\n"
"<Text>\n"
"{{text_to_translate}}\n"
"</Text>";

const string CONTEXT_PROMPT_BASE =
"The context below provides reference material from prior turns.\n"
"Use it for tone, intent, and continuity only.\n"
"Do NOT translate or quote the context.\n"
"\n"
"<Context>\n"
"{{optional_reference_context}}\n"
"</Context>";

const string SYSTEM_PROMPT_LONG =
    "Role: Simultaneous Interpreter\n"
    "\n"
    "Profile\n"
    "- Source Language: {{from}}\n"
    "- Target Language: {{to}}\n"
    "- Description: Act as a senior professional simultaneous interpreter, delivering accurate, natural, and listener-friendly translations suitable for real-time interpretation or subtitles.\n"
    "- Experience: 15+ years in corporate, legal, diplomatic, and technical live interpretation.\n"
    "- Style: Calm, precise, adaptive, and native-sounding.\n"
    "\n"
    "Core Skills\n"
    "1. Interpretation\n"
    "- Accuracy: Preserve original meaning, intent, and tone.\n"
    "- Fluency: Produce natural spoken language; avoid stiff or literal phrasing.\n"
    "- Cultural Adaptation: Adjust expressions appropriately from {{from}} to {{to}}.\n"
    "- Real-time Optimization: Prioritize clarity, brevity, and smooth flow.\n"
    "\n"
    "2. Technical Handling\n"
    "- Terminology Consistency: Maintain domain-specific terms across {{from}} → {{to}}.\n"
    "- Preservation: Keep all names, numbers, symbols, identifiers, code, and tags unchanged.\n"
    "- Formatting: Preserve original punctuation, spacing, and structure.\n"
    "- Smoothing: Remove filler words, repetitions, and minor grammatical issues without altering meaning.\n"
    "\n"
    "Output Rules (Strict)\n"
    "- Output ONLY the translated text in {{to}}.\n"
    "- Do NOT include explanations, notes, comments, or metadata.\n"
    "- Do NOT add, omit, or reinterpret content.\n"
    "- Do NOT use Markdown unless present in the source.\n"
    "- Output plain text only.\n"
    "\n"
    "Context History Handling\n"
    "- The user prompt may include prior context or conversation history in {{from}}.\n"
    "- Use context ONLY as background to resolve references, implied meaning, tone, and terminology consistency.\n"
    "- Translate ONLY the explicitly provided target text from {{from}} to {{to}}.\n"
    "- Do NOT translate, quote, summarize, or reference context history.\n"
    "- If context conflicts with current input, prioritize the current input.\n"
    "- If context is unclear or incomplete, translate conservatively without speculation.\n"
    "\n"
    "Behavioral Guidelines\n"
    "- Optimize output for real-time listening and subtitle readability.\n"
    "- Smooth incomplete or cut-off sentences naturally.\n"
    "- Ensure the final result sounds fluent, native, and effortless in {{to}}.\n"
    "\n"
    "Workflow\n"
    "- Step 1: Read source text ({{from}}) and optional context.\n"
    "- Step 2: Interpret meaning while preserving intent and tone.\n"
    "- Step 3: Refine for fluency and subtitle compatibility in {{to}}.\n"
    "- Result: One clean block of natural, accurate translated text in {{to}}.\n"
    "\n"
    "Initialization\n"
    "Follow all rules strictly and execute tasks exactly as defined.\n";

// ========================
// DEFAULT CONFIGURATION
// ========================
const string DEFAULT_MODEL_NAME = "qwen3.5:27b";

// ========================
// USER CONFIGURATION
// ========================
class Config {
    // Api
    string modelName = DEFAULT_MODEL_NAME;
    string apiKey = "";
    string customEndpoint = "";
    string baseUrl = "http://127.0.0.1:11434";
    // Model
    float temperature = 0.3;
    float topP = 0.9;
    int topK = 40;
    float minP = 0.1;
    float repeatPenalty = 1.1;
    int maxTokens = 2048;
    // Reasoning
    bool enableThinking = false;
    string thinkStrength = "";
    // Context
    bool contextEnabled = true;
    int contextMaxSize = 20;
    int contextCount = 7;
    string contextPrompt = CONTEXT_PROMPT_BASE;

    string systemPrompt = SYSTEM_PROMPT_BASE;
    string userPrompt = USER_PROMPT_BASE;
}

// ========================
// CONTEXT HISTORY
// ========================
class ContextHistory {
    array<string> history;

    void AddEntry(const string &in source, const string &in translation,
                  const string &in srcLang, const string &in dstLang) {
        if (!g_config.contextEnabled || source.empty()) return;
        string entry;
        if (!srcLang.empty()) {
            entry = "[" + srcLang + "] " + source + " -> [" + dstLang + "] " + translation;
        } else {
            entry = "[source] " + source + " -> [" + dstLang + "] " + translation;
        }
        history.insertLast(entry);
        if (history.length() > uint(g_config.contextMaxSize)) {
            history.removeAt(0);
        }
    }

    string GetContext() {
        if (!g_config.contextEnabled || history.length() == 0) return "";
        string historyBlock = "";
        int startIdx = max(0, int(history.length()) - g_config.contextCount);
        for (int i = startIdx; i < int(history.length()); ++i) {
            historyBlock += history[i] + "\n";
        }
        return historyBlock;
    }
}

// ========================
// API COMMUNICATION
// ========================
class Api {
    string chatRoute = "/api/chat";
    string userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
    string contentType = "Content-Type: application/json";
    string ollamaCloudUrl = "https://ollama.com";

    dictionary defaultParams;
    bool ollamaSupportsNativeThinking = false;
    bool modelSupportsThinking = false;
    string modelArchitecture = "";

    void LoadDefaults(const dictionary &in params) { defaultParams = params; }

    dictionary GetActiveParams() {
        dictionary result;
        if (defaultParams.exists("temperature")) result["temperature"] = g_config.temperature;
        if (defaultParams.exists("top_p")) result["top_p"] = g_config.topP;
        if (defaultParams.exists("top_k")) result["top_k"] = g_config.topK;
        if (defaultParams.exists("min_p")) result["min_p"] = g_config.minP;
        if (defaultParams.exists("repeat_penalty")) result["repeat_penalty"] = g_config.repeatPenalty;
        if (defaultParams.exists("max_tokens")) result["max_tokens"] = g_config.maxTokens;
        return result;
    }

    string GetThinkOption() {
        HostPrintUTF8("modelArchitecture: " + modelArchitecture + "\n");

        if (modelArchitecture == "gpt-oss" && !g_config.enableThinking) return "\"low\"";
        if (modelArchitecture != "gpt-oss") return g_config.enableThinking
            ? (g_config.thinkStrength.empty() ? "true" : "\"" + g_config.thinkStrength + "\"")
            : "false";

        return "\"" + (g_config.enableThinking
            ? (g_config.thinkStrength.empty() ? "true" : g_config.thinkStrength)
            : "false") + "\"";
    }

    array<string> GetAvailableModels() {
        string response = HostUrlGetString(g_config.baseUrl + "/api/tags", userAgent, contentType, "");
        if (response.empty()) return array<string>();

        JsonReader reader;
        JsonValue root;
        if (!reader.parse(response, root)) {
            HostPrintUTF8("Failed to parse models list response\n");
            return array<string>();
        }

        JsonValue models = root["models"];
        if (!models.isArray()) return array<string>();

        array<string> result;
        for (int i = 0; i < models.size(); i++) {
            JsonValue model = models[i];
            if (model.isObject() && model["name"].isString()) result.insertLast(model["name"].asString());
        }
        return result;
    }

    string GetModelInfo(const string &in modelName) {
        string response = HostUrlGetString(g_config.baseUrl + "/api/show", userAgent, contentType, "{\"model\":\"" + modelName + "\"}");
        if (response.empty()) return "";

        JsonReader reader;
        JsonValue root;
        if (!reader.parse(response, root)) return "";

        return FormatModelInfo(root);
    }

    string GetVersion() {
        string response = HostUrlGetString(g_config.baseUrl + "/api/version", userAgent, contentType, "");
        if (response.empty()) return "";

        JsonReader reader;
        JsonValue root;
        if (!reader.parse(response, root)) return "";
        return root["version"].asString();
    }

    array<string> GetOpenAIModels() {
        string base = g_config.customEndpoint;
        int chatPos = base.find("/chat/completions");
        int v1Pos = base.find("/v1/");
        if (chatPos != -1) base = base.substr(0, chatPos);
        else if (v1Pos != -1) base = base.substr(0, v1Pos);
        if (base.empty()) return array<string>();
        if (base.substr(base.length() - 1, 1) == "/") base = base.substr(0, base.length() - 1);
        string url = (base.length() >= 3 && base.substr(base.length() - 3, 3) == "/v1")
            ? (base + "/models")
            : (base + "/v1/models");

        string header = BuildHeader();
        string headerLog = header;
        if (!g_config.apiKey.empty()) headerLog.replace(g_config.apiKey, "***");
        HostPrintUTF8("Models list request url   : " + url + "\n");
        HostPrintUTF8("Models list request header: " + headerLog + "\n");

        string response = HostUrlGetString(url, userAgent, header, "");
        if (response.empty()) return array<string>();
        HostPrintUTF8("Models list response size : " + response.length() + "\n");

        JsonReader reader;
        JsonValue root;
        string normalized = NormalizeJsonResponse(response);
        if (!reader.parse(normalized, root)) {
            HostPrintUTF8("Failed to parse OpenAI models list response\n");
            int previewLen = min(512, int(response.length()));
            string preview = response.substr(0, uint(previewLen));
            HostPrintUTF8("OpenAI models raw response (first 512 chars): " + preview + "\n");
            return array<string>();
        }

        JsonValue data = root["data"];
        if (!data.isArray()) return array<string>();

        array<string> result;
        for (int i = 0; i < data.size(); i++) {
            JsonValue model = data[i];
            if (model.isObject() && model["id"].isString()) result.insertLast(model["id"].asString());
        }
        return result;
    }

    bool SupportsNativeThinking() {
        string version = GetVersion();
        return !version.empty() && CompareVersion(version, "0.9.0") >= 0;
    }

    string SendTranslationRequest(const string &in requestData) {
        string url = BuildUrl();
        string header = BuildHeader();

        HostPrintUTF8("request url   : " + url + "\n");
        HostPrintUTF8("request header: " + header + "\n");
        HostPrintUTF8("request data  : " + requestData + "\n");

        return HostUrlGetString(url, userAgent, header, requestData);
    }

    string BuildTranslationRequest(const string &in text, const string &in srcLang, const string &in dstLang) {
        string context = g_config.contextEnabled ? g_contextHistory.GetContext() : "";
        string sysContent = ApplyTemplate(g_config.systemPrompt, text, srcLang, dstLang, context);
        string userContent = ApplyTemplate(g_config.userPrompt, text, srcLang, dstLang, context);
        string escapedSystem = EscapeJsonString(sysContent);
        string escapedUser = EscapeJsonString(userContent);

        string messages = "[{\"role\":\"system\",\"content\":\"" + escapedSystem + "\"},"
            + "{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}]";

        string requestData = "{\"model\":\"" + g_config.modelName + "\",\"messages\":" + messages;
        requestData += BuildOptions();
        if (ollamaSupportsNativeThinking) requestData += ",\"think\":" + GetThinkOption();
        requestData += ",\"stream\":false}";
        return requestData;
    }

    string BuildUrl() {
        if (!g_config.customEndpoint.empty()) return g_config.customEndpoint;
        if (!g_config.apiKey.empty()) return ollamaCloudUrl + chatRoute;
        return g_config.baseUrl + chatRoute;
    }

    string BuildHeader() {
        string header = contentType + "\nAccept: application/json";
        if (!g_config.apiKey.empty()) header += "\nAuthorization: Bearer " + g_config.apiKey;
        return header;
    }

    string BuildOptions() {
        dictionary params = GetActiveParams();
        if (params.getSize() == 0) return "";

        string json = ",\"options\":{";
        array<string> keys = params.getKeys();
        for (uint i = 0; i < keys.length(); i++) {
            string key = keys[i];
            json += "\"" + key + "\":";

            float fVal; int iVal;
            if (params.get(key, fVal)) json += "" + fVal;
            else if (params.get(key, iVal)) json += "" + iVal;
            if (i < keys.length() - 1) json += ",";
        }
        return json + "}";
    }

    string FormatModelInfo(JsonValue &in root) {
        string result = "";

        if (root["parameters"].isString()) {
            string params = root["parameters"].asString();
            if (!params.empty()) {
                result += "Parameters:\n";
                array<string> lines = SplitString(params, "\n");
                for (uint i = 0; i < lines.length(); ++i) {
                    string line = TrimString(lines[i]);
                    if (!line.empty()) result += "  " + line + "\n";
                }
                LoadDefaults(ParseParameterString(params));
            }
        }

        if (root["model_info"].isObject()) {
            JsonValue modelInfo = root["model_info"];
            array<string> keys = modelInfo.getKeys();
            if (keys.length() > 0) {
                result += "Model Info:\n";
                for (uint i = 0; i < keys.length(); ++i) {
                    string key = keys[i];
                    string value = JsonValueToString(modelInfo[key]);
                    result += "  " + key + ": " + value + "\n";
                    if (key == "general.architecture") modelArchitecture = value;
                }
            }
        }

        if (root["capabilities"].isArray()) {
            JsonValue capabilities = root["capabilities"];
            array<string> caps;
            for (int i = 0; i < capabilities.size(); i++) if (capabilities[i].isString()) caps.insertLast(capabilities[i].asString());
            modelSupportsThinking = caps.find("thinking") != -1;
        }

        return result;
    }

    string JsonValueToString(JsonValue &in value) {
        try {
            if (value.isNull()) return "null";
            if (value.isString()) return value.asString();
            if (value.isBool()) return value.asBool() ? "true" : "false";
            if (value.isInt()) return "" + value.asInt();
            if (value.isUInt()) return "" + value.asUInt();
            if (value.isFloat()) return "" + value.asFloat();
            return "(unknown type)";
        } catch {
            return "Error converting JSON to string";
        }
    }

    int CompareVersion(const string &in version1, const string &in version2) {
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
                if (!key.empty() && !value.empty()) result[key] = value;
            }
        }
        return result;
    }
}

// ========================
// GLOBAL INSTANCES
// ========================
Config g_config;
ContextHistory g_contextHistory;
Api g_api;
bool g_isPluginActive = true;

// ========================
// USER CONFIG & AUTH
// ========================
void LoadUserConfig() {
    g_config.modelName = HostLoadString("selected_model_ollama");
    HostPrintUTF8("Loaded model: " + g_config.modelName + "\n");

    g_config.apiKey = HostLoadString("api_key_ollama");
    HostPrintUTF8("Loaded API Key: " + g_config.apiKey + "\n");
    g_config.customEndpoint = HostLoadString("custom_endpoint_ollama");
    if (!g_config.customEndpoint.empty()) {
        HostPrintUTF8("Loaded custom endpoint: " + g_config.customEndpoint + "\n");
    }
}

bool TrySelectModelFromList(const array<string> &in availableModels, const string &in modelName) {
    string selectedLower = modelName; selectedLower.MakeLower();
    for (uint i = 0; i < availableModels.length(); i++) {
        string availableLower = availableModels[i]; availableLower.MakeLower();
        if (selectedLower == availableLower) {
            g_config.modelName = availableModels[i];
            return true;
        }
    }
    return false;
}

bool IsModelValid(const string &in modelName) {
    array<string> availableModels;
    if (g_config.customEndpoint.empty()) {
        availableModels = g_api.GetAvailableModels();
    } else {
        if (g_config.customEndpoint.find("/v1/") != -1
            || g_config.customEndpoint.find("/chat/completions") != -1) return true;
        availableModels = g_api.GetOpenAIModels();
    }
    if (availableModels.length() == 0) return false;

    if (TrySelectModelFromList(availableModels, modelName)) return true;
    if (modelName != DEFAULT_MODEL_NAME && TrySelectModelFromList(availableModels, DEFAULT_MODEL_NAME)) {
        HostPrintUTF8("Model not found, falling back to default: " + DEFAULT_MODEL_NAME + "\n");
        return true;
    }
    return false;
}

// ========================
// LOGIN FLOW
// ========================
void ParseLoginInput(string User, string Pass) {
    g_config.modelName = TrimString(User);
    if (g_config.modelName.empty()) g_config.modelName = DEFAULT_MODEL_NAME;

    string newApiKey = TrimString(Pass);
    if (!newApiKey.empty()) {
        g_config.apiKey = newApiKey;
    }
}

string LoginNativeOllama() {
    array<string> availableModels = g_api.GetAvailableModels();
    if (availableModels.length() == 0) {
        ShowError("Unable to connect to Ollama. Please ensure Ollama is running and has models available.", "Login Failed");
        return "500 Unable to connect to Ollama. Please ensure Ollama is running and has models available.";
    }

    bool valid = IsModelValid(g_config.modelName);
    HostPrintUTF8("Is " + g_config.modelName + " valid: " + (valid ? "true" : "false") + "\n");
    if (!valid) {
        return HandleModelNotFound();
    }
    return "";
}

string LoginCustomEndpoint() {
    if (!IsValidCustomEndpoint(g_config.customEndpoint)) {
        g_isPluginActive = false;
        return "400 Invalid custom endpoint.";
    }
    if (g_config.apiKey.empty()) {
        ShowError("API key is required for custom endpoint.\nEndpoint: " + g_config.customEndpoint, "Login Failed");
        return "401 API key required for custom endpoint.";
    }

    bool openAIEndpoint = g_config.customEndpoint.find("/v1/chat/completions") != -1;
    if (openAIEndpoint) {
        array<string> availableModels = g_api.GetOpenAIModels();
        if (availableModels.length() == 0) {
            ShowError("Unable to connect to custom endpoint or fetch models.\nEndpoint: " + g_config.customEndpoint, "Login Failed");
            return "500 Unable to connect to custom endpoint or fetch models.";
        }
        LogModelList(availableModels);
        bool valid = TrySelectModelFromList(availableModels, g_config.modelName);
        HostPrintUTF8("Is " + g_config.modelName + " valid: " + (valid ? "true" : "false") + "\n");
        if (!valid) {
            return HandleModelNotFound();
        }
        HostPrintUTF8("Using custom OpenAI endpoint: " + g_config.customEndpoint + "\n");
    } else {
        HostPrintUTF8("Using custom endpoint (skipping model validation): " + g_config.customEndpoint + "\n");
    }
    return "";
}

void DetectThinkingSupport() {
    g_api.ollamaSupportsNativeThinking = g_config.customEndpoint.empty()
        ? g_api.SupportsNativeThinking()
        : false;
}

string FetchAndApplyModelInfo() {
    if (g_config.customEndpoint.empty()) {
        string modelInfo = g_api.GetModelInfo(g_config.modelName);
        if (modelInfo.empty()) {
            HostPrintUTF8("Warning: Could not retrieve model information\n");
            ShowError("Unable to retrieve model information for " + g_config.modelName, "Login Warning");
            return "500 Unable to retrieve model information.";
        }
        HostPrintUTF8("Model information retrieved successfully\n" + modelInfo);
    } else {
        HostPrintUTF8("Skipping model info fetch for custom endpoint\n");
    }
    return "";
}

void SaveLoginConfig() {
    HostSaveString("selected_model_ollama", g_config.modelName);
    HostSaveString("custom_endpoint_ollama", g_config.customEndpoint);
    HostSaveString("api_key_ollama", g_config.apiKey);
}

void RunLoginTest() {
    string testSrcLang = "auto";
    string testDstLang = "zh-CN";
    string testText = "Why is the sky blue?";

    HostPrintUTF8("Running login test translation: " + testSrcLang + " -> " + testDstLang + "\n");

    string requestData = g_api.BuildTranslationRequest(testText, testSrcLang, testDstLang);
    string response = g_api.SendTranslationRequest(requestData);

    if (response.empty()) {
        HostPrintUTF8("Login test: translation request failed - no response\n");
        ShowError("Login test translation failed - no response.\nThe plugin is configured but translation may not work.", "Login Test Warning");
        return;
    }

    string translatedText = ExtractTranslatedText(response);
    translatedText = RemoveThinkingTags(translatedText);
    translatedText = TrimString(translatedText);

    if (translatedText.empty()) {
        HostPrintUTF8("Login test: translation returned empty result\n");
        ShowError("Login test translation returned empty result.\nThe plugin is configured but translation may not work.", "Login Test Warning");
        return;
    }

    HostPrintUTF8("Login test completed successfully!\n");
    HostPrintUTF8("  " + testSrcLang + " -> " + testDstLang + "\n");
    HostPrintUTF8("  Input: " + testText + "\n");
    HostPrintUTF8("  Output: " + translatedText + "\n");
}

string ServerLogin(string User, string Pass) {
    ParseLoginInput(User, Pass);

    string error;
    if (g_config.customEndpoint.empty()) {
        error = LoginNativeOllama();
    } else {
        error = LoginCustomEndpoint();
    }
    if (!error.empty()) return error;

    DetectThinkingSupport();

    error = FetchAndApplyModelInfo();
    if (!error.empty()) return error;

    SaveLoginConfig();

    g_isPluginActive = true;
    HostPrintUTF8("Successfully configured Ollama translation plugin\n");
    HostPrintUTF8("Native thinking support: " + (g_api.ollamaSupportsNativeThinking ? "Yes" : "No") + "\n");
    // RunLoginTest();

    return "200 ok";
}

void ServerLogout() {
    HostSaveString("selected_model_ollama", g_config.modelName);
    HostSaveString("custom_endpoint_ollama", g_config.customEndpoint);
    HostSaveString("api_key_ollama", "");
    HostPrintUTF8("Successfully logged out from Ollama translation plugin\n");
}

// ========================
// LANGUAGES
// ========================
array<string> g_supportedLanguages = {
    "", "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca",
    "ceb", "ny", "zh-CN", "zh-TW", "co", "hr", "cs", "da", "nl", "en", "eo", "et",
    "tl", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he",
    "hi", "hmn", "hu", "is", "ig", "id", "ga", "it", "ja", "jw", "kn", "kk", "km",
    "ko", "ku", "ky", "lo", "la", "lv", "lt", "lb", "mk", "ms", "mg", "ml", "mt",
    "mi", "mr", "mn", "my", "ne", "no", "ps", "fa", "pl", "pt", "pa", "ro", "ru",
    "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw",
    "sv", "tg", "ta", "te", "th", "tr", "uk", "ur", "uz", "vi", "cy", "xh", "yi",
    "yo", "zu"
};

array<string> GetSrcLangs() { return g_supportedLanguages; }
array<string> GetDstLangs() { return g_supportedLanguages; }

// ========================
// TRANSLATION FLOW
// ========================
string Translate(string Text, string &in SrcLang, string &in DstLang) {
    if (!g_isPluginActive) return "Plugin is not loaded normally, please check settings";

    if (!IsTargetLanguageValid(DstLang)) {
        HostPrintUTF8("Target language not specified\n");
        ShowError("Target language not specified", "Translation Failed");
        return "";
    }

    string srcLangCode = NormalizeLanguage(SrcLang);
    string requestData = g_api.BuildTranslationRequest(Text, srcLangCode, DstLang);

    string response = g_api.SendTranslationRequest(requestData);
    if (response.empty()) {
        HostPrintUTF8("Translation request failed - no response\n");
        ShowError("Translation request failed - no response", "Translation Failed");
        return "";
    }

    string translatedText = ExtractTranslatedText(response);
    translatedText = RemoveThinkingTags(translatedText);
    translatedText = TrimString(translatedText);
    if (DstLang == "fa" || DstLang == "ar" || DstLang == "he") translatedText = "\u202B" + translatedText;

    g_contextHistory.AddEntry(Text, translatedText, srcLangCode, DstLang);

    SrcLang = "UTF8";
    DstLang = "UTF8";
    return translatedText;
}

string ExtractTranslatedText(const string response) {
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(response, root)) {
        HostPrintUTF8("Failed to parse translation response\n");
        return "";
    }

    HostPrintUTF8("response: " + response + "\n");

    JsonValue message = g_config.customEndpoint.empty() ? root["message"] : root["choices"][0]["message"];
    if (!message.isObject()) {
        HostPrintUTF8("Invalid response format - no message\n");
        return "";
    }

    JsonValue content = message["content"];
    if (!content.isString()) {
        HostPrintUTF8("Invalid response format - no content\n");
        ShowError("Invalid response format - no content", "Translation Failed");
        return "";
    }
    return content.asString();
}

// ========================
// UTILITIES
// ========================

bool IsTargetLanguageValid(const string &in dst) {
    if (dst.empty()) return false;
    string lower = dst;
    lower.MakeLower();
    return lower != "auto";
}

string NormalizeLanguage(const string &in lang) {
    if (lang.empty()) return "";
    string lower = lang;
    lower.MakeLower();
    if (lower == "auto") return "";
    return lang;
}

void ShowError(const string &in message, const string &in title = "Error") {
    HostMessageBox(message, title, 3, 1);
}

string HandleModelNotFound() {
    ShowError("Model not found: " + g_config.modelName, "Login Failed");
    g_isPluginActive = false;
    return "";
}

void LogModelList(const array<string> &in models) {
    if (models.length() == 0) return;
    string output = "Available models (" + models.length() + "):\n";
    for (uint i = 0; i < models.length(); i++) {
        output += "- " + models[i] + "\n";
    }
    HostPrintUTF8(output);
}

bool IsValidCustomEndpoint(const string &in endpoint) {
    if (endpoint.empty()) return false;
    string lower = endpoint;
    lower.MakeLower();
    bool hasScheme = false;
    if (lower.length() >= 7 && lower.substr(0, 7) == "http://") hasScheme = true;
    if (lower.length() >= 8 && lower.substr(0, 8) == "https://") hasScheme = true;
    if (!hasScheme) {
        ShowError("Invalid custom endpoint (missing http/https): " + endpoint, "Login Failed");
        return false;
    }
    return true;
}

int max(int a, int b) { return (a > b) ? a : b; }
int min(int a, int b) { return (a < b) ? a : b; }

string TrimString(const string &in text) {
    if (text.empty()) return "";
    int start = 0;
    int end = int(text.length()) - 1;
    while (start <= end) {
        string ch = text.substr(start, 1);
        if (ch != " " && ch != "\n" && ch != "\r" && ch != "\t") break;
        start++;
    }
    while (end >= start) {
        string ch = text.substr(end, 1);
        if (ch != " " && ch != "\n" && ch != "\r" && ch != "\t") break;
        end--;
    }
    if (start > end) return "";
    return text.substr(uint(start), uint(end - start + 1));
}

string NormalizeJsonResponse(const string &in input) {
    string output = input;
    if (output.length() >= 3 && output.substr(0, 3) == "\xEF\xBB\xBF") {
        output = output.substr(3);
    }
    return TrimString(output);
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
        int openPos = result.find("<think", startPos);
        if (openPos == -1) break;

        int closePos = result.find("</think", openPos);
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

string ApplyTemplate(const string &in tmpl, const string &in text, const string &in from, const string &in to, const string &in context) {
    string result = tmpl;
    string fromVal = from;
    fromVal.MakeLower();
    bool includeFrom = !(fromVal.empty() || fromVal == "auto");

    result.replace("{{text}}", text);
    result.replace("{{text_to_translate}}", text);
    result.replace("{{from}}", includeFrom ? from : "");
    result.replace("{{to}}", to);
    result.replace("{{context}}", context);

    if (g_config.contextEnabled && !TrimString(g_config.contextPrompt).empty() && !TrimString(context).empty()) {
        result.replace("{{context_prompt}}", g_config.contextPrompt);
        result.replace("{{optional_reference_context}}", context);
    } else {
        result.replace("{{context_prompt}}\n\n", "");
        result.replace("{{context_prompt}}\n", "");
        result.replace("{{context_prompt}}", "");
    }

    if (!includeFrom) {
        result.replace(" from  to", " to");
        result.replace("from  to", "to");
        result.replace(" from  ", " ");
        result.replace("from  ", "");
        while (result.find("  ") != -1) {
            result.replace("  ", " ");
        }
    }
    return result;
}
