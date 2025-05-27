/*
    Real-time subtitle translation for PotPlayer using ollama API
*/

string GetTitle() {
    return "{$CP949=Ollama번역$}{$CP950=Ollama翻譯$}{$CP0=Ollama live translate$}";
}

string GetVersion() {
    return "1.71";
}

string GetDesc() {
    return "{$CP949=本地 AI를 사용한 실시간 자막 번역$}{$CP950=使用本地 AI 的實時字幕翻譯$}{$CP0=Real-time subtitle translation using Ollama$}";
}

string GetLoginTitle() {
    return "{$CP949=本地 AI 모델 구성$}{$CP950=本地 AI 模型配置$}{$CP0=Ollama Model Configuration$}";
}

string GetLoginDesc() {
    return "{$CP949=모델 이름을 입력하십시오.$}{$CP950=請輸入模型名稱。$}{$CP0=Please enter the model name.$}";
}

string GetUserText() {
    return "{$CP949=모델 이름 (현     : " + selected_model + ")$}{$CP950=模型名稱 (目前: " + selected_model + ")$}{$CP0=Model Name (Current: " + selected_model + ")$}";
}

string GetPasswordText() {
    return "{$CP949=API 키:$}{$CP950=API 金鑰:$}{$CP0=API Key:$}";
}

// Model Settings
string DEFAULT_MODEL_NAME = "qwen3:14b";
bool bIsReasoningModel = true;
bool bActivateReasoning = false;
string sReasoningDeactivatePrompt = "/no_think ";
string sReasoningActivatePrompt = "/think ";
float temperature = 0;
// Prompts
string systemPrompt = "Act as a professional, authentic translation engine dedicated to providing accurate and fluent translations of subtitles. ONLY provide the translated subtitle text without any additional information.";
string userPromptWithContext = 
    "You are a professional subtitle translator skilled in accurate and culturally appropriate translations. I may provide additional context to help clarify the meaning. Use this context to understand the subtitle's meaning and provide an accurate translation. Follow these rules:\n"
    "1. First, perform a direct translation based on the original text without adding any information.\n"
    "2. Then, reinterpret the translation to make it sound more natural and understandable in the target language, while preserving the original meaning.\n"
    "3. Use the provided context and cultural cues to ensure the translation aligns with local language norms and nuances.\n"
    "4. Your output must only include the translated text—do not include any explanations, context, or commentary.\n";

string userPromptWithoutContext = 
    "You are a professional subtitle translator skilled in Filmography. Understand the cultural background in different languages. Please abide by the following rules:\n"
    "1. Perform a direct translation based strictly on the text provided, without adding any additional information.\n"
    "2. Perform a reinterpretation based on the direct translation, making the content more natural and understandable while keeping the original meaning.\n"
    "3. Rely solely on the given text and general linguistic knowledge—do not assume or invent missing context.\n"
    "4. Your output must contain only the translation, without any commentary, explanation, or context.\n";
//Context History
bool bShouldUseContextHistory = true;
array<string> contextHistory = {};
int historyCount = 3;
int historyMaxSize = 10; 
// Ollama API settings
string api_key = "";
string selected_model = DEFAULT_MODEL_NAME; 
string UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)";
string api_url = "http://127.0.0.1:11434/v1/chat/completions"; 
string api_url_base = "http://127.0.0.1:11434";

// exit handler
bool bDoesExit = false;
// all languages supported
array<string> LangTable = 
{
    "Auto", "af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca",
    "ceb", "ny", "zh-CN",
    "zh-TW", "co", "hr", "cs", "da", "nl", "en", "eo", "et", "tl", "fi", "fr",
    "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he", "hi", "hmn", "hu", "is", "ig", "id", "ga", "it", "ja", "jw", "kn", "kk", "km",
    "ko", "ku", "ky", "lo", "la", "lv", "lt", "lb", "mk", "ms", "mg", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "ps", "fa", "pl", "pt",
    "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw", "sv", "tg", "ta", "te", "th", "tr", "uk",
    "ur", "uz", "vi", "cy", "xh", "yi", "yo", "zu"
};

// get source language list
array<string> GetSrcLangs() {
    array<string> ret = LangTable;
    return ret;
}

// get destination language list
array<string> GetDstLangs() {
    array<string> ret = LangTable;
    return ret;
}

