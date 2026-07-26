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
    // reasoning
    bool enableThinking = false;
    string thinkStrength = "";   // empty or low/medium/high
    // context
    bool contextEnabled = true;
    int contextMaxSize = 20;
    int contextCount = 7;
    string contextPrompt = CONTEXT_PROMPT_BASE;
    // cache
    bool cacheEnabled = false;
    int cacheMaxEntries = 500;
    // transport: false = hosturlgetstring, true = httpclient (real status codes)
    bool useHttpClient = false;

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
    string kind;                   // ollama | rest | openai | anthropic
    string chatUrl;                // full url for chat completion
    string tagsUrl;                // full url for model list
    bool needsAuth;                // include any auth header
    bool authIsBearer;             // true: bearer; false: x-api-key
    bool needsSystemTopLevel;      // anthropic: system in top field, not messages
    string name;                   // human-readable, for logging
}

// ========================
// endpoint normalizer
// ========================
// append correct suffix per format; host or full url both ok

class EndpointNormalizer {
    string Resolve(const string &in raw, const string &in apiFormat) {
        string url = TrimString(raw);
        if (url.empty()) return "";

        // strip trailing slashes
        while (url.length() > 0 && url.substr(url.length() - 1, 1) == "/") {
            url = url.substr(0, url.length() - 1);
        }

        // already has chat endpoint; use as-is
        if (apiFormat == "ollama") {
            if (url.find("/api/chat") != -1) return url;
        } else if (apiFormat == "rest") {
            if (url.find("/api/v1/chat") != -1) return url;
        } else if (apiFormat == "openai") {
            if (url.find("/chat/completions") != -1) return url;
        } else if (apiFormat == "anthropic") {
            if (url.find("/v1/messages") != -1 || url.find("/messages") != -1) return url;
        }

        // default suffixes per format
        if (apiFormat == "ollama") {
            return url + "/api/chat";
        } else if (apiFormat == "rest") {
            return url + "/api/v1/chat";
        } else if (apiFormat == "openai") {
            // ends with /v1: append /chat/completions; else add /v1/chat/completions
            if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
                return url + "/chat/completions";
            }
            return url + "/v1/chat/completions";
        } else if (apiFormat == "anthropic") {
            // ends with /v1: append /messages; else add /v1/messages
            if (url.length() >= 3 && url.substr(url.length() - 3, 3) == "/v1") {
                return url + "/messages";
            }
            return url + "/v1/messages";
        }
        return url;
    }

    string ResolveModelsList(const string &in chatUrl, const string &in apiFormat) {
        // chat and models endpoints are paired per format
        string chatMarker;
        string modelsMarker;
        if (apiFormat == "ollama") {
            chatMarker = "/api/chat";
            modelsMarker = "/api/tags";
        } else if (apiFormat == "rest") {
            chatMarker = "/api/v1/chat";
            modelsMarker = "/api/v1/models";
        } else if (apiFormat == "openai") {
            chatMarker = "/chat/completions";
            modelsMarker = "/models";
        } else if (apiFormat == "anthropic") {
            return "";  // no list endpoint
        } else {
            return "";
        }

        string base = chatUrl;
        int pos = base.find(chatMarker);
        if (pos != -1) base = base.substr(0, uint(pos));
        return base + modelsMarker;
    }
}

// ========================
// provider detector
// ========================
// shape determined by config.apiformat

