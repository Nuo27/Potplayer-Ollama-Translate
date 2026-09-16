/*
 * real-time subtitle translation for potplayer
 */

// ========================
// user settings
// ========================
// restart potplayer after any edit to this file.

// ---- prompts ----
const string SYSTEM_PROMPT_BASE =
"You are a senior subtitle translator. Translate from {{from}} into {{to}}.\n"
"\n"
"Principles:\n"
"- Faithful: convey exactly what the line says - nothing added, nothing omitted, nothing explained.\n"
"- Idiomatic: recast each line the way a native speaker would say it, never word-for-word. If it sounds translated, rewrite it.\n"
"- In character: match the speaker's register - casual, formal, slang, angry, teasing - and keep lines short enough to read at a glance.\n"
"- Consistent: follow the names, terms, and honorifics already established in context.\n"
"\n"
"Output rules:\n"
"- Emit only the translation - no quotes, no notes, no source text.\n"
"- Keep names, numbers, units, code, and identifiers unchanged.\n"
"- A mid-sentence fragment stays a fragment; do not complete it.\n"
"\n"
"User messages may include a <context> block of earlier lines, each as \"source ⇒ translation\" (read only).\n"
"Use it for tone, terminology, and continuity; it may be empty. Never translate or repeat the context.\n";

const string USER_PROMPT_BASE =
"<context>\n"
"{{context_raw}}\n"
"</context>\n"
"\n"
"<text>\n"
"{{text_to_translate}}\n"
"</text>\n"
"\n"
"Translate the line in <text> into {{to}}. Output only the translation.\n";

const string USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
const string OLLAMA_LOCAL_BASE = "http://127.0.0.1:11434";

class Config {
    // ---- login ----
    string modelName = "";
    string apiKey = "";
    // pristine defaults; login falls back to these on bad input
    string fallbackModelName = "";
    string fallbackApiKey = "";

    // ---- endpoint ----
    string apiFormat = "ollama";   // ollama | openai | anthropic
    string customEndpoint = "";

    // ---- ollama extras (/api/chat) ----
    // spliced into the body verbatim; "" = bare skeleton (stream:false still injected)
    string ollamaConfigs = ""
        + "{"
        + "\"stream\": false, "
        + "\"options\": {\"num_ctx\": 4096, \"num_predict\": 256, \"temperature\": 0.3, \"top_p\": 0.9}, "
        + "\"think\": false, "
        + "\"keep_alive\": \"30m\""
        + "}";

    // ---- openai extras (/v1/chat/completions) ----
    string openaiConfigs = ""
        + "{"
        + "\"temperature\": 0.3, "
        + "\"reasoning_effort\": \"none\", "
        + "\"chat_template_kwargs\": { \"enable_thinking\": false }"
        + "}";

    // ---- anthropic extras (/v1/messages) ----
    // spec: thinking budget_tokens >= 1024 and < max_tokens; thinking requires temperature = 1
    string anthropicConfigs = ""
    + "{"
    + "\"temperature\": 0.3, "
    + "\"max_tokens\": 512, "
    + "\"thinking\": {\"type\": \"disabled\"}"
    + "}";

    // ---- general settings: context history ----
    bool contextEnabled = true;
    int contextCount = 7;
    // ---- general settings: memory cache cap ----
    int cacheMaxEntries = 500;
    // ---- general settings: retry ----
    int retryCount = -1;      // retryCount: 0 = single attempt, -1 = retry until success, n = n extra attempts
    int retryDelayMs = 500;   // wait before each retry in ms; 0 = immediate

    string systemPrompt = SYSTEM_PROMPT_BASE;
    string userPrompt = USER_PROMPT_BASE;

    Config() {
        // pristine file-side defaults, captured once at construction
        fallbackModelName = modelName;
        fallbackApiKey = apiKey;
    }

    void Load() {
        // empty stored values must not shadow the file-side defaults
        // (a logout in a fresh instance may have saved "")
        string savedModel = HostLoadString("selected_model_ollama", "");
        if (!savedModel.empty()) modelName = savedModel;
        string savedKey = HostLoadString("api_key_ollama", "");
        if (!savedKey.empty()) apiKey = savedKey;
    }

