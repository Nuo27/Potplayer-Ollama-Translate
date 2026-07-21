# PotPlayer Ollama Real-Time Translation Plugin

This is a plugin developed for PotPlayer that enables real-time subtitle translation using Ollama or other custom APIs.

<div align="center">
  <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/README.md">简体中文</a> | <strong>English</strong>
</div>

## Features

- Supports custom translation prompts → [Prompt Templates](#prompt-templates)
- API support

  - Native local Ollama API
  - Ollama Cloud and custom APIs → [Advanced Configuration](#advanced-configuration-and-debug)

- Supports configuring model reasoning/thinking features, including qwen3, deepsseek-r1, gpt-oss → [Reasoning Configuration](#reasoning-configuration)
- Configurable context history → [Context History](#context-history)
- Customizable LLM parameter configuration → [Model Configuration](#model-configuration)

## Table of Contents

- [PotPlayer Ollama Real-Time Translation Plugin](#potplayer-ollama-real-time-translation-plugin)
  - [Features](#features)
  - [Table of Contents](#table-of-contents)
  - [Install the Plugin](#install-the-plugin)
  - [Advanced Configuration and Debug](#advanced-configuration-and-debug)
  - [Notes](#notes)
   - [Updates](#updates)
     - [V3.0 Major Updates](#v30-major-updates)
     - [V2.4 Major Updates](#v24-major-updates)
     - [V2.3 Major Updates](#v23-major-updates)
  - [TODO](#todo)
  - [About the Project](#about-the-project)
  - [Custom Configuration](#custom-configuration)
    - [Model Selection](#model-selection)
    - [Model Configuration](#model-configuration)
    - [Reasoning Configuration](#reasoning-configuration)
    - [Context History](#context-history)
    - [Prompt Templates](#prompt-templates)
  - [Performance](#performance)
    - [Ollama](#ollama)
    - [External API](#external-api)
  - [References](#references)
  - [License](#license)

## Install the Plugin

1. Go to the [Release page](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases) and download the `.7z` or `.zip` archive. After extraction, you will get a `.as` file and an `.ico` file.
2. Copy both files into the PotPlayer installation directory:
   `...\DAUM\PotPlayer\Extension\Subtitle\Translate`
3. Open the `.as` file with a text editor or IDE and modify the value of `DEFAULT_MODEL_NAME` to your **fallback model name**. If no model is configured in the extension settings, this model will be used by default.
4. Launch PotPlayer, right-click the video window, go to
   `Subtitles → Real-time Subtitle Translation`, select **Ollama Translate**, then open **Real-time Subtitle Translation Settings**.
   You can also open this panel via `Preferences → Extensions → Real-time Subtitle Translation`.
5. In the real-time subtitle translation settings, set the translation engine to **Ollama Translate**. Usually, the source language can remain `auto`, and you can choose the target language as needed.
6. In the account settings, set **Model Name** to the name of the model you are using.

   - If you are using **Ollama Cloud**, enter the corresponding **API Key**.
   - If you are using a local Ollama model, leave it empty.
     After confirming, make sure the status shows **“Ready”**.

7. Once configured, the plugin is ready to use. You can click the **Test** button to send a translation request and verify the result.

> Due to PotPlayer’s internal mechanism, the **Test** button returns cached translate results. So after changing settings, slightly modify the test text before testing again to see updated translation results.

## Advanced Configuration and Debug

- **Custom Prompts**: In [Prompt Templates](#prompt-templates), you can customize system and user prompts based on the templates to adapt to different models and translation needs.
- **Ollama Cloud**: Entering an Ollama Cloud API Key in the account settings and using Ollama Cloud models for translation.

  - You do not need to manually fill in `g_customEndpoint`, keep it empty. The plugin will automatically detect whether to use local or cloud based on whether the API Key is empty.

- **Custom API**: Supports custom OpenAI-compatible API endpoints.

  - If you are using an OpenAI-compatible API, enter the base URL into `g_customEndpoint`.

    - Examples:

      - `http://localhost:1234/v1/chat/completions` – LM Studio
      - `https://openrouter.ai/api/v1/chat/completions` – OpenRouter API

    - The plugin will detect whether an OpenAI-compatible API is being used and check if the model is in the supported list.

  - If you provide a custom endpoint, ensure it is complete and ends with `/chat/completions`.

    - Example:
      - `https://api.z.ai/api/paas/v4/chat/completions` - Z.AI GLM API
      - `https://api.deepseek.com/chat/completions` - DeepSeek API
    - The plugin will skip the model check and directly use the endpoint and model provided for translation.

- **Debug**:

  - Uncomment `HostOpenConsole` in the `OnInitialize` method to open the console and view runtime output.
  - Use `HostPrintUTF8` to output debug information.
  - Use `HostMessageBox` to display message boxes.

## Notes

- Local Ollama users **must ensure that both the model and Ollama are updated to version >= 0.9.0**.
- Make sure to use models that **support multilingual tasks**.
- Adjust prompts according to your desired translation quality.
- Generally, reasoning/thinking **should be disabled by default**, as it significantly affects translation speed and is usually unnecessary for simple translation tasks.
- Strongly recommended to use **Instruct** models, such as `qwen3.5:27b`. Recommended models can be found in the [Performance](#performance) section.

## Updates

### V3.0 Major Updates

Architecture-level rewrite, rolled out in phases. This release is **Phase 1: Foundation refactor and critical bug fixes**.

- Introduced `Logger` class as the single output funnel with **automatic API key redaction** (fixes the security issue where the API key was written in cleartext to the log)
- Log levels: `Info / Warn / Error / Debug`; Debug gated by `g_logger.debug`
- Removed dead code: `SYSTEM_PROMPT_LONG` (50-line unreferenced constant), `RunLoginTest` (commented-out function)
- Removed `DEFAULT_MODEL_NAME` constant and its fallback logic
- Removed the `from  to` / `while "  "` hack inside `ApplyTemplate` (fixes a data-corruption bug that mangled user prompt templates by collapsing intentional double spaces)
- Removed the `{{text}}` alias variable (duplicate of `{{text_to_translate}}`)
- Added `Config.Load()/Save()` methods to centralize config I/O
- Added `SelfTest()` startup smoke check (pure-function invariant verification)
- Fixed inconsistent version strings (`GetVersion()` now returns `"3.0"`, aligned with docs and tags)

> Phases 2–4 will address: reliability and concurrency, provider split with new prompt system, and the translation cache.

### V2.4 Major Updates

- Refactored plugin configuration and API layer
- Implemented richer context history and context prompt templates with source/translation/lang metadata
- Context is only injected into user/system prompts when enabled
- Refactored login flow into native and custom handlers
- Misc: tweaked language normalization and template substitution

### V2.3 Major Updates

- Refactored prompt templates and processing. You can now use variables to replace prompt content.
- Refactored error handling and optimized model/API detection logic.
- Added support for custom APIs. You can now specify a custom API address and API key to use external LLM for translation.

<details>
<summary>V2.2 Major Updates</summary>

- Updated prompts to improve accuracy and fluency, optimizing instructions for incomplete sentences.
- Refactored API request construction to support both native Ollama and OpenAI-compatible APIs.

  - You can set `useOllamaNative = false` in the Ollama API class to use OpenAI-compatible APIs.

- For Ollama Cloud users, entering an API key in model configuration should allow usage of cloud models.

  - Not extensively tested; please open an issue if you encounter problems.

</details>

## TODO

- [ ] Optimize prompts (long-term task)

  - Improve translation quality

- [ ] Terminology glossary

  - A version was written and tested with several ~10–14B models, but the effect is similar for smaller models, so this feature is not included for now.

## About the Project

- If you have other requests or encounter issues, feel free to open an issue.

> This project was originally intended to focus on local Ollama usage. With the addition of custom API support, it has effectively become a general-purpose LLM-based translation plugin.

## Custom Configuration

### Model Selection

| Variable             | Description                                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `DEFAULT_MODEL_NAME` | Default model name (default: `"qwen3.5:27b"`). **This model is used if no model is configured in PotPlayer settings** |

### Model Configuration

| Variable        | Example Value | Description                                                                 |
| --------------- | ------------- | --------------------------------------------------------------------------- |
| `temperature`   | `0.1 - 0.3`   | Lower values produce more deterministic and less creative output.           |
| `topP`          | `0.8 - 0.95`  | Consider the smallest set of tokens whose cumulative probability ≥ topP.    |
| `topK`          | `20-40`       | Consider only the top K most likely tokens at each generation step.         |
| `minP`          | `0.01 - 0.1`  | Filter out tokens with probability below minP, even if in `topP` or `topK`. |
| `repeatPenalty` | `1.0 - 2.0`   | Penalize previously generated tokens to prevent repetition.                 |
| `maxTokens`     | `1024-2048`   | Maximum number of tokens that can be generated.                             |

> You may add other parameters as needed, but typically only temperature and topP need adjustment. Make sure to update the `GetActiveParams` method accordingly.

### Reasoning Configuration

| Variable         | Example Value                    | Description                                                                                                                                                                                                       |
| ---------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enableThinking` | `false`                          | Enables model reasoning. Strongly recommended to keep this **disabled**.                                                                                                                                          |
| `thinkStrength`  | `"low"` `"medium"` `"high"` `""` | Adjusts reasoning strength for gpt-oss models. Only applies to gpt-oss, and reasoning cannot be disabled for these models. If `enableThinking` is `false`, `"low"` is used automatically. Leave empty by default. |

### Context History

| Variable          | Example Value | Description                                              |
| ----------------- | ------------- | -------------------------------------------------------- |
| `contextEnabled`  | `true`        | Whether to use context history for translation           |
| `contextCount`    | `5`           | Number of recent sentences included in context           |
| `contextMaxSize`  | `10`          | Maximum number of history entries                       |
| `contextPrompt`    | See below     | Custom context prompt template (see `CONTEXT_PROMPT_BASE` below) |

> History entries contain source text, translation, and language metadata in the format: `[source language] source -> [target language] translation`
> Significantly increasing the number of entries may increase response time due to larger context size. Adjust token limits accordingly.
> Context is only injected into prompts when `contextEnabled` is true and `contextPrompt` is non-empty.

### Prompt Templates

You can apply the following variables in your prompt templates:

- `{{from}}` – source language
- `{{to}}` – target language
- `{{optional_reference_context}}` – optional reference history (only populated when context history is enabled and non-empty)
- `{{text_to_translate}}` – the text to be translated
- `{{context_prompt}}` – context prompt template (only populated when context history is enabled and `contextPrompt` is non-empty)

<details>
<summary>SYSTEM_PROMPT_BASE</summary>

```
const string SYSTEM_PROMPT_BASE =
"You are a professional simultaneous interpreter.\n"
"Translate from {{from}} into {{to}} with natural, fluent, native-sounding output.\n"
"Preserve meaning, tone, emotion, and speaker intent.\n"
"\n"
"Context & History:\n"
"- Reference context and prior turns are for tone, intent, and continuity only\n"
"- Never translate or quote context or history\n"
"- If context conflicts with the current text, translate the current text faithfully\n"
"- Assume the same speaker unless stated otherwise\n"
"\n"
"Rules:\n"
"- Output ONLY the translation in {{to}}\n"
"- Do NOT add explanations or commentary\n"
"- Keep names, numbers, symbols, tags, and formatting unchanged\n"
"- Smooth disfluencies only when it improves natural spoken flow\n"
"- Do not add, omit, or reinterpret meaning\n"
"- If input is fragmentary or incomplete, translate it naturally as-is\n"
"\n"
"Follow the rules strictly, output PLAIN TEXT ONLY.";
```

</details>

<details>
<summary>USER_PROMPT_BASE</summary>

```
const string USER_PROMPT_BASE =
"{{context_prompt}}"
"\n"
"Translate ONLY the text inside <Text> into {{to}}.\n"
"The context is for tone and continuity only and must NOT be translated.\n"
"\n"
"<Text>\n"
"{{text_to_translate}}\n"
"</Text>";
```

</details>
<details>
<summary>CONTEXT_PROMPT_BASE</summary>

```
const string CONTEXT_PROMPT_BASE =
"The context below provides reference material from prior turns.\n"
"Use it for tone, intent, and continuity only.\n"
"Do NOT translate or quote the context.\n"
"\n"
"<Context>\n"
"{{optional_reference_context}}\n"
"</Context>";
```

</details>
<details>
<summary>SYSTEM_PROMPT_LONG</summary>

```
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

```

</details>
<details>
<summary>Deprecated System Prompts (for reference)</summary>

- SYSTEM_PROMPT_OLD

```
You are a professional subtitle translator. Your task is to fluently translate text into the target language. Strictly follow these rules:

1. Output only the translated content, without explanations or additional content.
2. Use provided context if provided to aid understanding, but DO NOT include it in your output.
3. Maintain the original tone, style, and narrative of the subtitles.
```

- SYSTEM_PROMPT_BASIC

```
Act as a professional, authentic translation engine dedicated to providing accurate and fluent translations of subtitles.
ONLY provide the translated subtitle text without any additional information.
```

- SYSTEM_PROMPT_BASIC_OLD_TWO_STEP

```
You are a professional subtitle translator skilled in accurate and culturally appropriate translations. I may provide additional context to help clarify the meaning. Use this context to understand the subtitle's meaning and provide an accurate translation. Follow these rules:

1. First, perform a direct translation based on the original text without adding any information.
2. Then, reinterpret the translation to make it sound more natural and understandable in the target language, while preserving the original meaning.
3. Use the provided context and cultural cues to ensure the translation aligns with local language norms and nuances.
4. Your output must only include the translated text—do not include any explanations, context, or commentary.
```

</details>

## Performance

### Ollama

**Supported Models:**

- All models officially supported by Ollama
- All HuggingFace models supported by the Ollama community
- Custom models configured through Ollama

> In other words, if your model can run in the Ollama app or Ollama CLI, it is supported by this plugin.

Please test your tokens/sec. Models with slow response times may cause translation delays or failures. Configure according to your hardware and requirements to ensure optimal performance.

### Cloud API

**Tested Platforms:**

- Ollama Cloud
- OpenRouter
- Google Gemini
- Z.Ai
- DeepSeek
- Minimax

> Only tested a few models, but since Potplayer's translation calls are made sentence by sentence, please be aware of concurrency and rate limits, as well as **costs**

## References

- Inspired by and further developed from [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1.
- Written using [AngelScript](https://www.angelcode.com/angelscript/).
- Uses [Ollama](https://ollama.com/) for LLM and API support.
- Uses [OpenAI](https://platform.openai.com/docs/api-reference) for API format.

## License

MIT License