class ProviderDetector {
    ProviderInfo Detect() {
        ProviderInfo p;
        p.kind = g_config.apiFormat;

        // lms rest, openai-compat, anthropic-compat default to local lm studio
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
            p.needsSystemTopLevel = false;
            p.name = g_config.apiKey.empty() ? "Ollama Local" : "Ollama Cloud";
        } else if (p.kind == "rest") {
            p.chatUrl = "http://127.0.0.1:1234/api/v1/chat";
            p.tagsUrl = "http://127.0.0.1:1234/api/v1/models";
            p.needsAuth = !g_config.apiKey.empty();
            p.authIsBearer = true;
            p.needsSystemTopLevel = false;
            p.name = "LM Studio REST";
        } else if (p.kind == "openai") {
            p.chatUrl = "http://127.0.0.1:1234/v1/chat/completions";
            p.tagsUrl = "http://127.0.0.1:1234/v1/models";
            p.needsAuth = !g_config.apiKey.empty();
            p.authIsBearer = true;
            p.needsSystemTopLevel = false;
            p.name = "OpenAI-compat";
        } else if (p.kind == "anthropic") {
            p.chatUrl = "http://127.0.0.1:1234/v1/messages";
            p.tagsUrl = "";  // no list endpoint
            p.needsAuth = !g_config.apiKey.empty();
            p.authIsBearer = false;  // x-api-key, not bearer
            p.needsSystemTopLevel = true;
            p.name = "Anthropic-compat";
        } else {
            // unknown format: fall back to ollama to avoid lockout
            g_logger.Warn("Unknown apiFormat '" + p.kind + "', defaulting to ollama");
            p.kind = "ollama";
            p.chatUrl = g_config.baseUrl + "/api/chat";
            p.tagsUrl = g_config.baseUrl + "/api/tags";
            p.needsAuth = false;
            p.authIsBearer = true;
            p.needsSystemTopLevel = false;
            p.name = "Ollama Local (fallback)";
        }

        if (!g_config.customEndpoint.empty()) {
            p.chatUrl = g_endpointNormalizer.Resolve(g_config.customEndpoint, p.kind);
            if (!p.tagsUrl.empty()) {
                p.tagsUrl = g_endpointNormalizer.ResolveModelsList(p.chatUrl, p.kind);
            }
        }

        return p;
    }
}

// ========================
// http response
// ========================

class Response {
    int status = 0;
    string body = "";
}

// ========================
// text cleaner
// ========================

class TextCleaner {
    string Normalize(const string &in t) {
        string s = TrimString(t);
        while (s.find("  ") != -1) s.replace("  ", " ");
        return s;
    }

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
}

// ========================
// http transport
// ========================

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
        if (r.status == 0) return true;        // network failure
        if (r.status >= 500) return true;      // server error
        if (r.status == 429) return true;      // rate limit
        // skip 200 with body-error; those are permanent
        return false;
    }

    bool HasErrorField(const string &in body) {
        if (body.empty()) return false;
        JsonReader reader;
        JsonValue root;
        if (!reader.parse(body, root)) return false;
        if (!root.isObject()) return false;
        JsonValue err = root["error"];
        return !err.isNull();
    }
}

// ========================
// context history
// ========================

class ContextHistory {
    array<string> history;