    void Save() {
        // never wipe stored credentials with empty in-memory values
        if (!modelName.empty()) HostSaveString("selected_model_ollama", modelName);
        if (!apiKey.empty()) HostSaveString("api_key_ollama", apiKey);
    }
}

// ========================
// logger
// ========================

class Logger {
    bool debug = false;   // dev only: set true to print debug logs
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
    return "{$CP949=API Key:$}{$CP950=API Key:$}{$CP936=API Key:$}{$CP0=API Key:$}";
}

void OnInitialize() {
    LoadUserConfig();
    // dev only: uncomment to open a console window and inspect log output
    // HostOpenConsole();
    g_logger.Info("Ollama translation plugin initialized");
}

void OnFinalize() {
    g_logger.Info("Ollama translation plugin finalized");
}

// ========================
// provider info
// ========================
// supported formats: ollama, openai, anthropic

class ProviderInfo {
    string kind;         // ollama | openai | anthropic
    string chatUrl;      // full url for chat completion
    string tagsUrl;      // full url for model list ("" = none, login uses a test request)
    bool needsAuth;      // include auth header
    bool authIsBearer;   // true: bearer; false: x-api-key
    string name;
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
    if (kind == "anthropic") {
        if (url.find("/messages") != -1) return url;
        if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
            return url + "/messages";
        }
        return url + "/v1/messages";
    }
    if (url.find("/chat/completions") != -1) return url;
    if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
        return url + "/chat/completions";
    }
    return url + "/v1/chat/completions";
}

string ModelsUrlFromChatUrl(const string &in chatUrl, const string &in kind) {
    string chatMarker = (kind == "ollama") ? "/api/chat" : "/chat/completions";
    string modelsMarker = (kind == "ollama") ? "/api/tags" : "/models";
    string base = chatUrl;
    int pos = base.find(chatMarker);
    if (pos != -1) base = base.substr(0, uint(pos));
    return base + modelsMarker;
}

