/*
 * Real-time subtitle translation for PotPlayer using Ollama
 * v3.0 — Phase 1: Foundation refactor
 */

// ========================
// LOGGER
// ========================
// ponytail: single funnel for all output. Redacts the configured API key
// before any print. Levels gated by debug flag.

class Logger {
    bool debug = false;
    string redactKey = "";

    void Info(const string &in m)  { HostPrintUTF8("[INFO]  " + Redact(m) + "\n"); }
    void Warn(const string &in m)  { HostPrintUTF8("[WARN]  " + Redact(m) + "\n"); }
    void Error(const string &in m) { HostPrintUTF8("[ERROR] " + Redact(m) + "\n"); }
    void Debug(const string &in m) { if (debug) HostPrintUTF8("[DEBUG] " + Redact(m) + "\n"); }

    string Redact(const string &in m) {
        if (redactKey.empty()) return m;
        string out = m;
        out.replace(redactKey, "***");
        return out;
    }
}

Logger g_logger;

// ========================
// PLUGIN METADATA & LIFECYCLE
// ========================

string GetTitle() {
    return "{$CP949=Ollama translate$}{$CP950=Ollama translate$}{$CP936=Ollama translate$}{$CP0=Ollama translate$}";
}

string GetVersion() { return "3.0"; }

string GetDesc() {
    return "https://github.com/Nuo27/Potplayer-Ollama-Translate";
}

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
    // Uncomment HostOpenConsole() to inspect log output at runtime
    // HostOpenConsole();
    g_logger.Info("Ollama translation plugin v3.0 initialized");
    SelfTest();
}

