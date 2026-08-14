/*
 * real-time subtitle translation for potplayer
 */

// ========================
// user settings
// ========================
// edit below to change model, endpoint, prompts, and runtime behavior.
// modelName and apiKey are entered via the potplayer login dialog.
// all other fields require editing this file; defaults target local ollama.
// restart potplayer after any edit to this file.

// ---- prompts ----
// placeholders: {{from}}, {{to}}, {{text_to_translate}},
//               {{context}}, {{context_prompt}}, {{optional_reference_context}}
// tweak to change translation style or add domain instructions.
// check prompts.md / prompts_EN.md for examples.

const string SYSTEM_PROMPT_BASE =
"You are a real-time subtitle translator.\n"
"Translate the user text from {{from}} to {{to}}.\n"
"\n"
"Rules:\n"
"- Output only the translation in {{to}}. No explanation.\n"
"- Preserve names, numbers, code, and identifiers as-is.\n"
"- Adapt phrasing for native fluency, do not translate word-by-word.\n"
"- If input is incomplete, translate what is given.\n"
"\n"
"If context is provided, use it only for tone and reference.\n"
"Never translate or repeat the context.\n";

const string USER_PROMPT_BASE =
"{{context_prompt}}"
"Translate the following text in <text> to {{to}}:\n"
"\n"
"<text>\n"
"{{text_to_translate}}\n"
"</text>\n";

const string CONTEXT_PROMPT_BASE =
"Reference context (do NOT translate):\n"
"{{optional_reference_context}}\n"
"\n";

const string USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";

// ---- runtime config ----
// modelName + apiKey are saved by potplayer login dialog
// apiFormat + customEndpoint require editing this file
class Config {
    // from potplayer login ui
    string modelName = "";
    string apiKey = "";
    // source-edited only
    string apiFormat = "ollama";   // ollama | rest | openai | anthropic
    string customEndpoint = "";
    string baseUrl = "http://127.0.0.1:11434";
    // translation quality
    float temperature = 0.3;
    float topP = 0.9;
    // context override; smaller = faster load, less vram; 0 = model default
    int contextLength = 4096;
    // output token limit; ollama path does not send this
    int maxTokens = 512;
    // watchdog budget per host call (Translate/ServerLogin); covers one
    // request attempt plus at most one network-level retry and its sleep
    int requestTimeoutMs = 60000;
    // reasoning
    bool enableThinking = false;
    string thinkStrength = "";   // empty or low/medium/high
    // context
    bool contextEnabled = true;
    int contextCount = 7;
    string contextPrompt = CONTEXT_PROMPT_BASE;
    // memory cache cap
    int cacheMaxEntries = 500;

    string systemPrompt = SYSTEM_PROMPT_BASE;
    string userPrompt = USER_PROMPT_BASE;

    void Load() {
        modelName = HostLoadString("selected_model_ollama");
        apiKey = HostLoadString("api_key_ollama");
        customEndpoint = HostLoadString("custom_endpoint_ollama");
    }

    void Save() {
        HostSaveString("selected_model_ollama", modelName);
        HostSaveString("custom_endpoint_ollama", customEndpoint);
    }
}

// ========================
// logger
// ========================

class Logger {
    bool debug = false;
    string redactKey = "";

    void Info(const string &in m)  { HostPrintUTF8("[INFO]  " + Redact(m) + "\n"); }
    void Warn(const string &in m)  { HostPrintUTF8("[WARN]  " + Redact(m) + "\n"); }
    void Error(const string &in m) { HostPrintUTF8("[ERROR] " + Redact(m) + "\n"); }
    void Debug(const string &in m) { if (debug) HostPrintUTF8("[DEBUG] " + Redact(m) + "\n"); }

    string Redact(const string &in m) {
        if (redactKey.empty()) return m;
        string result = m;
        result.replace(redactKey, "***");
        return result;
    }
}

Logger g_logger;

// ========================
// plugin metadata
// ========================