ProviderInfo DetectProvider() {
    ProviderInfo p;
    p.kind = g_config.apiFormat;

    if (p.kind == "ollama") {
        if (g_config.apiKey.empty()) {
            p.chatUrl = OLLAMA_LOCAL_BASE + "/api/chat";
            p.tagsUrl = OLLAMA_LOCAL_BASE + "/api/tags";
            p.needsAuth = false;
        } else {
            p.chatUrl = "https://ollama.com/api/chat";
            p.tagsUrl = "https://ollama.com/api/tags";
            p.needsAuth = true;
        }
        p.authIsBearer = true;
        p.name = g_config.apiKey.empty() ? "Ollama Local" : "Ollama Cloud";
    } else if (p.kind == "openai") {
        if (g_config.apiKey.empty()) {
            p.chatUrl = OLLAMA_LOCAL_BASE + "/v1/chat/completions";
            p.tagsUrl = OLLAMA_LOCAL_BASE + "/v1/models";
        } else {
            p.chatUrl = "https://api.openai.com/v1/chat/completions";
            p.tagsUrl = "https://api.openai.com/v1/models";
        }
        p.needsAuth = !g_config.apiKey.empty();
        p.authIsBearer = true;
        p.name = g_config.apiKey.empty() ? "OpenAI Local" : "OpenAI Cloud";
    } else if (p.kind == "anthropic") {
        p.chatUrl = g_config.apiKey.empty()
            ? OLLAMA_LOCAL_BASE + "/v1/messages"
            : "https://api.anthropic.com/v1/messages";
        p.tagsUrl = "";   // anthropic has no list-models endpoint; login tests with a minimal request
        p.needsAuth = !g_config.apiKey.empty();
        p.authIsBearer = false;
        p.name = g_config.apiKey.empty() ? "Anthropic Local" : "Anthropic Cloud";
    } else {
        // unknown format: fall back to ollama to avoid lockout
        g_logger.Warn("Unknown apiFormat '" + p.kind + "', defaulting to ollama");
        p.kind = "ollama";
        p.chatUrl = OLLAMA_LOCAL_BASE + "/api/chat";
        p.tagsUrl = OLLAMA_LOCAL_BASE + "/api/tags";
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

Response DoSend(const string &in url, const string &in header, const string &in body) {
    Response r;
    string resp = HostUrlGetString(url, USER_AGENT, header, body);
    if (resp.empty()) {
        r.status = 0;
        r.body = "";
        return r;
    }
    // HostUrlGetString has no status code; success = non-empty body
    r.status = 200;
    r.body = resp;
    return r;
}

// ========================
// context history
// ========================

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
        // refresh recency so frequently hit entries survive eviction
        for (uint i = 0; i < g_cacheLru.length(); i++) {
            if (g_cacheLru[i] == key) {
                g_cacheLru.removeAt(i);
                g_cacheLru.insertLast(key);
                break;
            }
        }
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

// active=true when raw is a valid object; inner = its k/v pairs (no braces)
void ResolveJsonExtras(const string &in raw, const string &in fieldName, bool &out active, string &out inner) {
    active = false;
    inner = "";
    string trimmed = TrimString(raw);
    if (trimmed.empty()) return;
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(trimmed, root) || !root.isObject()) {
        g_logger.Warn(fieldName + " is not a valid json object; ignoring it");
        return;
    }
    active = true;
    inner = TrimString(trimmed.substr(uint(1), trimmed.length() - 2));
}

// system+user message array shared by the chat-completion bodies
string BuildChatMessages(const string &in sysContent, const string &in userContent) {
    return "[{\"role\":\"system\",\"content\":\"" + EscapeJsonString(sysContent)
         + "\"},{\"role\":\"user\",\"content\":\"" + EscapeJsonString(userContent) + "\"}]";
}

// ollama /api/chat body. stream:false is injected when ollamaConfigs is "" (ollama defaults to streaming ndjson)
string BuildOllamaRequest(const string &in escapedModel,
                          const string &in sysContent,
                          const string &in userContent) {
    string req = "{\"model\":\"" + escapedModel + "\",\"messages\":"
         + BuildChatMessages(sysContent, userContent);

    bool active = false;
    string inner = "";
    ResolveJsonExtras(g_config.ollamaConfigs, "ollamaConfigs", active, inner);
    if (active) {
        return req + (inner.empty() ? "" : "," + inner) + "}";
    }
    return req + ",\"stream\":false}";
}

// openai /v1/chat/completions body. openaiConfigs controls it
string BuildOpenAIRequest(const string &in escapedModel,
                          const string &in sysContent,
                          const string &in userContent) {
    string req = "{\"model\":\"" + escapedModel + "\",\"messages\":"
         + BuildChatMessages(sysContent, userContent);

    bool active = false;
    string inner = "";
    ResolveJsonExtras(g_config.openaiConfigs, "openaiConfigs", active, inner);
    return req + (active && !inner.empty() ? "," + inner : "") + "}";
}

// anthropic: model + system + messages + max_tokens (api-required);
// every other body parameter comes from anthropicConfigs verbatim
string BuildAnthropicRequest(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
    bool active = false;
    string inner = "";
    ResolveJsonExtras(g_config.anthropicConfigs, "anthropicConfigs", active, inner);

    // max_tokens is required; skeleton supplies it when anthropicConfigs omits it
    bool extrasHaveMaxTokens = false;
    if (active) {
        JsonReader reader;
        JsonValue root;
        if (reader.parse(TrimString(g_config.anthropicConfigs), root)
            && !root["max_tokens"].isNull()) {
            extrasHaveMaxTokens = true;
        }
    }

    string req = "{\"model\":\"" + escapedModel
         + "\",\"system\":\"" + EscapeJsonString(sysContent)
         + "\",\"messages\":[{\"role\":\"user\",\"content\":\""
         + EscapeJsonString(userContent) + "\"}]";
    if (!extrasHaveMaxTokens) {
        req += ",\"max_tokens\":256";
    }
    return req + (active && !inner.empty() ? "," + inner : "") + "}";
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
bool g_langErrorShown = false;
Logger g_logger;

// ========================
// request assembly & send
// ========================

string BuildHeader() {
    // Connection: close — a pooled request on a closed connection hangs forever
    string header = "Content-Type: application/json\r\nAccept: application/json\r\nConnection: close";
    if (g_provider.needsAuth && !g_config.apiKey.empty()) {
        if (g_provider.authIsBearer) {
            header += "\r\nAuthorization: Bearer " + g_config.apiKey;
        } else {
            header += "\r\nx-api-key: " + g_config.apiKey
                   + "\r\nanthropic-version: 2023-06-01";
        }
    }
    return header;
}

string BuildTranslationRequest(const string &in text, const string &in srcLang, const string &in dstLang) {
    string context = g_config.contextEnabled ? GetHistoryContext() : "";
    string sysContent = ApplyTemplate(g_config.systemPrompt, text, srcLang, dstLang, context);
    string userContent = ApplyTemplate(g_config.userPrompt, text, srcLang, dstLang, context);
    string escapedModel = EscapeJsonString(g_config.modelName);

    if (g_provider.kind == "openai") {
        return BuildOpenAIRequest(escapedModel, sysContent, userContent);
    }
    if (g_provider.kind == "anthropic") {
        return BuildAnthropicRequest(escapedModel, sysContent, userContent);
    }
    return BuildOllamaRequest(escapedModel, sysContent, userContent);
}

Response SendTranslationRequest(const string &in requestData) {
    g_logger.Debug("request url   : " + g_provider.chatUrl);
    g_logger.Debug("request header: " + BuildHeader());
    g_logger.Debug("request data  : " + requestData);
    return DoSend(g_provider.chatUrl, BuildHeader(), requestData);
}

// ========================
// user config & model validation
// ========================

void LoadUserConfig() {
    g_config.Load();
    g_logger.Info("apiFormat: " + g_config.apiFormat);
    g_logger.Info("Loaded model: " + g_config.modelName);
    if (!g_config.customEndpoint.empty()) {
        g_logger.Info("Custom endpoint (from file): " + g_config.customEndpoint);
    }
}

void RefreshSavedConfig() {
    string prevModel = g_config.modelName;
    string prevKey = g_config.apiKey;
    g_config.Load();
    if (g_config.modelName == prevModel && g_config.apiKey == prevKey) return;

    g_logger.redactKey = g_config.apiKey;
    g_provider = DetectProvider();
    // a model switch invalidates the accumulated context history
    g_history.resize(0);
    g_logger.Info("Config updated outside this instance — provider=" + g_provider.name + ", model=" + g_config.modelName);
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

// return: "" = usable, "auth" = auth failure, otherwise the server's error message
string AnthropicTestFailure(const Response &in r) {
    if (r.status == 0 || r.body.empty()) {
        return "endpoint unreachable (empty response)";
    }
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(NormalizeJsonResponse(r.body), root)) {
        return "unparseable response";
    }
    JsonValue err = root["error"];
    if (err.isNull()) return "";
    string msg = "unknown error";
    string type = "";
    if (err.isString()) {
        msg = err.asString();
    } else if (err.isObject()) {
        if (err["message"].isString()) msg = err["message"].asString();
        if (err["type"].isString()) type = err["type"].asString();
    }
    string lower = type + " " + msg;
    lower.MakeLower();
    if (lower.find("auth") != -1) return "auth";
    return msg;
}

string ServerLogin(string User, string Pass) {
    string dialogModel = TrimString(User);
    string dialogKey = TrimString(Pass);
    string fallbackModel = dialogModel.empty() ? g_config.modelName : g_config.fallbackModelName;
    string fallbackKey = dialogKey.empty() ? g_config.apiKey : g_config.fallbackApiKey;
    // dialog input wins when non-empty; empty fields keep the saved value
    if (!dialogKey.empty()) {
        g_config.apiKey = dialogKey;
    }
    g_logger.redactKey = g_config.apiKey;

    if (dialogModel.empty() && fallbackModel.empty()) {
        g_isPluginActive = false;
        return "400 Model name is required (login dialog or modelName in file)";
    }

    if (!g_config.customEndpoint.empty() && !IsValidCustomEndpoint(g_config.customEndpoint)) {
        g_isPluginActive = false;
        return "400 Invalid custom endpoint (must start with http:// or https://)";
    }

    g_provider = DetectProvider();
    g_logger.Info("Provider: " + g_provider.name);
    g_logger.Debug("chat URL: " + g_provider.chatUrl);
    g_logger.Debug("tags URL: " + g_provider.tagsUrl);

    bool matched = false;

    if (g_provider.kind == "anthropic") {
        // anthropic has no list-models endpoint; validate with a minimal test request
        array<string> candidates;
        if (!dialogModel.empty()) candidates.insertLast(dialogModel);
        if (!fallbackModel.empty() && fallbackModel != dialogModel) {
            candidates.insertLast(fallbackModel);
        }
        bool keyFellBack = false;
        string lastFail = "";
        for (uint i = 0; i < candidates.length() && !matched; i++) {
            string testBody = "{\"model\":\"" + EscapeJsonString(candidates[i])
                 + "\",\"max_tokens\":8,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}";
            Response tr = DoSend(g_provider.chatUrl, BuildHeader(), testBody);
            string fail = AnthropicTestFailure(tr);
            // auth failure may be the dialog key's fault; code-side key gets one retry with the same model
            if (fail == "auth" && !keyFellBack && !fallbackKey.empty()
                && fallbackKey != g_config.apiKey) {
                keyFellBack = true;
                g_logger.Warn("Endpoint rejected dialog API key, retrying with code-side key");
                g_config.apiKey = fallbackKey;
                g_logger.redactKey = g_config.apiKey;
                g_provider = DetectProvider();
                tr = DoSend(g_provider.chatUrl, BuildHeader(), testBody);
                fail = AnthropicTestFailure(tr);
            }
            if (fail.empty()) {
                g_config.modelName = candidates[i];
                if (i > 0) {
                    g_logger.Warn("Dialog model '" + candidates[0]
                         + "' not available, using fallback '" + g_config.modelName + "'");
                }
                matched = true;
            } else {
                lastFail = fail;
                g_logger.Warn("Login test failed for model '" + candidates[i] + "': " + fail);
            }
        }
        if (!matched) {
            g_isPluginActive = false;
            return "500 Login test failed: " + lastFail;
        }
    } else {
        Response r = DoSend(g_provider.tagsUrl, BuildHeader(), "");

        // dialog key may be wrong while code-side key works; switch happens because the key decides local vs cloud
        if (r.status == 0 || r.body.empty()) {
            if (!dialogKey.empty() && !fallbackKey.empty() && dialogKey != fallbackKey) {
                g_logger.Warn("Endpoint rejected dialog API key, retrying with code-side key");
                g_config.apiKey = fallbackKey;
                g_logger.redactKey = g_config.apiKey;
                g_provider = DetectProvider();
                r = DoSend(g_provider.tagsUrl, BuildHeader(), "");
            }
        }

        // HostUrlGetString returns no status code; empty body covers both unreachable and auth-with-empty-body
        if (r.status == 0 || r.body.empty()) {
            g_isPluginActive = false;
            return "500 Cannot reach endpoint (empty response): " + g_provider.tagsUrl;
        }

        array<string> available = ParseModelsList(r.body, g_config.apiFormat);
        if (available.length() == 0) {
            g_isPluginActive = false;
            return "500 No models found at endpoint (response parsed but list empty)";
        }
        LogModelList(available);

        // model candidates: dialog model first, file-side default as fallback
        array<string> candidates;
        if (!dialogModel.empty()) candidates.insertLast(dialogModel);
        if (!fallbackModel.empty() && fallbackModel != dialogModel) {
            candidates.insertLast(fallbackModel);
        }
        for (uint i = 0; i < candidates.length() && !matched; i++) {
            matched = TrySelectModelFromList(available, candidates[i]);
            if (matched && i > 0) {
                g_logger.Warn("Dialog model '" + candidates[0]
                     + "' not available, using fallback '" + g_config.modelName + "'");
            }
        }
        string requestedModel = dialogModel.empty() ? fallbackModel : dialogModel;
        if (!matched) {
            g_isPluginActive = false;
            g_logger.Warn("Model '" + requestedModel + "' not in available list");
            return "404 Model '" + requestedModel + "' not found. Available: "
                 + FirstNModels(available, 10);
        }
    }

    g_config.Save();
    g_isPluginActive = true;
    // fresh login resets context; prior history in another language/model would pollute subsequent prompts
    g_history.resize(0);
    g_logger.Info("Login ok — provider=" + g_provider.name + ", model=" + g_config.modelName);

    return "200 ok";
}

void ServerLogout() {
    g_config.Save();
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
    if (!g_isPluginActive) {
        LoadUserConfig();
        string loginResult = ServerLogin("", "");
        if (loginResult != "200 ok") return loginResult;
    } else {
        RefreshSavedConfig();
    }

    if (!IsTargetLanguageValid(DstLang)) {
        if (!g_langErrorShown) {
            g_langErrorShown = true;
            ShowError("Target language not specified", "Translation Failed");
        }
        g_logger.Warn("Target language not specified; returning subtitle untranslated");
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
    string translatedText = "";
    int retries = 0;
    while (true) {
        Response resp = SendTranslationRequest(requestData);
        string candidate = "";
        if (resp.status == 0 || resp.body.empty()) {
            g_logger.Warn("Translation failed (status=" + resp.status + "): " + Text);
        } else {
            candidate = TrimString(RemoveThinkingTags(ExtractTranslatedText(resp.body)));
            if (candidate.empty()) {
                g_logger.Warn("Translation returned empty content: " + Text);
            }
        }
        if (!candidate.empty()) {
            translatedText = candidate;
            break;
        }
        if (g_config.retryCount == 0) break;
        if (g_config.retryCount > 0 && retries >= g_config.retryCount) break;
        retries++;
        if (g_config.retryDelayMs > 0) HostSleep(g_config.retryDelayMs);
    }

    if (translatedText.empty()) {
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return "";
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
    string body = NormalizeJsonResponse(response);
    if (!reader.parse(body, root)) {
        g_logger.Warn("Failed to parse translation response");
        return "";
    }
    g_logger.Debug("response: " + body);

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
        string detail = errMsg;
        if (errType != "") detail += " [type=" + errType + "]";
        if (errCode != "") detail += " [code=" + errCode + "]";
        g_logger.Warn("API error: " + detail);
        return "";
    }

    if (g_provider.kind == "openai") {
        return ExtractOpenAIText(body);
    }
    if (g_provider.kind == "anthropic") {
        return ExtractAnthropicText(body);
    }
    return ExtractOllamaText(body);
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
    const string hex = "0123456789abcdef";
    string output = "";
    for (uint i = 0; i < input.length(); i++) {
        int c = input[i];
        // single-quoted literals are strings in potplayer's angelscript,
        // so compare against char codes instead
        if (c == 0x22)  { output += "\\\""; continue; }   // "
        if (c == 0x5C)  { output += "\\\\"; continue; }   // backslash
        if (c == 0x0A) { output += "\\n"; continue; }
        if (c == 0x0D) { output += "\\r"; continue; }
        if (c == 0x09) { output += "\\t"; continue; }
        if (c == 0x08) { output += "\\b"; continue; }
        if (c == 0x0C) { output += "\\f"; continue; }
        if (c < 0x20) {
            output += "\\u00" + hex.substr(uint((c >> 4) & 0xF), 1) + hex.substr(uint(c & 0xF), 1);
            continue;
        }
        output += input.substr(i, 1);
    }
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

    result.replace("{{context_raw}}", context);
    result.replace("{{text_to_translate}}", text);
    result.replace("{{from}}", includeFrom ? from : "the source language");
    result.replace("{{to}}", to);

    return result;
}