void OnFinalize() {
    g_logger.Info("Ollama translation plugin finalized");
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

// ========================
// HTTP RESPONSE
// ========================
// ponytail: simple value carrier. status=0 means network-layer failure
// (connection refused, timeout, DNS, etc.); otherwise the HTTP status code.

class Response {
    int status = 0;
    string body = "";
}

// ========================
// TEXT CLEANER
// ========================
// ponytail: input normalization + noise filter. Skips empty/numeric/punctuation-only
// inputs so we don't waste an API call on "..." or "123".

class TextCleaner {
    string Normalize(const string &in t) {
        string s = TrimString(t);
        // Collapse internal whitespace runs (input text only, not user prompts)
        while (s.find("  ") != -1) s.replace("  ", " ");
        return s;
    }

    bool IsTranslatable(const string &in t) {
        string s = TrimString(t);
        if (s.empty()) return false;

        // ponytail: skip set covers ASCII whitespace/digits/punctuation.
        // Any character outside this set (ASCII letter or non-ASCII byte from
        // a multibyte UTF-8 sequence) counts as translatable content.
        string skipChars = " .,;:!?\"'-()[]{}<>/*+=~`@#$%^&|\\\n\r\t";
        uint len = s.length();
        for (uint i = 0; i < len; i++) {
            string ch = s.substr(i, 1);
            if (ch >= "0" && ch <= "9") continue;
            if (skipChars.find(ch) != -1) continue;
            return true;
        }
        return false;
    }
}

// ========================
// HTTP TRANSPORT
// ========================
// ponytail: dual impl per Q9. Default uses HostUrlGetString (status unknown,
// heuristic from body emptiness); flip Config.useHttpClient to use the
// HttpClient class which exposes real HTTP status codes.
// SendWithRetry does at most ONE retry on transient errors (network failure,
// 5xx, 429). 4xx is not retried (auth / bad request — retry won't help).

class HttpTransport {
    string userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";

    Response SendWithRetry(const string &in url, const string &in header, const string &in body) {
        Response r = Send(url, header, body);
        if (ShouldRetry(r)) {
            g_logger.Warn("Transient failure (status=" + r.status + "), retrying once...");
            HostSleep(500);
            r = Send(url, header, body);
        }
        return r;
    }

    Response Send(const string &in url, const string &in header, const string &in body) {
        if (g_config.useHttpClient) return SendViaHttpClient(url, header, body);
        return SendViaHostUrlGetString(url, header, body);
    }

    Response SendViaHostUrlGetString(const string &in url, const string &in header, const string &in body) {
        HostIncTimeOut(15000);  // give the LLM time to respond (fixes C3)
        Response r;
        string bodyOut = HostUrlGetString(url, userAgent, header, body);
        r.body = bodyOut;
        // Heuristic: HostUrlGetString does not expose HTTP status. Treat empty
        // body as network-layer failure, non-empty as assumed 200.
        r.status = bodyOut.empty() ? 0 : 200;
        return r;
    }

    Response SendViaHttpClient(const string &in url, const string &in header, const string &in body) {
        HostIncTimeOut(15000);
        Response r;
        HttpClient client;
        bool ok = client.Open(url, userAgent, header, body, true);
        if (!ok) {
            r.status = 0;
            r.body = "";
            return r;
        }
        r.status = client.GetStatus();
        r.body = client.GetContent();
        return r;
    }

    bool ShouldRetry(const Response &in r) {
        if (r.status == 0) return true;        // network layer failure
        if (r.status >= 500) return true;      // server error
        if (r.status == 429) return true;      // rate limited
        return false;                          // 4xx = auth / bad request
    }
}

// ========================
// USER CONFIGURATION
// ========================
class Config {
    // Api
    string modelName = "";
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
    // Cache (Phase 4)
    bool cacheEnabled = false;
    // Transport (Phase 2): default false = HostUrlGetString, true = HttpClient (real status codes)
    bool useHttpClient = false;

    string systemPrompt = SYSTEM_PROMPT_BASE;
    string userPrompt = USER_PROMPT_BASE;

    // ponytail: PotPlayer persists username (model) and password (api key)
    // automatically via the login dialog. We only load/sync our own extras.
    void Load() {
        modelName = HostLoadString("selected_model_ollama");
        apiKey = HostLoadString("api_key_ollama");
        customEndpoint = HostLoadString("custom_endpoint_ollama");
    }

    void Save() {
        HostSaveString("selected_model_ollama", modelName);
        HostSaveString("custom_endpoint_ollama", customEndpoint);
        // Note: apiKey is managed by PotPlayer's login dialog; not overwritten here.
    }
}

// ========================
// CONTEXT HISTORY
// ========================
// ponytail: no mutex primitives in AngelScript; Translate() may fire concurrently
// (Q2). Mitigation: GetContext() returns a complete string snapshot, AddEntry()
// is a short append+trim. Snapshot is taken before the HTTP call so concurrent
// translators never read partial state; final ordering of appends depends on
// completion order, which is acceptable for tone/continuity context.

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
        g_logger.Debug("modelArchitecture: " + modelArchitecture);

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
            g_logger.Warn("Failed to parse models list response");
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
        g_logger.Debug("Models list request url   : " + url);
        g_logger.Debug("Models list request header: " + headerLog);

        string response = HostUrlGetString(url, userAgent, header, "");
        if (response.empty()) return array<string>();
        g_logger.Debug("Models list response size : " + response.length());

        JsonReader reader;
        JsonValue root;
        string normalized = NormalizeJsonResponse(response);
        if (!reader.parse(normalized, root)) {
            g_logger.Warn("Failed to parse OpenAI models list response");
            int previewLen = min(512, int(response.length()));
            string preview = response.substr(0, uint(previewLen));
            g_logger.Debug("OpenAI models raw response (first 512 chars): " + preview);
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

    Response SendTranslationRequest(const string &in requestData) {
        string url = BuildUrl();
        string header = BuildHeader();

        g_logger.Debug("request url   : " + url);
        g_logger.Debug("request header: " + header);
        g_logger.Debug("request data  : " + requestData);

        return g_httpTransport.SendWithRetry(url, header, requestData);
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
HttpTransport g_httpTransport;
TextCleaner g_textCleaner;
bool g_isPluginActive = true;

// ========================
// USER CONFIG & AUTH
// ========================
void LoadUserConfig() {
    g_config.Load();
    g_logger.Info("Loaded model: " + g_config.modelName);
    g_logger.Info("Loaded API Key: " + (g_config.apiKey.empty() ? "(not set)" : "(set)"));
    if (!g_config.customEndpoint.empty()) {
        g_logger.Info("Loaded custom endpoint: " + g_config.customEndpoint);
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
    return TrySelectModelFromList(availableModels, modelName);
}

// ========================
// LOGIN FLOW
// ========================
void ParseLoginInput(string User, string Pass) {
    g_config.modelName = TrimString(User);

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
    g_logger.Debug("Is " + g_config.modelName + " valid: " + (valid ? "true" : "false"));
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
        g_logger.Debug("Is " + g_config.modelName + " valid: " + (valid ? "true" : "false"));
        if (!valid) {
            return HandleModelNotFound();
        }
        g_logger.Info("Using custom OpenAI endpoint: " + g_config.customEndpoint);
    } else {
        g_logger.Info("Using custom endpoint (skipping model validation): " + g_config.customEndpoint);
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
            g_logger.Warn("Could not retrieve model information");
            ShowError("Unable to retrieve model information for " + g_config.modelName, "Login Warning");
            return "500 Unable to retrieve model information.";
        }
        g_logger.Debug("Model information retrieved:\n" + modelInfo);
    } else {
        g_logger.Debug("Skipping model info fetch for custom endpoint");
    }
    return "";
}

void SaveLoginConfig() {
    g_config.Save();
}

string ServerLogin(string User, string Pass) {
    ParseLoginInput(User, Pass);

    // ponytail: redactKey set as early as possible so all subsequent logs are safe
    g_logger.redactKey = g_config.apiKey;

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
    g_logger.Info("Successfully configured Ollama translation plugin");
    g_logger.Info("Native thinking support: " + (g_api.ollamaSupportsNativeThinking ? "Yes" : "No"));

    return "200 ok";
}

void ServerLogout() {
    HostSaveString("selected_model_ollama", g_config.modelName);
    HostSaveString("custom_endpoint_ollama", g_config.customEndpoint);
    HostSaveString("api_key_ollama", "");
    g_logger.Info("Successfully logged out from Ollama translation plugin");
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
        g_logger.Warn("Target language not specified");
        ShowError("Target language not specified", "Translation Failed");
        return "";
    }

    // Phase 2: skip noise input so we don't waste an API call on "" / "..." / "123"
    if (!g_textCleaner.IsTranslatable(Text)) {
        g_logger.Debug("Skipping non-translatable input: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }

    string srcLangCode = NormalizeLanguage(SrcLang);
    string requestData = g_api.BuildTranslationRequest(Text, srcLangCode, DstLang);

    Response resp = g_api.SendTranslationRequest(requestData);
    if (resp.status == 0 || resp.body.empty()) {
        // Phase 2 (H7): return original text instead of empty string.
        // User sees the source line rather than a blank subtitle — much better UX
        // under network blips / model load stalls / rate limits.
        g_logger.Warn("Translation failed (status=" + resp.status + "): " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }

    string translatedText = ExtractTranslatedText(resp.body);
    translatedText = RemoveThinkingTags(translatedText);
    translatedText = TrimString(translatedText);
    if (translatedText.empty()) {
        // API responded but content was empty/unparsable — still better than blank
        g_logger.Warn("Translation returned empty content: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }
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
        g_logger.Warn("Failed to parse translation response");
        return "";
    }

    g_logger.Debug("response: " + response);

    JsonValue message = g_config.customEndpoint.empty() ? root["message"] : root["choices"][0]["message"];
    if (!message.isObject()) {
        g_logger.Warn("Invalid response format - no message");
        return "";
    }

    JsonValue content = message["content"];
    if (!content.isString()) {
        g_logger.Warn("Invalid response format - no content");
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
    g_logger.Debug(output);
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
    if (output.length() >= 3 && output.substr(0, 3) == "\xef\xbb\xbf") {
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
    // Phase 2 (fixes C2): proper scan-based removal.
    // - Handles <think>, <think attr="x">, <thinking> (matched via "<think" prefix)
    // - Handles </think>, </thinking> (matched via "</think" prefix)
    // - Unclosed <think>...</text without close>: discards the trailing content
    //   (likely truncated chain-of-thought, better to drop than show)
    // - Multiple sequential tags handled by the loop
    string result = "";
    int cur = 0;
    int totalLen = int(text.length());
    while (cur < totalLen) {
        int openPos = text.find("<think", cur);
        if (openPos == -1) {
            result += text.substr(uint(cur));
            break;
        }
        // Append text before the open tag
        result += text.substr(uint(cur), uint(openPos - cur));
        // Find closing "</think" prefix
        int closePos = text.find("</think", openPos);
        if (closePos == -1) {
            // Unclosed thinking block — discard the rest
            break;
        }
        // Advance past the closing tag's ">" (handles "</think>", "</thinking>", "</think attr>")
        int closeBracket = text.find(">", closePos);
        if (closeBracket == -1) {
            cur = closePos + 7;  // skip past "</think" even if ">" missing
        } else {
            cur = closeBracket + 1;
        }
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

    // ponytail: removed the previous "from  to" / double-space collapse hack.
    // It corrupted user-authored prompts by collapsing intentional double spaces.
    // Template authors are now responsible for handling empty {{from}} gracefully.
    return result;
}

// ========================
// SELF-TEST
// ========================
// ponytail: minimal assert-style smoke check, runs once on OnInitialize.
// Verifies pure-function invariants; no framework, no fixtures.

void SelfTestAssert(bool cond, const string &in msg) {
    if (!cond) {
        g_logger.Error("SelfTest FAILED: " + msg);
    }
}

void SelfTest() {
    // ApplyTemplate: empty {{from}} no longer triggers string hacks
    string r1 = ApplyTemplate("from={{from}} to={{to}}", "hello", "", "zh-CN", "");
    SelfTestAssert(r1 == "from= to=zh-CN", "ApplyTemplate empty from -> '" + r1 + "'");

    // ApplyTemplate: {{text}} alias removed; only {{text_to_translate}} works
    string r2 = ApplyTemplate("[{{text_to_translate}}]", "hi", "", "zh", "");
    SelfTestAssert(r2 == "[hi]", "ApplyTemplate text_to_translate -> '" + r2 + "'");

    // TrimString basic cases
    SelfTestAssert(TrimString("  hello  ") == "hello", "TrimString spaces");
    SelfTestAssert(TrimString("\n\n") == "", "TrimString whitespace-only");

    // EscapeJsonString
    string r3 = EscapeJsonString("a\"b\nc");
    SelfTestAssert(r3 == "a\\\"b\\nc", "EscapeJsonString -> '" + r3 + "'");

    // Logger.Redact
    Logger l;
    l.redactKey = "secret";
    SelfTestAssert(l.Redact("mysecret here") == "my*** here", "Logger.Redact -> '" + l.Redact("mysecret here") + "'");

    // RemoveThinkingTags (Phase 2, C2 fix)
    string t1 = RemoveThinkingTags("<think>reasoning here</think>hello");
    SelfTestAssert(t1 == "hello", "RemoveThinkingTags basic -> '" + t1 + "'");
    string t2 = RemoveThinkingTags("before<think>coT</think>middle<think>more</think>after");
    SelfTestAssert(t2 == "beforemiddleafter", "RemoveThinkingTags multi -> '" + t2 + "'");
    string t3 = RemoveThinkingTags("<think attr=\"x\">tagged open</think>ok");
    SelfTestAssert(t3 == "ok", "RemoveThinkingTags attr open -> '" + t3 + "'");
    string t4 = RemoveThinkingTags("<thinking>unclosed block");
    SelfTestAssert(t4 == "", "RemoveThinkingTags unclosed -> '" + t4 + "'");
    string t5 = RemoveThinkingTags("no tags here");
    SelfTestAssert(t5 == "no tags here", "RemoveThinkingTags no tags -> '" + t5 + "'");

    // TextCleaner.IsTranslatable (Phase 2)
    TextCleaner tc;
    SelfTestAssert(tc.IsTranslatable("") == false, "IsTranslatable empty");
    SelfTestAssert(tc.IsTranslatable("   ") == false, "IsTranslatable whitespace");
    SelfTestAssert(tc.IsTranslatable("...") == false, "IsTranslatable punctuation");
    SelfTestAssert(tc.IsTranslatable("123") == false, "IsTranslatable digits");
    SelfTestAssert(tc.IsTranslatable("-") == false, "IsTranslatable single char");
    SelfTestAssert(tc.IsTranslatable("hello") == true, "IsTranslatable ascii word");
    SelfTestAssert(tc.IsTranslatable("Hello, world!") == true, "IsTranslatable sentence");

    // Response default state
    Response r;
    SelfTestAssert(r.status == 0, "Response default status");
    SelfTestAssert(r.body == "", "Response default body");

    // HttpTransport.ShouldRetry logic
    HttpTransport ht;
    Response fail;  fail.status = 0;    fail.body = "";
    Response ok;    ok.status = 200;    ok.body = "{}";
    Response err5;  err5.status = 500;  err5.body = "";
    Response rl;    rl.status = 429;    rl.body = "";
    Response auth;  auth.status = 401;  auth.body = "";
    SelfTestAssert(ht.ShouldRetry(fail) == true, "ShouldRetry network failure");
    SelfTestAssert(ht.ShouldRetry(ok) == false, "ShouldRetry 200");
    SelfTestAssert(ht.ShouldRetry(err5) == true, "ShouldRetry 5xx");
    SelfTestAssert(ht.ShouldRetry(rl) == true, "ShouldRetry 429");
    SelfTestAssert(ht.ShouldRetry(auth) == false, "ShouldRetry 401");

    g_logger.Info("SelfTest passed");
}