string GetTitle() {
    return "{$CP949=Ollama translate$}{$CP950=Ollama translate$}{$CP936=Ollama translate$}{$CP0=Ollama translate$}";
}

string GetVersion() { return "3.1"; }

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
    return "{$CP949=API Key:$}{$CP950=API Key:$}${$CP936=API Key:$}{$CP0=API Key:$}";
}

void OnInitialize() {
    // Uncomment HostOpenConsole() to inspect log output at runtime
    // HostOpenConsole();
    g_logger.Info("Ollama translation plugin initialized");
}

void OnFinalize() {
    g_logger.Info("Ollama translation plugin finalized");
}

// ========================
// provider info
// ========================
// supported formats: ollama, rest, openai, anthropic
// customEndpoint overrides per-format default url

class ProviderInfo {
    string kind;         // ollama | rest | openai | anthropic
    string chatUrl;      // full url for chat completion
    string tagsUrl;      // full url for model list
    bool needsAuth;      // include any auth header
    bool authIsBearer;   // true: bearer; false: x-api-key
    string name;         // human-readable, for logging
}

// strip trailing slashes, then append the format's chat suffix
// unless the url already contains it
string ResolveChatEndpoint(const string &in raw, const string &in kind) {
    string url = TrimString(raw);
    if (url.empty()) return "";
    while (url.length() > 0 && url.substr(url.length() - 1, 1) == "/") {
        url = url.substr(0, url.length() - 1);
    }

    if (kind == "ollama") {
        if (url.find("/api/chat") != -1) return url;
        return url + "/api/chat";
    }
    if (kind == "rest") {
        if (url.find("/api/v1/chat") != -1) return url;
        return url + "/api/v1/chat";
    }
    if (kind == "openai") {
        if (url.find("/chat/completions") != -1) return url;
        if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
            return url + "/chat/completions";
        }
        return url + "/v1/chat/completions";
    }
    // anthropic
    if (url.find("/messages") != -1) return url;
    if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
        return url + "/messages";
    }
    return url + "/v1/messages";
}

// chat and models endpoints are paired per format
string ModelsUrlFromChatUrl(const string &in chatUrl, const string &in kind) {
    if (kind == "anthropic") return "";  // no list endpoint
    string chatMarker = (kind == "ollama") ? "/api/chat"
                      : (kind == "rest") ? "/api/v1/chat"
                      : "/chat/completions";
    string modelsMarker = (kind == "ollama") ? "/api/tags"
                        : (kind == "rest") ? "/api/v1/models"
                        : "/models";
    string base = chatUrl;
    int pos = base.find(chatMarker);
    if (pos != -1) base = base.substr(0, uint(pos));
    return base + modelsMarker;
}

// shape determined by config.apiformat
ProviderInfo DetectProvider() {
    ProviderInfo p;
    p.kind = g_config.apiFormat;

    if (p.kind == "ollama") {
        if (g_config.apiKey.empty()) {
            p.chatUrl = g_config.baseUrl + "/api/chat";
            p.tagsUrl = g_config.baseUrl + "/api/tags";
            p.needsAuth = false;
        } else {
            p.chatUrl = "https://ollama.com/api/chat";
            p.tagsUrl = "https://ollama.com/api/tags";
            p.needsAuth = true;
        }
        p.authIsBearer = true;
        p.name = g_config.apiKey.empty() ? "Ollama Local" : "Ollama Cloud";
    } else if (p.kind == "rest") {
        p.chatUrl = "http://127.0.0.1:1234/api/v1/chat";
        p.tagsUrl = "http://127.0.0.1:1234/api/v1/models";
        p.needsAuth = !g_config.apiKey.empty();
        p.authIsBearer = true;
        p.name = "LM Studio REST";
    } else if (p.kind == "openai") {
        p.chatUrl = "http://127.0.0.1:1234/v1/chat/completions";
        p.tagsUrl = "http://127.0.0.1:1234/v1/models";
        p.needsAuth = !g_config.apiKey.empty();
        p.authIsBearer = true;
        p.name = "OpenAI-compat";
    } else if (p.kind == "anthropic") {
        p.chatUrl = "http://127.0.0.1:1234/v1/messages";
        p.tagsUrl = "";  // no list endpoint
        p.needsAuth = !g_config.apiKey.empty();
        p.authIsBearer = false;  // x-api-key, not bearer
        p.name = "Anthropic-compat";
    } else {
        // unknown format: fall back to ollama to avoid lockout
        g_logger.Warn("Unknown apiFormat '" + p.kind + "', defaulting to ollama");
        p.kind = "ollama";
        p.chatUrl = g_config.baseUrl + "/api/chat";
        p.tagsUrl = g_config.baseUrl + "/api/tags";
        p.needsAuth = false;
        p.authIsBearer = true;
        p.name = "Ollama Local (fallback)";
    }

    if (!g_config.customEndpoint.empty()) {
        p.chatUrl = ResolveChatEndpoint(g_config.customEndpoint, p.kind);
        if (!p.tagsUrl.empty()) {
            p.tagsUrl = ModelsUrlFromChatUrl(p.chatUrl, p.kind);
        }
    }

    return p;
}

