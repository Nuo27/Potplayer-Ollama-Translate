# Potplayer Live Translate Plugin via Ollama

This is a plugin for Potplayer that allows real-time subtitle translation using Ollama.

- Support Qwen3 & Deepseek-R1 reasoning models
- Allow some custom settings
- Better context handling, and customizable

<div align="center">
  <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/master/README_zh.md">简体中文</a> | <strong>English</strong>
</div>

## Table of Contents

- [Potplayer Live Translate Plugin via Ollama](#potplayer-live-translate-plugin-via-ollama)
  - [Table of Contents](#table-of-contents)
  - [Features](#features)
  - [Usage](#usage)
  - [NOTES](#notes)
  - [Customization](#customization)
  - [Performance](#performance)
  - [References](#references)
  - [License](#license)

## Features

- Add supports for reasoning models
- Improve context history handler
- Prompts of paraphrase and two-steps translation strategy
- custom model configuration (temperature, top_p, etc.)

## Usage

1. Download the `.as` and `.ico` files put them to your Potplayer's installation directory under `...\DAUM\PotPlayer\Extension\Subtitle\Translate` folder.
2. Open the `.as` file and modify `DEFAULT_MODEL_NAME` to your target model name. Or you can leave it and set it up in the extension settings later.
3. Feel free to twerk around with the **prompts**, **model configuration** and context history size if you want to.
4. Make sure to set up reasoning model configuration if you are using a reasoning model. `Reasoning is highly recommended to be turned off.`
5. Run PotPlayer, right click and open up settings / f5. Then go to `Subtitles -> Subtitle Translation -> Online Subtitle Translation Settings`, select and enable the plugin.
6. In the extension settings, set up your model name if you want to use a different one than the default. You wont need the API key since its for ollama
7. All done. Enjoy live translation!

## NOTES

- **Make sure to update the model and ollama to >= 0.9.0** for ollama's native thinking support. qwen3's think prompt is not yet removed since it wasnt really working under my testing.
- Qwen3, Deepseek-r1 with old template & capabilities and ollama <0.9.0 are **compatible** but other models might not compatible and you can manually add their think tags and `bool` value under `ModelConfig` to add a item in `options` field.
- Remember to adjust the **prompts** according to your needs, as they can significantly affect the quality of the output.
- Please ensure that your model **supports multilingual tasks** otherwise the quality of the translation might be affected.
- Reasoning should be **turned off** if not needed as it can significantly affect the speed of translation.

## Customization

**Model Selection**
| Variable | Description |
|--------|-------------|
| `DEFAULT_MODEL_NAME` | Default model name (default: `"qwen3:14b"`). **This will enable if you didnt setup model in Potplayer's Settings** |

**Model Configuration**  
| Variable | Recommended Value | Description |
|--------|-------------|-------------|
| `temperature` | `0.1 - 0.3` | Lower values make the output more deterministic and less creative. **If you want paraphrased translation, you may want to increase this a bit**|
| `topP` | `0.8 - 0.95` | Only the smallest set of top tokens whose cumulative probability ≥ topP are considered.|
|`topK`| `20-40` | Only considers the top K most likely tokens at each generation step.|
| `minP` | `0.01 - 0.1` | Filters out tokens with probability lower than minP, even if they are in `topP` or `topK`|
|`repeatPenalty` | `1.0 - 2.0` | Penalizes tokens that have already been generated, discouraging repetition|
|`maxTokens` | `1024-2048` | Maximum number of tokens that can be generated in`However you dont need to tweak this since ollama wont ban you.`|

> Additional parameters can be added as needed. Make sure to update the `GetActiveParams` method accordingly

**Reasoning Configuration**  
| Variable | Recommended Value | Description |
|--------|-------------|-------------|
| `isReasoningModel` | `false` | Only check this if you are using a model that supports reasoning. |
| `activateReasoning` | `false` | Activates reasoning in the model. Highly recommended to turn if `off`|

**Context History**  
| Variable | Recommended Value | Description |
|--------|-------------|-------------|
| `enabled` | `true` | Whether to use context history for translation |
| `contextCount` | `10` | Number of recent sentences to include in the context
| `maxSize` | `50` | Maximum number of history entries |

> if you increase the entries significantly, the response time might also increase significantly due to the larger context size. and you got to adjust tokens as well.

**Prompts**  
| Prompt | Description |
|--------|-------------|
| `SYSTEM_PROMPT` | This prompt and context history will be combined to form the final System prompt for the model. |
| `USER_PROMPT_BASE` | User prompt that require model to paraphrase the output by default. |
| `backup_system_prompt` | Backup System prompt.|
| `two_step_process_prompt` | User prompt that require model to follow a two-step process by default |

## Performance

**Tested models:**

- qwen3:14b
- gemma3:12b
- deepseek-r1:14b-qwen-distill-q4_K_M
- aya-expanse:8b
- granite3.3:8b
- phi4:14b
- llama3.1:8b

**Recommendations**

- qwen3:14b (thinking not enabled) is the best model with this prompt tested so far.
- gemma3:12b works well with simple prompt.
- and others are just fine, but not as good as qwen3.

> Adjust prompt makes big impact on models' performance and these reckons are just FYI.

## References

- Inspired by [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) and further built upon.
- Written in [Angel Script](https://www.angelcode.com/angelscript/).
- [Ollama](https://ollama.com/) for LLMs and API usage.

## License

MIT License
