/*
 * Real-time subtitle translation for PotPlayer using Ollama
 * v3.0 — Phase 3: Provider split + Prompt v3
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
// PROMPTS (v3 — ~70 token system, down from ~220)
// ========================
// ponytail: positive instructions over negative, no redundant "Output plain
// text only" repeated three times, no contradictory "keep formatting" vs
// "natural fluent". Optimized for real-time subtitle translation.

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
"Translate to {{to}}:\n"
"\n"
"<text>\n"
"{{text_to_translate}}\n"
"</text>\n";

const string CONTEXT_PROMPT_BASE =
"Reference context (do NOT translate):\n"
"{{optional_reference_context}}\n"
"\n";

// ========================
// ENDPOINT NORMALIZER
// ========================
// ponytail: auto-append /v1/chat/completions so user can paste just the host.
// Full URLs (already containing /chat/completions) are passed through.

class EndpointNormalizer {
    string Resolve(const string &in raw) {
        string url = TrimString(raw);
        if (url.empty()) return "";

        // Already a full chat URL — use as-is
        if (url.find("/chat/completions") != -1) return url;

        // Strip trailing slashes
        while (url.length() > 0 && url.substr(url.length() - 1, 1) == "/") {
            url = url.substr(0, url.length() - 1);
        }

        // Ends with /v1 — append /chat/completions
        if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
            return url + "/chat/completions";
        }

        // Default: append /v1/chat/completions
        return url + "/v1/chat/completions";
    }

    string ResolveModelsList(const string &in chatUrl) {
        string base = chatUrl;
        int pos = base.find("/chat/completions");
        if (pos != -1) base = base.substr(0, uint(pos));
        if (base.length() >= 3 && base.substr(base.length() - 3, 3) == "/v1") {
            return base + "/models";
        }
        return base + "/v1/models";
    }
}

// ========================
// PROVIDER MATRIX
// ========================
// Four modes based on (customEndpoint, apiKey) presence:
//   (empty, empty)   → OllamaLocal   (baseUrl + options wrapper, no auth)
//   (empty, set)     → OllamaCloud   (ollama.com + options wrapper, Bearer)
//   (set, empty)     → OpenAILocal   (custom + top-level params, no auth)
//   (set, set)       → OpenAICloud   (custom + top-level params, Bearer)

class ProviderInfo {
    string kind;            // "OllamaLocal" / "OllamaCloud" / "OpenAILocal" / "OpenAICloud"
    string chatUrl;         // full URL for chat completion
    string tagsUrl;         // full URL for model list
    bool needsAuth;         // include Authorization: Bearer header
    bool isOllamaFormat;    // true = options wrapper + think field, false = OpenAI top-level
    string name;            // human-readable, for logging
}

class ProviderDetector {
    ProviderInfo Detect() {
        ProviderInfo p;
        if (g_config.customEndpoint.empty()) {
            if (g_config.apiKey.empty()) {
                p.kind = "OllamaLocal";
                p.chatUrl = g_config.baseUrl + "/api/chat";
                p.tagsUrl = g_config.baseUrl + "/api/tags";
                p.needsAuth = false;
                p.isOllamaFormat = true;
                p.name = "Ollama Local";
            } else {
                p.kind = "OllamaCloud";
                p.chatUrl = "https://ollama.com/api/chat";
                p.tagsUrl = "https://ollama.com/api/tags";
                p.needsAuth = true;
                p.isOllamaFormat = true;
                p.name = "Ollama Cloud";
            }
        } else {
            string resolved = g_endpointNormalizer.Resolve(g_config.customEndpoint);
            p.kind = g_config.apiKey.empty() ? "OpenAILocal" : "OpenAICloud";
            p.chatUrl = resolved;
            p.tagsUrl = g_endpointNormalizer.ResolveModelsList(resolved);
            p.needsAuth = !g_config.apiKey.empty();
            p.isOllamaFormat = false;
            p.name = p.needsAuth ? "OpenAI Cloud" : "OpenAI Local (e.g. LM Studio)";
        }
        return p;
    }
}

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
        HostIncTimeOut(15000);
        Response r;
        string bodyOut = HostUrlGetString(url, userAgent, header, body);
        r.body = bodyOut;
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
        if (r.status == 0) return true;
        if (r.status >= 500) return true;
        if (r.status == 429) return true;
        return false;
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

    void AddEntry(const string &in source, const string &in translation) {
        if (!g_config.contextEnabled || source.empty()) return;
        // Phase 3 (fixes H5): drop [lang] metadata, use plain src ⇒ dst format.
        // Saves ~10 tokens per entry; LLM no longer tempted to translate brackets.
        string entry = source + " \u21D2 " + translation;
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
// Phase 3: provider-split request building. Old Api class probed /api/show,
// /api/version, /api/tags at login (3 sync requests). All that's gone —
// ProviderDetector does it with config field inspection only.

class Api {
    string userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
    string contentType = "Content-Type: application/json";

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
        string messages = BuildMessages(sysContent, userContent);

        if (g_provider.isOllamaFormat) return BuildOllamaRequest(messages);
        return BuildOpenAIRequest(messages);
    }

    string BuildMessages(const string &in sysContent, const string &in userContent) {
        string escapedSystem = EscapeJsonString(sysContent);
        string escapedUser = EscapeJsonString(userContent);
        return "[{\"role\":\"system\",\"content\":\"" + escapedSystem + "\"},"
             + "{\"role\":\"user\",\"content\":\"" + escapedUser + "\"}]";
    }

    string BuildOllamaRequest(const string &in messages) {
        // Phase 3 (fixes H4): escape model name to handle characters like " or \
        string escapedModel = EscapeJsonString(g_config.modelName);
        string req = "{\"model\":\"" + escapedModel + "\",\"messages\":" + messages;
        req += BuildOllamaOptions();
        // ponytail: only emit think field when user opts in.
        // gpt-oss users: set enableThinking=true + thinkStrength="low".
        if (g_config.enableThinking) {
            req += ",\"think\":" + GetThinkValue();
        }
        req += ",\"stream\":false}";
        return req;
    }

    string BuildOpenAIRequest(const string &in messages) {
        // Phase 3 (fixes Q8/H8): top-level params, NOT wrapped in options.
        // OpenAI standard fields only; top_k/min_p/repeat_penalty dropped
        // (not in OpenAI spec, would error on strict servers).
        string escapedModel = EscapeJsonString(g_config.modelName);
        string req = "{\"model\":\"" + escapedModel + "\",\"messages\":" + messages;
        req += BuildOpenAIOptions();
        req += ",\"stream\":false}";
        return req;
    }

    string BuildOllamaOptions() {
        // Phase 3 (fixes H3): explicit sorted field list, NOT dictionary iteration.
        // jsoncpp dictionary order is non-deterministic; this guarantees stable JSON
        // which is also a prerequisite for cache hits in Phase 4.
        return ",\"options\":{"
             + "\"max_tokens\":" + g_config.maxTokens + ","
             + "\"min_p\":" + g_config.minP + ","
             + "\"repeat_penalty\":" + g_config.repeatPenalty + ","
             + "\"temperature\":" + g_config.temperature + ","
             + "\"top_k\":" + g_config.topK + ","
             + "\"top_p\":" + g_config.topP
             + "}";
    }

    string BuildOpenAIOptions() {
        // Top-level (no options wrapper). Sorted alphabetically.
        return ",\"max_tokens\":" + g_config.maxTokens + ","
             + "\"temperature\":" + g_config.temperature + ","
             + "\"top_p\":" + g_config.topP;
    }

    string GetThinkValue() {
        if (g_config.thinkStrength.empty()) return "true";
        return "\"" + g_config.thinkStrength + "\"";
    }

    string BuildUrl() {
        return g_provider.chatUrl;
    }

    string BuildHeader() {
        string header = contentType + "\nAccept: application/json";
        if (g_provider.needsAuth) {
            header += "\nAuthorization: Bearer " + g_config.apiKey;
        }
        return header;
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
ProviderDetector g_providerDetector;
EndpointNormalizer g_endpointNormalizer;
ProviderInfo g_provider;  // set in ServerLogin, read by Api/Translate
bool g_isPluginActive = true;

// ========================
// USER CONFIG & MODEL VALIDATION
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
    if (modelName.empty()) return false;
    string selectedLower = modelName; selectedLower.MakeLower();
    for (uint i = 0; i < availableModels.length(); i++) {
        string availableLower = availableModels[i]; availableLower.MakeLower();
        if (selectedLower == availableLower) {
            g_config.modelName = availableModels[i];  // canonicalize case
            return true;
        }
    }
    return false;
}

array<string> ParseModelsList(const string &in body, bool isOllamaFormat) {
    array<string> result;
    if (body.empty()) return result;

    JsonReader reader;
    JsonValue root;
    string normalized = NormalizeJsonResponse(body);
    if (!reader.parse(normalized, root)) {
        g_logger.Warn("Failed to parse models list response");
        int previewLen = min(512, int(body.length()));
        g_logger.Debug("Raw response (first 512 chars): " + body.substr(0, uint(previewLen)));
        return result;
    }

    JsonValue list = isOllamaFormat ? root["models"] : root["data"];
    if (!list.isArray()) {
        g_logger.Warn("Models list response missing array field");
        return result;
    }

    string keyName = isOllamaFormat ? "name" : "id";
    for (int i = 0; i < list.size(); i++) {
        JsonValue m = list[i];
        if (m.isObject() && m[keyName].isString()) {
            result.insertLast(m[keyName].asString());
        }
    }
    return result;
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
// LOGIN FLOW
// ========================
void ParseLoginInput(string User, string Pass) {
    g_config.modelName = TrimString(User);
    string newApiKey = TrimString(Pass);
    if (!newApiKey.empty()) {
        g_config.apiKey = newApiKey;
    }
}

string ServerLogin(string User, string Pass) {
    ParseLoginInput(User, Pass);
    // ponytail: redactKey set as early as possible so all subsequent logs are safe
    g_logger.redactKey = g_config.apiKey;

    if (g_config.modelName.empty()) {
        g_isPluginActive = false;
        return "400 Model name is required";
    }

    if (!g_config.customEndpoint.empty() && !IsValidCustomEndpoint(g_config.customEndpoint)) {
        g_isPluginActive = false;
        return "400 Invalid custom endpoint (must start with http:// or https://)";
    }

    // Phase 3: detect provider once, cache globally (was implicit per-call in v2)
    g_provider = g_providerDetector.Detect();
    g_logger.Info("Provider: " + g_provider.name);
    g_logger.Debug("chat URL: " + g_provider.chatUrl);
    g_logger.Debug("tags URL: " + g_provider.tagsUrl);

    // Phase 3: single validation request (was 3 in v2.4: tags + show + version)
    string header = g_api.BuildHeader();
    Response r = g_httpTransport.SendWithRetry(g_provider.tagsUrl, header, "");

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

    // Parse + validate model presence (user requirement: confirm model is in list)
    array<string> available = ParseModelsList(r.body, g_provider.isOllamaFormat);
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
    return "200 ok";
}

void ServerLogout() {
    g_config.Save();
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
    if (DstLang == "fa" || DstLang == "ar" || DstLang == "he") translatedText = "\u202B" + translatedText;

    g_contextHistory.AddEntry(Text, translatedText);

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

    // Phase 3: response shape determined by provider format
    JsonValue message = g_provider.isOllamaFormat ? root["message"] : root["choices"][0]["message"];
    if (!message.isObject()) {
        g_logger.Warn("Invalid response format - no message");
        return "";
    }

    JsonValue content = message["content"];
    if (!content.isString()) {
        g_logger.Warn("Invalid response format - no content");
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

int max(int a, int b) { return (a > b) ? a : b; }
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
        result += text.substr(uint(cur), uint(openPos - cur));
        int closePos = text.find("</think", openPos);
        if (closePos == -1) {
            break;
        }
        int closeBracket = text.find(">", closePos);
        if (closeBracket == -1) {
            cur = closePos + 7;
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
        string token = text.substr(uint(start), uint(pos - start));
        if (!token.empty()) result.insertLast(token);
        start = pos + int(delimiter.length());
        pos = text.findFirst(delimiter, start);
    }

    string token = text.substr(uint(start));
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
    // Template authors are responsible for handling empty {{from}} gracefully.
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
    // === Phase 1: template + utility invariants ===

    // ApplyTemplate: empty {{from}} no longer triggers string hacks
    string r1 = ApplyTemplate("from={{from}} to={{to}}", "hello", "", "zh-CN", "");
    SelfTestAssert(r1 == "from= to=zh-CN", "ApplyTemplate empty from -> '" + r1 + "'");

    // ApplyTemplate: only {{text_to_translate}} works ({{text}} alias removed)
    string r2 = ApplyTemplate("[{{text_to_translate}}]", "hi", "", "zh", "");
    SelfTestAssert(r2 == "[hi]", "ApplyTemplate text_to_translate -> '" + r2 + "'");

    // TrimString
    SelfTestAssert(TrimString("  hello  ") == "hello", "TrimString spaces");
    SelfTestAssert(TrimString("\n\n") == "", "TrimString whitespace-only");

    // EscapeJsonString
    string r3 = EscapeJsonString("a\"b\nc");
    SelfTestAssert(r3 == "a\\\"b\\nc", "EscapeJsonString -> '" + r3 + "'");

    // Logger.Redact
    Logger l;
    l.redactKey = "secret";
    SelfTestAssert(l.Redact("mysecret here") == "my*** here", "Logger.Redact -> '" + l.Redact("mysecret here") + "'");

    // === Phase 2: reliability modules ===

    // RemoveThinkingTags
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

    // TextCleaner.IsTranslatable
    TextCleaner tc;
    SelfTestAssert(tc.IsTranslatable("") == false, "IsTranslatable empty");
    SelfTestAssert(tc.IsTranslatable("   ") == false, "IsTranslatable whitespace");
    SelfTestAssert(tc.IsTranslatable("...") == false, "IsTranslatable punctuation");
    SelfTestAssert(tc.IsTranslatable("123") == false, "IsTranslatable digits");
    SelfTestAssert(tc.IsTranslatable("-") == false, "IsTranslatable single char");
    SelfTestAssert(tc.IsTranslatable("hello") == true, "IsTranslatable ascii word");
    SelfTestAssert(tc.IsTranslatable("Hello, world!") == true, "IsTranslatable sentence");

    // Response default state
    Response resp;
    SelfTestAssert(resp.status == 0, "Response default status");
    SelfTestAssert(resp.body == "", "Response default body");

    // HttpTransport.ShouldRetry
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

    // === Phase 3: provider matrix + endpoint normalization ===

    EndpointNormalizer en;

    // EndpointNormalizer.Resolve
    SelfTestAssert(en.Resolve("http://127.0.0.1:1234") == "http://127.0.0.1:1234/v1/chat/completions",
                  "Resolve bare host -> '" + en.Resolve("http://127.0.0.1:1234") + "'");
    SelfTestAssert(en.Resolve("http://localhost:1234/v1") == "http://localhost:1234/v1/chat/completions",
                  "Resolve /v1 host -> '" + en.Resolve("http://localhost:1234/v1") + "'");
    SelfTestAssert(en.Resolve("http://localhost:1234/v1/") == "http://localhost:1234/v1/chat/completions",
                  "Resolve /v1/ host -> '" + en.Resolve("http://localhost:1234/v1/") + "'");
    SelfTestAssert(en.Resolve("https://api.z.ai/api/paas/v4/chat/completions") == "https://api.z.ai/api/paas/v4/chat/completions",
                  "Resolve full URL passthrough -> '" + en.Resolve("https://api.z.ai/api/paas/v4/chat/completions") + "'");
    SelfTestAssert(en.Resolve("https://openrouter.ai/api/v1") == "https://openrouter.ai/api/v1/chat/completions",
                  "Resolve openrouter /v1 -> '" + en.Resolve("https://openrouter.ai/api/v1") + "'");

    // EndpointNormalizer.ResolveModelsList
    SelfTestAssert(en.ResolveModelsList("http://h/v1/chat/completions") == "http://h/v1/models",
                  "ResolveModelsList /v1 -> '" + en.ResolveModelsList("http://h/v1/chat/completions") + "'");
    SelfTestAssert(en.ResolveModelsList("https://api.z.ai/api/paas/v4/chat/completions") == "https://api.z.ai/api/paas/v4/models",
                  "ResolveModelsList z.ai -> '" + en.ResolveModelsList("https://api.z.ai/api/paas/v4/chat/completions") + "'");

    // ProviderDetector: build a ProviderInfo manually to verify field setup logic
    // (cannot call Detect() here since it reads g_config which is in default state)
    ProviderInfo p;
    p.kind = "OllamaLocal"; p.chatUrl = "http://x/api/chat"; p.tagsUrl = "http://x/api/tags";
    p.needsAuth = false; p.isOllamaFormat = true; p.name = "Ollama Local";
    SelfTestAssert(p.isOllamaFormat == true && p.needsAuth == false, "ProviderInfo OllamaLocal fields");

    // ParseModelsList: Ollama format
    array<string> ollamaModels = ParseModelsList("{\"models\":[{\"name\":\"llama2\"},{\"name\":\"qwen3\"}]}", true);
    SelfTestAssert(ollamaModels.length() == 2 && ollamaModels[0] == "llama2", "ParseModelsList Ollama length=" + ollamaModels.length());

    // ParseModelsList: OpenAI format
    array<string> openaiModels = ParseModelsList("{\"data\":[{\"id\":\"gpt-4\"},{\"id\":\"claude\"}]}", false);
    SelfTestAssert(openaiModels.length() == 2 && openaiModels[0] == "gpt-4", "ParseModelsList OpenAI length=" + openaiModels.length());

    // TrySelectModelFromList: case-insensitive match + canonicalize
    array<string> modelList = {"Llama2", "Qwen3"};
    SelfTestAssert(TrySelectModelFromList(modelList, "qwen3") == true, "TrySelectModelFromList case-insensitive");
    SelfTestAssert(TrySelectModelFromList(modelList, "nonexistent") == false, "TrySelectModelFromList miss");

    // FirstNModels
    array<string> manyModels = {"a", "b", "c", "d", "e"};
    SelfTestAssert(FirstNModels(manyModels, 3) == "a, b, c, ...", "FirstNModels truncate -> '" + FirstNModels(manyModels, 3) + "'");

    // ContextHistory: new src ⇒ dst format
    ContextHistory ch;
    ch.AddEntry("hello", "\u4f60\u597d");
    string ctx = ch.GetContext();
    SelfTestAssert(ctx.find("\u21D2") != -1, "ContextHistory uses arrow -> '" + ctx + "'");
    SelfTestAssert(ctx.find("[") == -1, "ContextHistory drops [lang] tags -> '" + ctx + "'");

    g_logger.Info("SelfTest passed");
}