// ========================
// http transport
// ========================

class Response {
    int status = 0;
    string body = "";
}

Response DoSend(const string &in url, const string &in header, const string &in body, int timeoutMs = -1) {
    HostIncTimeOut(timeoutMs < 0 ? g_config.requestTimeoutMs : timeoutMs);
    Response r;
    HttpClient client;
    if (!client.Open(url, USER_AGENT, header, body, true)) {
        r.status = 0;
        r.body = "";
        return r;
    }
    r.status = client.GetStatus();
    r.body = client.GetContent();
    return r;
}

Response SendRequest(const string &in url, const string &in header, const string &in body) {
    uint started = HostGetTickCount();
    Response r = DoSend(url, header, body);
    // status 0 = no usable HTTP response (dns/connect/send failure);
    // deterministic API errors (4xx/5xx) are final and not retried
    if (r.status != 0) return r;

    int64 budgetLeft = int64(g_config.requestTimeoutMs) - int64(HostGetTickCount() - started) - 500;
    if (budgetLeft <= 0) {
        g_logger.Warn("Network failure (status=0), timeout budget exhausted, skip retry");
        return r;
    }
    g_logger.Warn("Network failure (status=0), retrying once...");
    HostSleep(500);
    // top up only the unused remainder so attempt + sleep + retry fit one budget
    HostIncTimeOut(int(budgetLeft));
    r = DoSend(url, header, body, 0);
    return r;
}

// ========================
// context history
// ========================
// capped at contextCount; the last entries are the prompt context

array<string> g_history;

void AddHistoryEntry(const string &in source, const string &in translation) {
    if (!g_config.contextEnabled || source.empty()) return;
    g_history.insertLast(source + " ⇒ " + translation);
    if (g_history.length() > uint(g_config.contextCount)) {
        g_history.removeAt(0);
    }
}

string GetHistoryContext() {
    if (!g_config.contextEnabled || g_history.length() == 0) return "";
    string block = "";
    for (uint i = 0; i < g_history.length(); i++) {
        block += g_history[i] + "\n";
    }
    return block;
}

// ========================
// translation cache (memory only, lru)
// ========================

dictionary g_cacheMem;
array<string> g_cacheLru;

string CacheKey(const string &in text, const string &in src, const string &in dst, const string &in model) {
    return HostHashSHA256(text + "|" + src + "|" + dst + "|" + model);
}

bool CacheTryGet(const string &in key, string &out val) {
    if (g_cacheMem.exists(key)) {
        val = string(g_cacheMem[key]);
        return true;
    }
    return false;
}

