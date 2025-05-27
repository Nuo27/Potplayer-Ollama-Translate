# Potplayer Live Translate Plugin via Ollama

This is a plugin for Potplayer that allows real-time subtitle translation using Ollama.

<div align="center">
  <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/master/README_zh.md">简体中文</a> | <strong>English</strong>
</div>

## Usage

1. Download the `.as` and `.ico` files put them to your Potplayer's installation directory under `...\DAUM\PotPlayer\Extension\Subtitle\Translate` folder.
2. Open the `.as` file and modify `DEFAULT_MODEL_NAME` to your target model name. Or you can leave it and set it up in the extension settings later.
3. Run PotPlayer, right click and `Subtitles -> Subtitle Translation -> Online Subtitle Translation Settings`, enable the plugin.
4. In the extension settings, set up your model name if you want to use a different one than the default. Leave the API key empty if you don't need it. (you wont need it since its for ollama local deployment)
5. All done. Enjoy live translation!

## Added Features

- Add custom settings for switching reasoning for reasoning models
- Custom trimming of translated lines for spaces, new lines and `<think>` tags
- Improve context history handler for better translation quality
- Modify the prompt and applied two-steps translation strategy for better translation quality.

## Customization

You can customize the plugin by modifying the settings in the `.as` file.

**Model Settings**  
| Setting | Description |
|--------|-------------|
| `DEFAULT_MODEL_NAME` | Default model name (default: `"qwen3:14b"`). **This will enable if you didnt setup model in Potplayer's Settings** |
| `bIsReasoningModel` | Set this to true if your model supports reasoning (default: `true`) |
| `bActivateReasoning` | Activate reasoning (default: `false`) |
| `sReasoningActivatePrompt` | Prompt to enable reasoning: `""` |
| `sReasoningDeactivatePrompt` | Prompt to disable reasoning: `"/no_think "` |
| `temperature` | Output randomness (default: `0` for deterministic) |

> Note that enabling reasoning will definitely consume more resources and slow down the translation process, however it may improve the translation quality a lot with two-steps translation strategy.
>
> (Under my testing, it does improve the translation quality a lot XD)

**Prompts**  
| Prompt | Description |
|--------|-------------|
| `systemPrompt` | System prompt for the model. |
| `userPrompt` | User prompt for the model. |

**Context History**  
| Setting | Description |
|--------|-------------|
| `contextHistory` | Stores previous interactions (array of strings) |
| `historyCount` | Number of entries to use (default: `3`) |
| `historyMaxSize` | Maximum history entries (default: `10`) |

> Note if you increase the entries significantly, the response time might increase significantly due to the larger context size. and usually you dont need that large context size.

**Ollama API Settings**  
| Variable | Description | Default Value |
|---------|-------------|---------------|
| `api_key` | API authentication key | (empty, optional) |
| `UserAgent` | HTTP user agent | `"Mozilla/5.0 (Windows NT 10.0; Win64; x64)"` |
| `api_url` | API endpoint | `http://127.0.0.1:11434/v1/chat/completions` |
| `api_url_base` | Base API URL | `http://127.0.0.1:11434` |

## References

> This project is a rewrite of the original PotPlayer_ollama_Translate by yxyxyz6, available at: https://github.com/yxyxyz6/PotPlayer_ollama_Translate

## License

MIT License
