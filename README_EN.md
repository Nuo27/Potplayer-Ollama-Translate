# Potplayer Ollama Real-Time Subtitle Translation Plugin

This is a plugin developed for PotPlayer that enables real-time subtitle translation using Ollama or other custom APIs.

<div align="center">
  <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/README.md">简体中文</a> | <strong>English</strong>
</div>
<div align="right">
Ollama test version: 0.32.1
</div>

## Features

- Real-time translation of PotPlayer subtitles.
- Supports multiple API protocols: Ollama native, LM Studio REST, OpenAI-compatible, Anthropic-compatible. See [Advanced configuration and Debug](#advanced-configuration-and-debug).
- Supports Ollama Cloud, OpenAI / Anthropic cloud-compatible APIs.
- Customizable system prompt, user prompt, and context prompt, with a [prompt collection](prompts_EN.md).
- Adjustable model parameters (`temperature`, `topP`, `contextLength`, `maxTokens`), see [Model configuration](#model-configuration).
- Supports context history (last N subtitles) for more natural translations, see [Context history](#context-history).
- Translation cache (memory + optional disk) avoids duplicate requests for repeated subtitles.
- Toggleable thinking mode for reasoning models such as qwen3, deepseek-r1, and gpt-oss, see [Reasoning configuration](#reasoning-configuration).
- Automatic retry on transient network errors, with diagnostic error logs.

## Table of Contents

- [Potplayer Ollama Real-Time Subtitle Translation Plugin](#potplayer-ollama-real-time-subtitle-translation-plugin)
  - [Features](#features)
  - [Table of Contents](#table-of-contents)
  - [Installation](#installation)
  - [Notes](#notes)
  - [Updates](#updates)
    - [V3.0 main updates](#v30-main-updates)
  - [About](#about)
  - [Custom configuration](#custom-configuration)
    - [Model selection](#model-selection)
    - [Model configuration](#model-configuration)
    - [Reasoning configuration](#reasoning-configuration)
    - [Context history](#context-history)
    - [Prompt templates](#prompt-templates)
  - [Advanced configuration and Debug](#advanced-configuration-and-debug)
    - [Select API type](#select-api-type)
    - [Ollama Cloud](#ollama-cloud)
    - [LM Studio REST](#lm-studio-rest)
    - [OpenAI compatible API](#openai-compatible-api)
    - [Anthropic compatible API](#anthropic-compatible-api)
    - [Custom endpoint](#custom-endpoint)
    - [Debug](#debug)
  - [Performance](#performance)
    - [Ollama](#ollama)
    - [Other local services](#other-local-services)
    - [Cloud APIs](#cloud-apis)
  - [References](#references)
  - [License](#license)

## Installation

1. Go to the [Release page](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases), download the `.7z` or `.zip` archive, and extract the `.as` and `.ico` files.
2. Copy them into the PotPlayer installation folder:

   ```text
   ...\DAUM\PotPlayer\Extension\Subtitle\Translate\
   ```

3. Open the `.as` file with a text editor or IDE. If you use a service other than Ollama, change `apiFormat` and `customEndpoint` in the `Config` class, see [Advanced configuration and Debug](#advanced-configuration-and-debug).
4. Launch PotPlayer, right-click on the video window, go to `Subtitles → Real-time subtitle translation`, and choose **Ollama Translate**. Then open **Real-time subtitle translation settings**.
   You can also open the settings panel from `Options → Extensions → Real-time subtitle translation`.
5. In the real-time subtitle translation settings, set the translation engine to **Ollama Translate**. Source language is usually `auto`; pick the target language as needed.
6. In the account settings, set **Model Name** to the model you use.
   - For **Ollama Cloud** models, fill in the corresponding **API Key**.
   - For local Ollama, leave it empty.
     After confirming, the status should read **"可正常处理"**.
7. You're ready to use it. Click the **Test** button to send a translation request and verify the result.

> PotPlayer caches translation results, so the **Test** button may return cached output. After changing the configuration, edit the test text slightly and test again to see the new result.

## Notes

- **Ollama local users**: make sure both Ollama and the model are **>= 0.9.0**.
- Use a model that **supports multilingual tasks**.
- Tune the prompt yourself when translation quality is not ideal.
- Reasoning / thinking should be **disabled by default**; it dramatically slows down translation and rarely helps for simple subtitle translation.
- **Instruct** models are strongly recommended, e.g. `qwen3.5:27b`. See [Performance](#performance) for tested platforms.

## Updates

### V3.0 main updates

- Full refactor of the plugin, removed unnecessary model config.
- Reworked API call and error handling flow, with automatic retry on network failures.
- Added four API types: `ollama`, `rest`, `openai`, `anthropic`.
- Added context memory and translation cache.

<details>
<summary>V2.4 main updates</summary>

- Updated prompts for better accuracy and fluency; instructions for incomplete sentences were tuned.
- Refactored API request construction, supporting both Ollama-native and OpenAI-compatible requests.
  - You can set `useOllamaNative = false` in the Ollama API class to use OpenAI-compatible requests.
- For Ollama Cloud users, filling in an API key in the model config should let you use cloud models.
  - Not deeply tested; please open an issue if you find any problems.

</details>

## About

- Open an issue for requests or bugs.

> This project started as an Ollama-only plugin. With the addition of custom APIs, it has effectively become a generic LLM subtitle translation plugin.

## Custom configuration

### Model selection

| Field            | Description                                                                              |
| ---------------- | ---------------------------------------------------------------------------------------- |
| `modelName`      | Model name. Usually filled in the PotPlayer login dialog, e.g. `qwen3:9b`.               |
| `apiKey`         | API key. Usually managed by the PotPlayer login dialog; local Ollama can leave it empty. |
| `apiFormat`      | API type: `ollama`, `rest`, `openai`, `anthropic`. Requires editing the `.as` file.      |
| `customEndpoint` | Custom service address. Leave empty to use the default endpoint.                         |

### Model configuration

| Field             | Example      | Description                                                                   |
| ----------------- | ------------ | ----------------------------------------------------------------------------- |
| `temperature`     | `0.1 - 0.3`  | Lower values make translation more stable; `0.3` recommended.                 |
| `topP`            | `0.8 - 0.95` | Controls token selection range; usually no need to change.                    |
| `contextLength`   | `4096`       | Context window size. Larger uses more VRAM; keep `4096` for normal subtitles. |
| `maxTokens`       | `512`        | Output length cap per request; keep `512` for normal subtitles.               |
| `cacheMaxEntries` | `500`        | Maximum in-memory cached translation entries.                                 |

> These fields live in the `Config` class of the `.as` file. You usually only need to adjust `temperature` and `contextEnabled`. Do not invent fields that do not exist.

### Reasoning configuration

| Field            | Example                          | Description                                                              |
| ---------------- | -------------------------------- | ------------------------------------------------------------------------ |
| `enableThinking` | `false`                          | Enable the model's reasoning feature. Strongly recommend leaving it off. |
| `thinkStrength`  | `"low"` `"medium"` `"high"` `""` | Adjust the model's reasoning strength. Leave empty by default.           |

### Context history

| Field            | Example                        | Description                                              |
| ---------------- | ------------------------------ | -------------------------------------------------------- |
| `contextEnabled` | `true`                         | Whether to use previous subtitle history in translation. |
| `contextCount`   | `7`                            | Number of recent subtitle lines used as context.         |
| `contextPrompt`  | [prompts_EN.md](prompts_EN.md) | Custom context prompt template.                          |

> Each history entry stores source, translation, and language metadata in the form `[source] source -> [target] translation`.
> If you increase the number of entries significantly, response time may grow due to a larger context. Adjust token counts accordingly.
> Context is injected into prompts only when `contextEnabled` is true and `contextPrompt` is non-empty.

### Prompt templates

The full prompt collection has been moved to [prompts_EN.md](prompts_EN.md) for reference.

It contains:

- Default system, user, and context prompts.
- Natural spoken subtitles.
- Formal and accurate translation.
- Video game terminology.
- Preserving tone, slang, and profanity.
- Custom terminology glossaries.

Supported template variables:

- `{{from}}` — source language.
- `{{to}}` — target language.
- `{{optional_reference_context}}` — optional reference history.
- `{{text_to_translate}}` — current subtitle text. Must be kept in `userPrompt`.
- `{{context_prompt}}` — context prompt template.

> When you edit prompts, ask the model to output only the translation. Otherwise explanations may leak into subtitles.

## Advanced configuration and Debug

The plugin supports four API protocols. Switch them via the `Config` class in the `.as` file:

```javascript
class Config {
    string apiFormat = "ollama";   // ollama | rest | openai | anthropic
    string customEndpoint = "";
}
```

`apiFormat` and `customEndpoint` are **not** exposed in PotPlayer's login UI. You must edit the `.as` file directly. Restart PotPlayer after changing them.

### Select API type

| `apiFormat` | Backend              | Default endpoint                            |
| ----------- | -------------------- | ------------------------------------------- |
| `ollama`    | Ollama               | `http://127.0.0.1:11434`                    |
| `rest`      | LM Studio REST       | `http://127.0.0.1:1234/api/v1/chat`         |
| `openai`    | OpenAI compatible    | `http://127.0.0.1:1234/v1/chat/completions` |
| `anthropic` | Anthropic compatible | `http://127.0.0.1:1234/v1/messages`         |

### Ollama Cloud

- Fill in your API key in the account settings.
- Keep `apiFormat = "ollama"`.
- Leave `customEndpoint` empty.
- The plugin automatically uses the cloud API.

### LM Studio REST

- Set `apiFormat = "rest"`.
- Default endpoint: `http://127.0.0.1:1234/api/v1/chat`.
- Enable the local server in LM Studio and load the target model.

### OpenAI compatible API

- Set `apiFormat = "openai"`.
- Fill `customEndpoint` with a service address, for example:
  - `http://localhost:1234` - LM Studio
  - `https://openrouter.ai/api/v1` - OpenRouter
  - `https://api.z.ai/api/paas/v4` - Z.AI GLM

### Anthropic compatible API

- Set `apiFormat = "anthropic"`.
- Fill in the API key in the account settings.
- Fill `customEndpoint` with the service address.

### Custom endpoint

- `customEndpoint` may be either a host or a full URL.
- The plugin appends the correct suffix based on `apiFormat`.
- For example, `http://localhost:1234` becomes `/api/chat` or `/v1/chat/completions` automatically.

### Debug

- Uncomment `HostOpenConsole` in `OnInitialize` to open the console at runtime.
- Use `HostPrintUTF8` for diagnostic output.
- Use `HostMessageBox` to pop a dialog.

> Advanced settings target users familiar with models and APIs. Most users only need the default Ollama setup.

## Performance

### Ollama

**Supported models:** any model that runs in the Ollama app or via the Ollama CLI is supported.

> Test your tokens/sec. Slow models may cause translation delays or failures. Tune hardware and parameters for the best results.

### Other local services

Tested platforms:

- LM Studio
- vLLM
- llama.cpp

> In theory any locally-served model is supported, but you have to wire it up yourself.
> Pre-load the model to avoid translation lag from model loading.

### Cloud APIs

Tested platforms:

- Ollama Cloud
- OpenRouter
- Google Gemini
- Z.Ai
- DeepSeek
- MiniMax

> Only a subset of models was tested. PotPlayer sends one translation request per subtitle line, so mind parallelism, rate limits, and **costs**.

## References

- Inspired by and built upon [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1.
- Written in [Angel Script](https://www.angelcode.com/angelscript/).
- Uses [Ollama](https://ollama.com/) for LLM and API support.
- Uses the [OpenAI](https://platform.openai.com/docs/api-reference) API format.

## License

MIT License