void CacheSet(const string &in key, const string &in val) {
    if (g_cacheMem.exists(key)) {
        g_cacheMem[key] = val;
        return;
    }
    if (int(g_cacheMem.getSize()) >= g_config.cacheMaxEntries && g_cacheLru.length() > 0) {
        g_cacheMem.delete(g_cacheLru[0]);
        g_cacheLru.removeAt(0);
    }
    g_cacheMem[key] = val;
    g_cacheLru.insertLast(key);
}

// ========================
// request builders
// ========================

string OllamaThinkValue() {
    if (!g_config.enableThinking) return "false";
    if (g_config.thinkStrength.empty()) return "true";
    return "\"" + g_config.thinkStrength + "\"";
}

string BuildOllamaRequest(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
    string messages = "[{\"role\":\"system\",\"content\":\"" + EscapeJsonString(sysContent)
         + "\"},{\"role\":\"user\",\"content\":\"" + EscapeJsonString(userContent) + "\"}]";
    string req = "{\"model\":\"" + escapedModel + "\",\"messages\":" + messages;

    // options: num_ctx (when set) + num_predict (when set) + temperature + top_p
    if (g_config.contextLength > 0) {
        req += ",\"options\":{\"num_ctx\":" + g_config.contextLength
             + (g_config.maxTokens > 0 ? ",\"num_predict\":" + g_config.maxTokens : "")
             + ",\"temperature\":" + g_config.temperature
             + ",\"top_p\":" + g_config.topP + "}";
    } else {
        req += ",\"options\":{"
             + (g_config.maxTokens > 0 ? "\"num_predict\":" + g_config.maxTokens + "," : "")
             + "\"temperature\":" + g_config.temperature
             + ",\"top_p\":" + g_config.topP + "}";
    }

    // always emit think to avoid qwen3 default-think timeout
    req += ",\"think\":" + OllamaThinkValue();
    // local only: keep the model resident so a playback pause does not
    // force a model reload (and a watchdog timeout) on the next subtitle
    if (g_config.apiKey.empty()) {
        req += ",\"keep_alive\":\"30m\"";
    }
    req += ",\"stream\":false}";
    return req;
}

string RestReasoningValue() {
    if (!g_config.enableThinking) return "off";
    if (g_config.thinkStrength.empty()) return "on";
    // caller wraps this in quotes; return the bare value so the JSON stays valid
    return g_config.thinkStrength;
}

// lms rest v1: input + system_prompt top-level + flat fields
string BuildRestRequest(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
    string req = "{\"model\":\"" + escapedModel
         + "\",\"input\":\"" + EscapeJsonString(userContent)
         + "\",\"system_prompt\":\"" + EscapeJsonString(sysContent)
         + "\",\"temperature\":" + g_config.temperature
         + ",\"top_p\":" + g_config.topP
         + ",\"max_output_tokens\":" + g_config.maxTokens;
    if (g_config.contextLength > 0) {
        req += ",\"context_length\":" + g_config.contextLength;
    }
    req += ",\"reasoning\":\"" + RestReasoningValue() + "\"";
    req += ",\"stream\":false}";
    return req;
}

string OpenAIReasoningEffortValue() {
    if (!g_config.enableThinking) return "none";
    if (g_config.thinkStrength.empty()) return "medium";
    return g_config.thinkStrength;
}

// openai: messages array + top-level params, max_completion_tokens
string BuildOpenAIRequest(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
    string messages = "[{\"role\":\"system\",\"content\":\"" + EscapeJsonString(sysContent)
         + "\"},{\"role\":\"user\",\"content\":\"" + EscapeJsonString(userContent) + "\"}]";
    return "{\"model\":\"" + escapedModel + "\",\"messages\":" + messages
         + ",\"max_completion_tokens\":" + g_config.maxTokens
         + ",\"temperature\":" + g_config.temperature
         + ",\"top_p\":" + g_config.topP
         + ",\"reasoning_effort\":\"" + OpenAIReasoningEffortValue() + "\""
         + ",\"stream\":false}";
}