// Login to the server with model name and API key
string ServerLogin(string User, string Pass) {

    selected_model = User.Trim();
    api_key = Pass.Trim();

    selected_model.MakeLower();

    array<string> names = GetOllamaModelNames();

    if (selected_model.empty()) {
        HostPrintUTF8("{$CP949=모델 이름이 입력되지 않았습니다. 유효한 모델 이름을 입력하십시오.$}{$CP950=模型名稱未輸入，請輸入有效的模型名稱。$}{$CP0=Model name not entered. Please enter a valid model name.$}\n");
        selected_model = DEFAULT_MODEL_NAME;
    }

    int modelscount = names.size();
    if (modelscount == 0){
        return "Ollama未返回有效的模型名称数据，请确认Ollama是否已运行或已有下载的模型。Ollama did not return valid model name data. Please confirm whether Ollama is running or has any downloaded models.";
    }
    bool matched = false;
    for (int i = 0; i < modelscount; i++){
        if (selected_model == names[i]){
            matched = true;
            break;
        }
    }
    if (!matched){
        HostPrintUTF8("{$CP949=지원되지 않는 모델입니다. 지원되는 모델을 입력하십시오.$}{$CP950=不支援的模型，輸入支援的模型。$}{$CP0=Unsupported model. Please enter a supported model.$}\n");
        return "未从Ollama中找到模型：" + selected_model;
    }
    HostSaveString("api_key_ollama", api_key);
    HostSaveString("selected_model_ollama", selected_model);

    HostPrintUTF8("{$CP949=API 키와 모델 이름이 성공적으로 설정되었습니다.$}{$CP950=API 金鑰與模型名稱已成功配置。$}{$CP0=API Key and model name successfully configured.$}\n");

    bDoesExit = false;
    return "200 ok";
}

// ServerLogout 
void ServerLogout() {
    api_key = "";
    selected_model = DEFAULT_MODEL_NAME; 
    HostSaveString("api_key_ollama", "");
    HostSaveString("selected_model_ollama", selected_model);
    HostPrintUTF8("{$CP949=성공적으로 로그아웃되었습니다.$}{$CP950=已成功登出。$}{$CP0=Successfully logged out.$}\n");
    bDoesExit = true;
}

string Translate(string Text, string &in SrcLang, string &in DstLang) {
    if(bDoesExit){
        return "";
    }
    selected_model = HostLoadString("selected_model_ollama", "qwen3:14b");

    if (DstLang.empty() || DstLang == "{$CP949=자동 감지$}{$CP950=自動檢測$}{$CP0=Auto Detect$}") {
        HostPrintUTF8("{$CP949=목표 언어가 지정되지 않았습니다.$}{$CP950=目標語言未指定。$}{$CP0=Target language not specified.$}\n");
        return "";
    }

    string UNICODE_RLE = "\u202B";

    if (SrcLang.empty() || SrcLang == "{$CP949=자동 감지$}{$CP950=自動檢測$}{$CP0=Auto Detect$}") {
        SrcLang = "";
    }
    // prompt
    string prompt = "" ;

    // Toggle for reasoning model
    if(bIsReasoningModel){
        prompt += bActivateReasoning ? sReasoningActivatePrompt : sReasoningDeactivatePrompt;
    }
    // Context History
    if(bShouldUseContextHistory){
        prompt += userPromptWithContext + "\n";
        string context = "The Context text: \n";
        context += handleContextHistory(Text);
        prompt += context;
    }
    else{
        prompt += userPromptWithoutContext+"\n";
    }
    // Target Language
    prompt += "Now translate the following text";
    if (!SrcLang.empty()) {
        prompt += " from " + SrcLang;
    }
    prompt += " to " + DstLang + " :\n";
    prompt +=  Text;


    string escapedSystemMsg = JsonEscape(systemPrompt);
    string escapedUserMsg = JsonEscape(prompt);

    string requestData = "{\"model\":\"" + selected_model + "\","
                        "\"messages\":[{\"role\":\"system\",\"content\":\"" + escapedSystemMsg + "\"},"
                        "{\"role\":\"user\",\"content\":\"" + escapedUserMsg + "\"}],"
                        "\"temperature\":" + temperature + "}";

    string headers = "Content-Type: application/json";

    // Send the translation request
    string response = HostUrlGetString(api_url, UserAgent, headers, requestData);
    if (response.empty()) {
        HostPrintUTF8("{$CP949=번역 요청이 실패했습니다.$}{$CP950=翻譯請求失敗。$}{$CP0=Translation request failed.$}\n");
        return "";
    }

    // Parse the JSON response
    JsonReader Reader;
    JsonValue Root;
    if (!Reader.parse(response, Root)) {
        HostPrintUTF8("{$CP949=API 응답을 분석하지 못했습니다.$}{$CP950=無法解析 API 回應。$}{$CP0=Failed to parse API response.$}\n");
        return "";
    }

    JsonValue choices = Root["choices"];
    if (choices.isArray() && choices[0]["message"]["content"].isString()) {
        string translatedText = choices[0]["message"]["content"].asString();

        // trim <think> and contents 
        translatedText = RemoveThinkTags(translatedText);

        if (DstLang == "fa" || DstLang == "ar" || DstLang == "he") {
            translatedText = UNICODE_RLE + translatedText;
        }
        SrcLang = "UTF8";
        DstLang = "UTF8";

        // Trim final translated text 
        translatedText = Trim(translatedText);
        
        return translatedText;
    }

    HostPrintUTF8("{$CP949=번역이 실패했습니다.$}{$CP950=翻譯失敗。$}{$CP0=Translation failed.$}\n");
    return "";
}

