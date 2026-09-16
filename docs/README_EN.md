# Potplayer Ollama Real-Time Subtitle Translation Plugin

This is a plugin developed for PotPlayer that enables real-time subtitle translation using Ollama or other custom APIs.

<div align="center">
  <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/README.md">简体中文</a> | <strong>English</strong>
</div>
<div align="right">
Tested with Ollama 0.32.15
</div>

## Features

- Real-time translation of PotPlayer subtitles.
- Multiple API protocols: Ollama, OpenAI, Anthropic, with arbitrary request parameters via JSON config, see [Custom configuration](#custom-configuration).
- Customizable system and user prompts, with a [prompt collection](prompts_EN.md).
- Context history (last N subtitles) for more natural translations, see [Context history](#context-history).
- In-memory LRU translation cache avoids duplicate requests for repeated subtitles.

## Table of Contents

- [Potplayer Ollama Real-Time Subtitle Translation Plugin](#potplayer-ollama-real-time-subtitle-translation-plugin)
  - [Features](#features)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [Notes](#notes)
  - [Custom configuration](#custom-configuration)
    - [Model selection](#model-selection)
    - [Model configuration](#model-configuration)
    - [General configuration](#general-configuration)
    - [Context history](#context-history)
  - [Prompts](#prompts)
  - [Performance](#performance)
  - [References](#references)
  - [License](#license)

## Installation

1. Go to the [Release page](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases), download the `.7z` or `.zip` archive, and extract the `.as` and `.ico` files.
2. Copy them into the PotPlayer installation folder:

   ```text
   ...\DAUM\PotPlayer\Extension\Subtitle\Translate\
   ```

3. Open the `.as` file with a text editor or IDE. If you use a service other than Ollama, change `apiFormat` and `customEndpoint` in the `Config` class, see [Custom configuration](#custom-configuration).
4. Launch PotPlayer, right-click on the video window, go to `Subtitles → Real-time subtitle translation`, and choose **Ollama Translate**. Then open **Real-time subtitle translation settings**.
   You can also open the settings panel from `Options → Extensions → Real-time subtitle translation`.
5. In the real-time subtitle translation settings, set the translation engine to **Ollama Translate**. Source language is usually `auto`; pick the target language as needed.
6. In the account settings, set **Model Name** to the model you use.
   - **Ollama Cloud** models: fill in the corresponding **API Key**.
   - Local Ollama models: leave it empty.

   After confirming, the status should read **"可正常处理"** ("ready to process" in the Chinese UI).

7. Click the **Test** button to send a translation request and verify the result.

> PotPlayer caches translation results, so the **Test** button may return cached output. After changing the configuration, edit the test text slightly and test again to see the new result.

## Notes

- Use a model that **supports multilingual tasks**.
- Tune the prompt yourself when translation quality is not ideal.
- Reasoning / thinking should be **disabled by default**; it dramatically slows down translation and rarely helps for simple subtitle translation. To enable it, set it in the matching JSON config.
- Failed requests are retried automatically (count and interval in [General configuration](#general-configuration); `retryCount = -1` retries until success). Subtitles that fail translation keep showing the original text and are retried on their next display.
- **Instruct** models are strongly recommended, e.g. `qwen3.5:27b`. See [Performance](#performance) for tested platforms.
- **Ollama local users**: make sure both Ollama and the model are **>= 0.9.0** (the default preset's `think` parameter requires 0.9.0+).

## Custom configuration

### Model selection

| Field            | Description                                                                                |
| ---------------- | ------------------------------------------------------------------------------------------ |
| `modelName`      | Model name. Usually filled in the PotPlayer login dialog, e.g. `qwen3.5:27b`.              |
| `apiKey`         | API key. Usually managed by the PotPlayer login dialog; local services can leave it empty. |
| `apiFormat`      | API type: `ollama`, `openai`, `anthropic`. Requires editing the `.as` file.                |
| `customEndpoint` | Custom service address. Leave empty to use the default endpoint.                           |

Model name and API key resolution order: **login dialog input > code-side default (the `Config` values in the `.as` file) > last saved value**.

> Wrong dialog input falls back to the code-side default; empty input keeps the last saved value; the validated value is persisted so the next login works with empty fields. At login the model name is validated against the server's model list (`/api/tags` for Ollama, `/v1/models` for OpenAI-compatible); input not in the list falls back to the code-side default.

**Default endpoints**

Without an API key, all three formats fall back to the matching **local Ollama compatibility endpoint**; filling in an API key switches to the official cloud.

| `apiFormat` | No API key (local Ollama)               | With API key (cloud)                             |
| ----------- | --------------------------------------- | ------------------------------------------------ |
| `ollama`    | `http://127.0.0.1:11434`                | `https://ollama.com`                             |
| `openai`    | `http://127.0.0.1:11434/v1/chat/completions` | `https://api.openai.com/v1/chat/completions` |
| `anthropic` | `http://127.0.0.1:11434/v1/messages`    | `https://api.anthropic.com/v1/messages`          |

> The `anthropic` local fallback requires Ollama's Anthropic compatibility layer (built into recent Ollama versions; `/v1/messages` verified working).

Leave `customEndpoint` empty for the default above; you may also set it to a host (the plugin appends `/api/chat` / `/v1/chat/completions` / `/v1/messages` based on `apiFormat`) or a full URL. Common cases:

- Ollama Cloud: `apiFormat = "ollama"`, fill the API key in account settings, leave `customEndpoint` empty.
- Official OpenAI: `apiFormat = "openai"`, fill the API key, leave `customEndpoint` empty; if your model rejects the `reasoning_effort` parameter (e.g. gpt-4o), remove that field from `openaiConfigs`.
- Other OpenAI-compatible services: `apiFormat = "openai"`, `customEndpoint = "http://localhost:1234"` (LM Studio), `"https://openrouter.ai/api/v1"`, or `"https://api.z.ai/api/paas/v4/chat/completions"`.
- Official Anthropic: `apiFormat = "anthropic"`, fill the API key, leave `customEndpoint` empty; to use local Ollama models, leave the key empty and the local fallback applies. The Anthropic format has no portable list-models endpoint; at login the plugin sends one minimal test request to validate the model and key.

### Model configuration

All three formats follow the same skeleton + JSON config pattern: the body only fixes `model` and `messages` (plus format-required fields); every other parameter lives in the format's JSON field and is spliced into the request verbatim. Set it to `""` for the bare skeleton (ollama re-injects stream:false). Content that is not a valid JSON object is ignored with a logged warning.

**Ollama `ollamaConfigs`**

```javascript
string ollamaConfigs = ""
    + "{"
    + "\"stream\": false, "
    + "\"options\": {\"num_ctx\": 4096, \"num_predict\": 256, \"temperature\": 0.3, \"top_p\": 0.9}, "
    + "\"think\": false, "
    + "\"keep_alive\": \"30m\""
    + "}";
```

`options` accepts any sampling parameter ollama supports (`top_k`, `seed`, `num_gpu`, `repeat_penalty`, ...); Ollama Cloud users can drop the `keep_alive` line; thinking is controlled by the top-level `think` field.

**OpenAI `openaiConfigs`**

```javascript
string openaiConfigs = ""
    + "{"
    + "\"temperature\": 0.3, "
    // + "\"reasoning_effort\": \"none\", "
    + "\"chat_template_kwargs\": { \"enable_thinking\": false }"
    + "}";
```

Any parameter the server supports (`max_tokens`, `top_p`, `reasoning_effort`, ...) can go here.

**Anthropic `anthropicConfigs`**

```javascript
string anthropicConfigs = ""
    + "{"
    + "\"temperature\": 0.3, "
    + "\"max_tokens\": 512"
    + "}";
```

The body always keeps `model` + `system` + `messages` + `max_tokens` (required; defaults to `256` when the JSON omits it). Spec constraints: `thinking` `budget_tokens` must be >= 1024 and below `max_tokens`, and thinking requires `temperature` exactly 1.

> These fields live in the `Config` class of the `.as` file. Parameters are validated by the server; check your service's API documentation when filling them in.

### General configuration

| Field             | Example | Description                                                                                              |
| ----------------- | ------- | -------------------------------------------------------------------------------------------------------- |
| `cacheMaxEntries` | `500`   | Maximum in-memory cached translation entries.                                                            |
| `retryCount`      | `-1`    | Retries after a failed translation: `0` off, `-1` retry until success, `N` extra attempts.               |
| `retryDelayMs`    | `500`   | Wait in ms before each retry; `0` retries immediately. Only applies to retries, never the first request. |

### Context history

| Field            | Example | Description                                              |
| ---------------- | ------- | -------------------------------------------------------- |
| `contextEnabled` | `true`  | Whether to use previous subtitle history in translation. |
| `contextCount`   | `7`     | Number of recent subtitle lines used as context.         |

> Each history entry has the form `source ⇒ translation` (no language metadata).
> If you increase the number of entries significantly, response time may grow due to a larger context. Adjust token counts accordingly.
> Context is injected via the `{{context_raw}}` template variable; the value is an empty string when there is no context.

## Prompts

The full prompt collection has been moved to [docs/prompts_EN.md](prompts_EN.md) for reference.

Supported template variables:

- `{{from}}` — source language.
- `{{to}}` — target language.
- `{{text_to_translate}}` — current subtitle text. Must be kept in `userPrompt`.
- `{{context_raw}}` — raw context history (previous subtitles in `source ⇒ translation` form). Empty string when context is disabled. No surrounding wrapper — wrap it in your own tags if you need one.

> When you edit prompts, ask the model to output only the translation. Otherwise explanations may leak into subtitles.

## Performance

**Ollama:** any model that runs in the Ollama app or via the Ollama CLI is supported.

> Test your tokens/sec. Slow models may cause translation delays or failures. Tune hardware and parameters for the best results.

Tested platforms:

| Platform      | Type  | Notes                                   |
| ------------- | ----- | --------------------------------------- |
| LM Studio     | Local | OpenAI / Anthropic compatible endpoints |
| vLLM          | Local | OpenAI-compatible endpoint              |
| llama.cpp     | Local | OpenAI-compatible endpoint              |
| Ollama Cloud  | Cloud | Fill in the API key in account settings |
| OpenRouter    | Cloud |                                         |
| Google Gemini | Cloud |                                         |
| Z.Ai          | Cloud |                                         |
| DeepSeek      | Cloud |                                         |
| MiniMax       | Cloud |                                         |

> In theory any service exposing the API formats above works, but you have to wire it up yourself. Only a subset of models was tested. PotPlayer sends one translation request per subtitle line, so mind parallelism, rate limits, and **costs**.

**Note**: PotPlayer has a built-in function timeout that aborts the request connection. If model loading, server response, or inference is too slow, translation fails repeatedly. When using larger models or thinking mode, pre-load the model and keep thinking intensity low.

## References

- Inspired by and built upon [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1.
- PotPlayer API docs are located in the Extension directory of the PotPlayer installation.
- Changelog: see the [Releases](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases) page.

## License

MIT License