string AnthropicThinkingValue() {
    if (!g_config.enableThinking) return "{\"type\":\"disabled\"}";
    // budget_tokens required when enabled; map strength to budgets
    int budget = g_config.contextLength / 2;
    if (g_config.thinkStrength == "low") budget = 1024;
    else if (g_config.thinkStrength == "medium") budget = 2048;
    else if (g_config.thinkStrength == "high") budget = 4096;
    return "{\"type\":\"enabled\",\"budget_tokens\":" + budget + "}";
}

// anthropic: system top-level, max_tokens required
string BuildAnthropicRequest(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
    return "{\"model\":\"" + escapedModel
         + "\",\"system\":\"" + EscapeJsonString(sysContent)
         + "\",\"max_tokens\":" + g_config.maxTokens
         + ",\"messages\":[{\"role\":\"user\",\"content\":\""
         + EscapeJsonString(userContent) + "\"}]"
         + ",\"temperature\":" + g_config.temperature
         + ",\"thinking\":" + AnthropicThinkingValue()
         + "}";
}

// ========================
// response parsers
// ========================

string ExtractOllamaText(const string &in body) {
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(body, root)) return "";
    JsonValue msg = root["message"];
    if (!msg.isObject()) return "";
    JsonValue content = msg["content"];
    if (!content.isString()) return "";
    return content.asString();
}

// lms rest: find first output[] item with type=="message"
string ExtractRestText(const string &in body) {
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(body, root)) return "";
    JsonValue output = root["output"];
    if (!output.isArray()) return "";
    for (int i = 0; i < output.size(); i++) {
        JsonValue item = output[i];
        if (item.isObject() && item["type"].isString()
            && item["type"].asString() == "message") {
            JsonValue content = item["content"];
            if (content.isString()) return content.asString();
        }
    }
    return "";
}

string ExtractOpenAIText(const string &in body) {
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(body, root)) return "";
    JsonValue choices = root["choices"];
    if (!choices.isArray() || choices.size() == 0) return "";
    JsonValue msg = choices[0]["message"];
    if (!msg.isObject()) return "";
    JsonValue content = msg["content"];
    if (!content.isString()) return "";
    return content.asString();
}

// anthropic: find first content[] item with type=="text"
string ExtractAnthropicText(const string &in body) {
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(body, root)) return "";
    JsonValue content = root["content"];
    if (!content.isArray() || content.size() == 0) return "";
    for (int i = 0; i < content.size(); i++) {
        JsonValue item = content[i];
        if (item.isObject() && item["type"].isString()
            && item["type"].asString() == "text") {
            JsonValue text = item["text"];
            if (text.isString()) return text.asString();
        }
    }
    return "";
}

// ========================
// globals
// ========================
Config g_config;
ProviderInfo g_provider;
bool g_isPluginActive = true;

// ========================
// request assembly & send
// ========================

string BuildHeader() {
    string header = "Content-Type: application/json\nAccept: application/json";
    if (g_provider.needsAuth && !g_config.apiKey.empty()) {
        if (g_provider.authIsBearer) {
            header += "\nAuthorization: Bearer " + g_config.apiKey;
        } else {
            // anthropic: x-api-key + required version
            header += "\nx-api-key: " + g_config.apiKey
                   + "\nanthropic-version: 2023-06-01";
        }
    }
    return header;
}

string BuildTranslationRequest(const string &in text, const string &in srcLang, const string &in dstLang) {
    string context = g_config.contextEnabled ? GetHistoryContext() : "";
    string sysContent = ApplyTemplate(g_config.systemPrompt, text, srcLang, dstLang, context);
    string userContent = ApplyTemplate(g_config.userPrompt, text, srcLang, dstLang, context);
    string escapedModel = EscapeJsonString(g_config.modelName);

    if (g_provider.kind == "rest") {
        return BuildRestRequest(escapedModel, sysContent, userContent);
    } else if (g_provider.kind == "openai") {
        return BuildOpenAIRequest(escapedModel, sysContent, userContent);
    } else if (g_provider.kind == "anthropic") {
        return BuildAnthropicRequest(escapedModel, sysContent, userContent);
    }
    return BuildOllamaRequest(escapedModel, sysContent, userContent);
}