string handleContextHistory(string &in currentText) {
    contextHistory.insertLast(currentText);
    if (contextHistory.length() > historyMaxSize) {
        contextHistory.removeAt(0);
    }
    int startIndex = max(0, int(contextHistory.length()) - historyCount - 1);
    string historyContext = "";
    for (int i = startIndex; i < int(contextHistory.length()) - 1; ++i) {
        historyContext += contextHistory[i] + "\n";
    }

    return historyContext;
}
int max(int a, int b) {
    return (a > b) ? a : b;
}


// clean up <think> for reasoning model 
string RemoveThinkTags(string text) {
    int startPos = 0;
    while (true) {
        int openPos = text.find("<think>", startPos);
        if (openPos == -1) break;
        int closePos = text.find("</think>", openPos);
        if (closePos == -1) break;
        text = text.substr(0, openPos) + text.substr(closePos + 8);
        startPos = openPos;
    }
    return text;
}
string JsonEscape(const string &in input) {
    string output = input;
    output.replace("\\", "\\\\");
    output.replace("\"", "\\\"");
    output.replace("\n", "\\n");
    output.replace("\r", "\\r");
    output.replace("\t", "\\t");
    return output;
}
// custom trim function to remove leading and trailing whitespace characters
string Trim(const string &in s) {
    int len = int(s.length()); 
    int start = 0;
    int end = len - 1;
    while (start <= end && 
      (s.substr(start,1) == " " || s.substr(start,1) == "\n" || s.substr(start,1) == "\r" || s.substr(start,1) == "\t"))
    start++;
    while (end >= start && 
        (s.substr(end,1) == " " || s.substr(end,1) == "\n" || s.substr(end,1) == "\r" || s.substr(end,1) == "\t"))
        end--;
    if (start > end) return "";
    return s.substr(uint(start), uint(end - start + 1));
}


// Init
void OnInitialize() {
    HostPrintUTF8("{$CP949=ollama 번역 플러그인이 로드되었습니다.$}{$CP950=ollama 翻譯插件已加載。$}{$CP0=ollama translation plugin loaded.$}\n");
    // 从临时存储中加载模型名称和 API Key（如果已保存），使用新的键名
    api_key = HostLoadString("api_key_ollama", "");
    selected_model = HostLoadString("selected_model_ollama", "qwen3:14b");
    if (!api_key.empty()) {
        HostPrintUTF8("{$CP949=저장된 API 키와 모델 이름이 로드되었습니다.$}{$CP950=已加載保存的 API 金鑰與模型名稱。$}{$CP0=Saved API Key and model name loaded.$}\n");
    }
}
// Finalize
void OnFinalize() {
    HostPrintUTF8("{$CP949=ollama 번역 플러그인이 언로드되었습니다.$}{$CP950=ollama 翻譯插件已卸載。$}{$CP0=ollama translation plugin unloaded.$}\n");
}

array<string> GetOllamaModelNames(){
    string url = api_url_base + "/api/tags";
    string headers = "Content-Type: application/json";
    string resp = HostUrlGetString(url,UserAgent, headers, "");
    JsonReader reader;
    JsonValue root;
    if (!reader.parse(resp, root)){
        HostPrintUTF8("{$CP0=Failed to parse the list of the deployed models from Ollama.$}{$CP936=解析Ollama本地部署模型名称列表时失败：无法解析json。}");
        array<string> empty;
        return empty;
    }
    JsonValue models = root["models"];
    int count = models.size();
    int i = 0;
    array<string> res;
    for (i=0 ; i<count;i++){
        res.insertLast(models[i]["name"].asString());
    }
    return res;
}