    void AddEntry(const string &in source, const string &in translation) {
        if (!g_config.contextEnabled || source.empty()) return;
        string entry = source + " ⇒ " + translation;
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
// translation cache
// ========================

class TranslationCache {
    dictionary mem;
    array<string> lru;
    bool diskEnabled = false;
    int maxEntries = 500;
    string iniFilename = "ollama_tr_cache.ini";
    string section = "t";
    bool loaded = false;

    string ComputeKey(const string &in text, const string &in src, const string &in dst, const string &in model) {
        return HostHashSHA256(text + "|" + src + "|" + dst + "|" + model);
    }

    bool TryGet(const string &in key, string &out val) {
        if (!loaded) Load();
        if (mem.exists(key)) {
            val = string(mem[key]);
            return true;
        }
        return false;
    }

    void Set(const string &in key, const string &in val) {
        if (!loaded) Load();
        if (mem.exists(key)) {
            mem[key] = val;
            return;
        }
        if (int(mem.getSize()) >= maxEntries) EvictOldest();
        mem[key] = val;
        lru.insertLast(key);
        if (diskEnabled) Save();
    }

    void EvictOldest() {
        if (lru.length() == 0) return;
        string oldest = lru[0];
        lru.removeAt(0);
        mem.delete(oldest);
    }

    void Load() {
        loaded = true;
        diskEnabled = g_config.cacheEnabled;
        maxEntries = g_config.cacheMaxEntries;
        if (!diskEnabled) {
            g_logger.Info("Cache: memory-only mode (disk disabled)");
            return;
        }

        IniFile ini;
        if (!ini.Open(iniFilename)) {
            g_logger.Info("Cache: no existing disk file, starting fresh");
            return;
        }
        array<string> keys;
        ini.GetItems(section, keys);
        for (uint i = 0; i < keys.length(); i++) {
            string key = keys[i];
            bool ok = false;
            string val = ini.GetProfileString(section, key, "", ok);
            if (ok && !val.empty()) {
                mem[key] = UnescapeIniValue(val);
                lru.insertLast(key);
            }
        }
        g_logger.Info("Cache: loaded " + mem.getSize() + " entries from disk");
    }

    void Save() {
        if (!diskEnabled) return;
        IniFile ini;
        ini.Open(iniFilename);
        ini.ClearSection(section);
        for (uint i = 0; i < lru.length(); i++) {
            string key = lru[i];
            string val = string(mem[key]);
            ini.WriteProfileString(section, key, EscapeIniValue(val));
        }
        if (!ini.Save(iniFilename)) {
            g_logger.Warn("Cache: failed to save disk file");
        }
    }

    string EscapeIniValue(const string &in s) {
        string r = s;
        r.replace("\\", "\\\\");
        r.replace("\n", "\\n");
        r.replace("\r", "\\r");
        r.replace("\t", "\\t");
        return r;
    }

    string UnescapeIniValue(const string &in s) {
        string r = s;
        r.replace("\\t", "\t");
        r.replace("\\r", "\r");
        r.replace("\\n", "\n");
        r.replace("\\\\", "\\");
        return r;
    }
}

// ========================
// request builders
// ========================
// duck-typed: each builder exposes Build(escModel, sys, user)
// adding a new format = new builder + branch in BuildTranslationRequest

class OllamaRequestBuilder {
    string Build(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
        string messages = "[{\"role\":\"system\",\"content\":\"" + EscapeJsonString(sysContent)
             + "\"},{\"role\":\"user\",\"content\":\"" + EscapeJsonString(userContent) + "\"}]";
        string req = "{\"model\":\"" + escapedModel + "\",\"messages\":" + messages;

        // options: num_ctx (when set) + temperature + top_p
        string opts;
        if (g_config.contextLength > 0) {
            opts = ",\"options\":{\"num_ctx\":" + g_config.contextLength
                 + ",\"temperature\":" + g_config.temperature
                 + ",\"top_p\":" + g_config.topP + "}";
        } else {
            opts = ",\"options\":{\"temperature\":" + g_config.temperature
                 + ",\"top_p\":" + g_config.topP + "}";
        }
        req += opts;

        // always emit think to avoid qwen3 default-think timeout
        req += ",\"think\":" + GetOllamaThinkValue();
        req += ",\"stream\":false}";
        return req;
    }

    string GetOllamaThinkValue() {
        if (!g_config.enableThinking) return "false";
        if (g_config.thinkStrength.empty()) return "true";
        return "\"" + g_config.thinkStrength + "\"";
    }
}

class LMSRestRequestBuilder {
    // lms rest v1: input + system_prompt top-level + flat fields
    string Build(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
        string req = "{\"model\":\"" + escapedModel
             + "\",\"input\":\"" + EscapeJsonString(userContent)
             + "\",\"system_prompt\":\"" + EscapeJsonString(sysContent)
             + "\",\"temperature\":" + g_config.temperature
             + ",\"top_p\":" + g_config.topP
             + ",\"max_output_tokens\":" + g_config.maxTokens;
        if (g_config.contextLength > 0) {
            req += ",\"context_length\":" + g_config.contextLength;
        }
        req += ",\"reasoning\":\"" + GetRestReasoningValue() + "\"";
        req += ",\"stream\":false}";
        return req;
    }

    string GetRestReasoningValue() {
        if (!g_config.enableThinking) return "off";
        if (g_config.thinkStrength.empty()) return "on";
        return "\"" + g_config.thinkStrength + "\"";
    }
}

class OpenAIRequestBuilder {
    // openai: messages array + top-level params, max_completion_tokens
    string Build(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
        string messages = "[{\"role\":\"system\",\"content\":\"" + EscapeJsonString(sysContent)
             + "\"},{\"role\":\"user\",\"content\":\"" + EscapeJsonString(userContent) + "\"}]";
        string req = "{\"model\":\"" + escapedModel + "\",\"messages\":" + messages
             + ",\"max_completion_tokens\":" + g_config.maxTokens
             + ",\"temperature\":" + g_config.temperature
             + ",\"top_p\":" + g_config.topP
             + ",\"reasoning_effort\":\"" + GetOpenAIReasoningEffortValue() + "\""
             + ",\"stream\":false}";
        return req;
    }

    string GetOpenAIReasoningEffortValue() {
        if (!g_config.enableThinking) return "none";
        if (g_config.thinkStrength.empty()) return "medium";
        return g_config.thinkStrength;
    }
}

class AnthropicRequestBuilder {
    // anthropic: system top-level, max_tokens required
    string Build(const string &in escapedModel, const string &in sysContent, const string &in userContent) {
        string req = "{\"model\":\"" + escapedModel
             + "\",\"system\":\"" + EscapeJsonString(sysContent)
             + "\",\"max_tokens\":" + g_config.maxTokens
             + ",\"messages\":[{\"role\":\"user\",\"content\":\""
             + EscapeJsonString(userContent) + "\"}]"
             + ",\"temperature\":" + g_config.temperature
             + ",\"thinking\":" + GetAnthropicThinkingValue()
             + "}";
        return req;
    }

    string GetAnthropicThinkingValue() {
        if (!g_config.enableThinking) return "{\"type\":\"disabled\"}";
        // budget_tokens required when enabled; map strength to budgets
        int budget = g_config.contextLength / 2;
        if (g_config.thinkStrength == "low") budget = 1024;
        else if (g_config.thinkStrength == "medium") budget = 2048;
        else if (g_config.thinkStrength == "high") budget = 4096;
        return "{\"type\":\"enabled\",\"budget_tokens\":" + budget + "}";
    }
}

// ========================
// response parsers
// ========================

class OllamaResponseParser {
    string Extract(const string &in body) {
        JsonReader reader;
        JsonValue root;
        if (!reader.parse(body, root)) return "";
        JsonValue msg = root["message"];
        if (!msg.isObject()) return "";
        JsonValue content = msg["content"];
        if (!content.isString()) return "";
        return content.asString();
    }
}

class LMSRestResponseParser {
    // lms rest: find first output[] item with type=="message"
    string Extract(const string &in body) {
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
}

class OpenAIResponseParser {
    string Extract(const string &in body) {
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
}

class AnthropicResponseParser {
    // anthropic: find first content[] item with type=="text"
    string Extract(const string &in body) {
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
}

// ========================
// api dispatcher
// ========================
// thin dispatcher; format-specific logic lives in builders/parsers
// new format = new builder + new parser + branch in BuildTranslationRequest + ExtractTranslatedText

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
        string escapedModel = EscapeJsonString(g_config.modelName);

        if (g_provider.kind == "ollama") {
            OllamaRequestBuilder b;
            return b.Build(escapedModel, sysContent, userContent);
        } else if (g_provider.kind == "rest") {
            LMSRestRequestBuilder b;
            return b.Build(escapedModel, sysContent, userContent);
        } else if (g_provider.kind == "openai") {
            OpenAIRequestBuilder b;
            return b.Build(escapedModel, sysContent, userContent);
        } else if (g_provider.kind == "anthropic") {
            AnthropicRequestBuilder b;
            return b.Build(escapedModel, sysContent, userContent);
        }
        // fallback
        OllamaRequestBuilder b;
        return b.Build(escapedModel, sysContent, userContent);
    }

    string BuildUrl() {
        return g_provider.chatUrl;
    }

    string BuildHeader() {
        string header = contentType + "\nAccept: application/json";
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
}

// ========================
// global instances
// ========================
Config g_config;
ContextHistory g_contextHistory;
TranslationCache g_cache;
Api g_api;
HttpTransport g_httpTransport;
TextCleaner g_textCleaner;
ProviderDetector g_providerDetector;
EndpointNormalizer g_endpointNormalizer;
ProviderInfo g_provider;
bool g_isPluginActive = true;

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
    if (body.empty()) {
        g_logger.Warn("Models list response body is empty");
        return result;
    }

    JsonReader reader;
    JsonValue root;
    string normalized = NormalizeJsonResponse(body);
    if (!reader.parse(normalized, root)) {
        g_logger.Warn("Failed to parse models list JSON");
        LogModelsListPreview(body);
        return result;
    }

    // try common list and id field names per server shape
    array<string> listKeys;
    array<string> idKeys;
    if (apiFormat == "ollama") {
        listKeys.insertLast("models");
        idKeys.insertLast("name"); idKeys.insertLast("id"); idKeys.insertLast("model");
    } else if (apiFormat == "anthropic") {
        return result;
    } else {
        listKeys.insertLast("data"); listKeys.insertLast("models"); listKeys.insertLast("items");
        idKeys.insertLast("key"); idKeys.insertLast("id"); idKeys.insertLast("name"); idKeys.insertLast("model_id"); idKeys.insertLast("model");
    }

    JsonValue list;
    bool listFound = false;
    for (uint i = 0; i < listKeys.length(); i++) {
        JsonValue v = root[listKeys[i]];
        if (v.isArray()) {
            list = v;
            listFound = true;
            break;
        }
    }
    if (!listFound) {
        g_logger.Warn("No model list array found in response (tried: data/models/items)");
        LogModelsListPreview(body);
        return result;
    }

    for (uint i = 0; i < idKeys.length(); i++) {
        bool anyFound = false;
        for (int j = 0; j < list.size(); j++) {
            JsonValue m = list[j];
            if (m.isObject() && m[idKeys[i]].isString()) {
                result.insertLast(m[idKeys[i]].asString());
                anyFound = true;
            }
        }
        if (anyFound) break;
    }

    if (result.length() == 0) {
        g_logger.Warn("Models list parsed but no entries extracted (tried: id/name/model_id/model)");
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

    g_provider = g_providerDetector.Detect();
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

    if (!g_textCleaner.IsTranslatable(Text)) {
        g_logger.Debug("Skipping non-translatable input: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return Text;
    }

    string srcLangCode = NormalizeLanguage(SrcLang);
    string cacheKey = g_cache.ComputeKey(Text, srcLangCode, DstLang, g_config.modelName);
    string cached;
    if (g_cache.TryGet(cacheKey, cached)) {
        g_logger.Debug("Cache hit: " + Text);
        SrcLang = "UTF8";
        DstLang = "UTF8";
        return cached;
    }

    string requestData = g_api.BuildTranslationRequest(Text, srcLangCode, DstLang);
    Response resp = g_api.SendTranslationRequest(requestData);
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

    g_cache.Set(cacheKey, translatedText);
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
    if (g_provider.kind == "ollama") {
        OllamaResponseParser p;
        return p.Extract(response);
    } else if (g_provider.kind == "rest") {
        LMSRestResponseParser p;
        return p.Extract(response);
    } else if (g_provider.kind == "openai") {
        OpenAIResponseParser p;
        return p.Extract(response);
    } else if (g_provider.kind == "anthropic") {
        AnthropicResponseParser p;
        return p.Extract(response);
    }
    OllamaResponseParser p;
    return p.Extract(response);
}

// ========================
// utilities
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

    return result;
}