Response SendTranslationRequest(const string &in requestData) {
    g_logger.Debug("request url   : " + g_provider.chatUrl);
    g_logger.Debug("request header: " + BuildHeader());
    g_logger.Debug("request data  : " + requestData);
    return SendRequest(g_provider.chatUrl, BuildHeader(), requestData);
}

// ========================
// user config & model validation
// ========================
void LoadUserConfig() {
    g_config.Load();
    g_logger.Info("apiFormat: " + g_config.apiFormat);
    g_logger.Info("Loaded model: " + g_config.modelName);
    g_logger.Info("Loaded API Key: " + (g_config.apiKey.empty() ? "(not set)" : "(set)"));
    if (!g_config.customEndpoint.empty()) {
        g_logger.Info("Loaded custom endpoint: " + g_config.customEndpoint);
    }
}

bool TrySelectModelFromList(const array<string> &in availableModels, const string &in modelName) {
    if (modelName.empty()) return false;
    string selectedLower = modelName; selectedLower.MakeLower();

    for (uint i = 0; i < availableModels.length(); i++) {
        string availableLower = availableModels[i]; availableLower.MakeLower();
        if (selectedLower == availableLower) {
            g_config.modelName = availableModels[i];
            return true;
        }
    }

    // :latest fallback for ollama /api/tags convention
    if (modelName.find(":") == -1) {
        string withLatestLower = modelName + ":latest";
        withLatestLower.MakeLower();
        for (uint i = 0; i < availableModels.length(); i++) {
            string availableLower = availableModels[i]; availableLower.MakeLower();
            if (withLatestLower == availableLower) {
                g_config.modelName = availableModels[i];
                return true;
            }
        }
    }

    return false;
}

array<string> ParseModelsList(const string &in body, const string &in apiFormat) {
    array<string> result;
    if (apiFormat == "anthropic") return result;

    JsonReader reader;
    JsonValue root;
    if (!reader.parse(NormalizeJsonResponse(body), root)) {
        g_logger.Warn("Failed to parse models list JSON");
        LogModelsListPreview(body);
        return result;
    }

    // ollama /api/tags: {"models":[{"name":...}]}; openai-compat: {"data":[{"id":...}]}
    string listKey = (apiFormat == "ollama") ? "models" : "data";
    string idKey   = (apiFormat == "ollama") ? "name"  : "id";
    JsonValue list = root[listKey];
    if (!list.isArray()) {
        g_logger.Warn("No model list array found in response (expected: " + listKey + ")");
        LogModelsListPreview(body);
        return result;
    }
    for (int j = 0; j < list.size(); j++) {
        JsonValue m = list[j];
        if (m.isObject() && m[idKey].isString()) {
            result.insertLast(m[idKey].asString());
        }
    }

    if (result.length() == 0) {
        g_logger.Warn("Models list parsed but no entries extracted (expected key: " + idKey + ")");
        LogModelsListPreview(body);
    }
    return result;
}

void LogModelsListPreview(const string &in body) {
    int previewLen = min(512, int(body.length()));
    g_logger.Debug("Raw models-list response (first 512 chars): " + body.substr(0, uint(previewLen)));
}

string FirstNModels(const array<string> &in models, int n) {
    string result = "";
    int count = min(int(models.length()), n);
    for (int i = 0; i < count; i++) {
        if (i > 0) result += ", ";
        result += models[i];
    }
    if (int(models.length()) > n) result += ", ...";
    return result;
}

