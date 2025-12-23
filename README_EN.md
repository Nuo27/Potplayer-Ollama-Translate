# Potplayer Live Translate Plugin via Ollama

This is a plugin for Potplayer that allows real-time subtitle translation using Ollama.

- Native Ollama API support, with added support for GPT-OSS thinking strength
- Added support for ollama cloud models (experimental)
- [Features](#features)
- Tested up to Ollama version 0.13.0

<div align="center">
  <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/README.md">简体中文</a> | <strong>English</strong>
</div>

## Table of Contents

- [Potplayer Live Translate Plugin via Ollama](#potplayer-live-translate-plugin-via-ollama)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Usage](#usage)
  - [Notes](#notes)
  - [Updates](#updates)
    - [V2.2 Major Updates](#v22-major-updates)
    - [TODO](#todo)
  - [Custom Configuration](#custom-configuration)
  - [Performance](#performance)
  - [References](#references)
  - [License](#license)

## Features

- Native Ollama API support, with added support for GPT-OSS thinking strength
- Added support for Ollama Cloud models (experimental)
- Supports reasoning/thinking capabilities of inference models, including qwen3, deepseek-r1, gpt-oss, etc.
- Configurable context history
- Customizable model parameter configuration
- Brand-new translation prompts and translation strategy

## Usage

1. Download the `.7z` or `.zip` compressed archive from the [release](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases) page, extract the `.as` and `.ico` files, and put them to your Potplayer's installation directory under `...\DAUM\PotPlayer\Extension\Subtitle\Translate` folder.
2. Open the `.as` file and modify `DEFAULT_MODEL_NAME` to your target model name. Or you can leave it and set it up in the extension settings later.
3. Feel free to twerk around with the **prompts**, **model configuration** and context history size if you want to.
4. Make sure to set up reasoning model configuration if you are using a reasoning model. `Reasoning is highly recommended to be turned off.`
5. Run PotPlayer, right click and open up settings / f5. Then go to `Subtitles -> Subtitle Translation -> Online Subtitle Translation Settings`, select and enable the plugin.
6. In the extension settings, set up your model name if you want to use a different one than the default. You wont need the API key since its for ollama
7. All done. Enjoy live translation!

## Notes

- **Make sure your model and Ollama are updated to version >= 0.9.0**
- The plugin provides several **prompt templates**; please adjust them according to translation quality.
- Ensure you are using a model that **supports multilingual tasks**.
- In general, reasoning/thinking **should be turned off**, as it significantly impacts translation speed, and simple translation tasks rarely require reasoning.
- Highly recommended to use **Instruct** models, such as `qwen3:30b-a3b-instruct-2507-q4_K_M`. Tested models can be found in the [Performance](#performance) section.

## Updates

### V2.2 Major Updates

- Updated prompts to improve accuracy and fluency, and optimized instructions for incomplete sentences
- Refactored API request construction to support both native Ollama and OpenAI-compatible API requests

  - You can set `useOllamaNative = false` in the Ollama API class to use the OpenAI-compatible API

- For Ollama Cloud users, filling in the API key in the model configuration should allow you to use cloud models

  - Not extensively tested; please open an issue if you encounter problems

### TODO

- The current state is likely final; translation quality ultimately depends on model capability and prompt quality
- Tested a Terms glossary approach by directly replacing terms and injecting them into prompts; results were similar tbh, so no plan to add it yet
- If you have other requirements, feel free to open an issue

## Custom Configuration

**Model Selection**
| Variable | Description |
| -------- | ----------- |
| `DEFAULT_MODEL_NAME` | Default model name (default: `"qwen3-vl:30b-a3b-instruct-q4_K_M"`). **Used when no model is configured in Potplayer.** |

**Model Configuration**  
| Variable | Example Value | Description |
| -------- | ------------- | ----------- |
| `temperature` | `0.1 - 0.3` | Lower values give more deterministic results. Slightly increase for paraphrased translation. |
| `topP` | `0.8 - 0.95` | Considers only token sets whose cumulative probability ≥ topP. |
| `topK` | `20-40` | Considers the top K most probable tokens at each step. |
| `minP` | `0.01 - 0.1` | Filters tokens below this probability, even if included in topP/topK. |
| `repeatPenalty` | `1.0 - 2.0` | Penalizes repeated tokens to reduce duplication. |
| `maxTokens` | `1024-2048` | Max number of tokens generated. |

> You can add other parameters if needed, but generally you only need to adjust temperature and topP. Make sure to update the `GetActiveParams` method accordingly.

**Reasoning/Thinking Configuration**  
| Variable | Example Value | Description |
| -------- | ------------- | ----------- |
| `enableThinking` | `false` | Enables reasoning mode. Strongly recommended to keep this off. |
| `thinkStrength` | `"low"` `"medium"` `"high"` `""` | Thinking strength for gpt-oss. Only applies to gpt-oss. If `enableThinking` = false, `low` is applied automatically. |

**Context History**  
| Variable | Recommended Value | Description |
|--------|-------------|-------------|
| `enabled` | `true` | Whether to use context history for translation |
| `contextCount` | `10` | Number of recent sentences to include in the context
| `maxSize` | `50` | Maximum number of history entries |

> If you significantly increase the number of entries, response time may increase noticeably due to larger context size. You may also need to adjust the token limit accordingly.

**Prompts**  
The plugin provides several prompt templates that can be freely customized.
| Prompt | Description |
|--------|-------------|
| `SYSTEM_PROMPT_BASE` | Base system prompt, combined with context prefix to form final system prompt. |
| `SYSTEM_PROMPT_END` | Appended to end of system prompt to specify user task. |
| `USER_PROMPT_BASE` | Base user prompt. |
| `CONTEXT_PROMPT` | Context prefix specifying history. |
| `SYSTEM_PROMPT_OLD` | Prompt used in previous version. |
| `SYSTEM_PROMPT_BASIC` | Simplified system prompt for weaker models or low context tolerance. |
| `SYSTEM_PROMPT_BASIC_OLD_TWO_STEP` | Two-step translation strategy from previous version. |

| Variable          | Default              | Description                              |
| ----------------- | -------------------- | ---------------------------------------- |
| `userPrompt`      | `USER_PROMPT_BASE`   | Uses USER_PROMPT_BASE as user prompt     |
| `systemPrompt`    | `SYSTEM_PROMPT_BASE` | Uses SYSTEM_PROMPT_BASE as system prompt |
| `systemPromptEnd` | `SYSTEM_PROMPT_END`  | Appended at end of system prompt         |

> **Note:** Make sure your model can properly handle these prompts, otherwise translation results may be inaccurate or the plugin may not work correctly.

## Performance

**Supported Models:**

- Newly added support for GPT-OSS
- all official Ollama supported models, including huggingface models, and custom models that is configured in Ollama

> In other words, if your model can run in the Ollama app or Ollama CLI, it is supported by the plugin.

**Recommended Models**

- qwen3-vl:30b-a3b-instruct-q4_K_M
- qwen3:30b-a3b-instruct-2507-q4_K_M
- gpt-oss:20b
- **qwen3-vl:8b-instruct**
- ministral-3:14b-instruct-2512-q4_K_M
- gemma3:12b / gemma3n:e4b
- For lower-end systems, consider qwen3:4b-instruct or qwen3-vl:4b-instruct

> Please test your tokens-per-second (token/s). Models with slow response times may cause translation delays or failures. Configure according to your hardware and needs to ensure optimal performance.

## References

- Inspired by [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1 and further developed based on it
- Written using [AngelScript](https://www.angelcode.com/angelscript/)
- Uses [Ollama](https://ollama.com/) to provide LLM and API support

## License

MIT License