// ========================
// login flow
// ========================
// pre-load a local ollama model so the first real subtitle does not pay the
// model-load latency; failures only log and never fail the login itself,
// and the response is never stored in cache or history
void WarmUpLocalOllama() {
    if (g_provider.kind != "ollama" || !g_config.apiKey.empty()) return;

    string req = "{\"model\":\"" + EscapeJsonString(g_config.modelName) + "\""
         + ",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]"
         + ",\"think\":false,\"stream\":false,\"keep_alive\":\"30m\"";
    if (g_config.contextLength > 0) {
        req += ",\"options\":{\"num_ctx\":" + g_config.contextLength + ",\"num_predict\":1}";
    } else {
        req += ",\"options\":{\"num_predict\":1}";
    }

    g_logger.Info("Warming up local ollama (loading model into memory)...");
    HostIncTimeOut(120000);
    Response r = DoSend(g_provider.chatUrl, BuildHeader(), req, 0);
    if (r.status == 0 || r.body.empty()) {
        g_logger.Warn("Warm-up request failed (status=" + r.status
             + "); the first subtitle may be slow");
    } else {
        g_logger.Info("Warm-up done (status=" + r.status + ")");
    }
}

void ParseLoginInput(string User, string Pass) {
    g_config.modelName = TrimString(User);
    string newApiKey = TrimString(Pass);
    if (!newApiKey.empty()) {
        g_config.apiKey = newApiKey;
    }
}

string ServerLogin(string User, string Pass) {
    ParseLoginInput(User, Pass);
    g_logger.redactKey = g_config.apiKey;

    if (g_config.modelName.empty()) {
        g_isPluginActive = false;
        return "400 Model name is required";
    }

    if (!g_config.customEndpoint.empty() && !IsValidCustomEndpoint(g_config.customEndpoint)) {
        g_isPluginActive = false;
        return "400 Invalid custom endpoint (must start with http:// or https://)";
    }

    g_provider = DetectProvider();
    g_logger.Info("Provider: " + g_provider.name);
    g_logger.Debug("chat URL: " + g_provider.chatUrl);
    g_logger.Debug("tags URL: " + g_provider.tagsUrl);

    // anthropic has no list endpoint; skip validation
    if (g_provider.tagsUrl.empty()) {
        g_logger.Info("Model list validation skipped (no list endpoint for " + g_provider.kind + ")");
        g_config.Save();
        g_isPluginActive = true;
        g_logger.Info("Login ok — provider=" + g_provider.name + ", model=" + g_config.modelName);
        return "200 ok";
    }

    Response r = SendRequest(g_provider.tagsUrl, BuildHeader(), "");

    if (r.status == 0) {
        g_isPluginActive = false;
        return "500 Cannot reach endpoint: " + g_provider.tagsUrl;
    }
    if (r.status == 401 || r.status == 403) {
        g_isPluginActive = false;
        return "401 Authentication failed (bad API key?)";
    }
    if (r.status >= 500) {
        g_isPluginActive = false;
        return "500 Server returned status " + r.status;
    }
    if (r.body.empty()) {
        g_isPluginActive = false;
        return "500 Empty response from endpoint";
    }

    array<string> available = ParseModelsList(r.body, g_config.apiFormat);
    if (available.length() == 0) {
        g_isPluginActive = false;
        return "500 No models found at endpoint (response parsed but list empty)";
    }
    LogModelList(available);

    if (!TrySelectModelFromList(available, g_config.modelName)) {
        g_isPluginActive = false;
        g_logger.Warn("Model '" + g_config.modelName + "' not in available list");
        return "404 Model '" + g_config.modelName + "' not found. Available: "
             + FirstNModels(available, 10);
    }

    g_config.Save();
    g_isPluginActive = true;
    g_logger.Info("Login ok — provider=" + g_provider.name + ", model=" + g_config.modelName);
    WarmUpLocalOllama();

    return "200 ok";
}

void ServerLogout() {
    g_config.Save();
    HostSaveString("api_key_ollama", "");
    g_logger.Info("Successfully logged out from Ollama translation plugin");
}

// ========================
// languages
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
// translation flow
// ========================
string Translate(string Text, string &in SrcLang, string &in DstLang) {
    if (!g_isPluginActive) return "Plugin is not loaded normally, please check settings";

    if (!IsTargetLanguageValid(DstLang)) {
        g_logger.Warn("Target language not specified");
        ShowError("Target language not specified", "Translation Failed");
        return "";
    }

    if (!IsTranslatable(Text)) {
        g_logger.Debug("Skipping non-translatable input: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }

    string srcLangCode = NormalizeLanguage(SrcLang);
    string cacheKey = CacheKey(Text, srcLangCode, DstLang, g_config.modelName);
    string cached;
    if (CacheTryGet(cacheKey, cached)) {
        g_logger.Debug("Cache hit: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return cached;
    }

    string requestData = BuildTranslationRequest(Text, srcLangCode, DstLang);
    Response resp = SendTranslationRequest(requestData);
    if (resp.status == 0 || resp.body.empty()) {
        g_logger.Warn("Translation failed (status=" + resp.status + "): " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }

    string translatedText = ExtractTranslatedText(resp.body);
    translatedText = RemoveThinkingTags(translatedText);
    translatedText = TrimString(translatedText);
    if (translatedText.empty()) {
        g_logger.Warn("Translation returned empty content: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }
    if (DstLang == "fa" || DstLang == "ar" || DstLang == "he" || DstLang == "ur" || DstLang == "yi") {
        translatedText = "‫" + translatedText;
    }

    CacheSet(cacheKey, translatedText);
    AddHistoryEntry(Text, translatedText);

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

    // all formats wrap errors in {"error": ...}
    JsonValue errVal = root["error"];
    if (!errVal.isNull()) {
        string errMsg = "(unknown error format)";
        string errType = "";
        string errCode = "";
        if (errVal.isString()) {
            errMsg = errVal.asString();
        } else if (errVal.isObject()) {
            if (errVal["message"].isString()) errMsg = errVal["message"].asString();
            if (errVal["type"].isString())   errType = errVal["type"].asString();
            if (errVal["code"].isString())    errCode = errVal["code"].asString();
        }
        // include type/code for classification
        string detail = errMsg;
        if (errType != "") detail += " [type=" + errType + "]";
        if (errCode != "") detail += " [code=" + errCode + "]";
        g_logger.Warn("API error: " + detail);
        return "";
    }

    // dispatch to format-specific parser
    if (g_provider.kind == "rest") {
        return ExtractRestText(response);
    } else if (g_provider.kind == "openai") {
        return ExtractOpenAIText(response);
    } else if (g_provider.kind == "anthropic") {
        return ExtractAnthropicText(response);
    }
    return ExtractOllamaText(response);
}

// ========================
// utilities
// ========================

bool IsTranslatable(const string &in t) {
    string s = TrimString(t);
    if (s.empty()) return false;

    // skip set covers ascii whitespace, digits, punctuation
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
    bool hasScheme = (lower.length() >= 7 && lower.substr(0, 7) == "http://")
                  || (lower.length() >= 8 && lower.substr(0, 8) == "https://");
    return hasScheme;
}

int min(int a, int b) { return (a < b) ? a : b; }

string TrimString(const string &in text) {
    if (text.empty()) return "";
    int start = 0;
    int end = int(text.length()) - 1;
    while (start <= end) {
        string ch = text.substr(uint(start), 1);
        if (ch != " " && ch != "\n" && ch != "\r" && ch != "\t") break;
        start++;
    }
    while (end >= start) {
        string ch = text.substr(uint(end), 1);
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
    string result = "";
    int cur = 0;
    int totalLen = int(text.length());
    while (cur < totalLen) {
        int openPos = text.find("<think", cur);
        if (openPos == -1) {
            result += text.substr(uint(cur));
            break;
        }
        result += text.substr(uint(cur), uint(openPos - cur));
        int closePos = text.find("</think", openPos);
        if (closePos == -1) break;
        int closeBracket = text.find(">", closePos);
        if (closeBracket == -1) cur = closePos + 7;
        else cur = closeBracket + 1;
    }
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

    return result;
}
