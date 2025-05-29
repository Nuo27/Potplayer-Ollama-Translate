# Potplayer Ollama 实时翻译插件

**这是一个用 Ollama 实现字幕实时翻译的 Potplayer 插件**

- 支持 Qwen3 & Deepseek-R1 推理模型
- 自定义模型设置
- 优化上下文处理，并可配置

<div align="center">
  <strong >简体中文</a> | <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/master/README.md">English</a>
</div>

## 使用方法

1. 下载 `.as` 和 `.ico` 文件，并将其放置到 Potplayer 安装目录下的 `...\DAUM\PotPlayer\Extension\Subtitle\Translate` 文件夹中。
2. 打开 `.as` 文件，设置默认模型，或者在插件设置中设置模型名称。
3. 运行 PotPlayer，右键 `字幕 -> 实时字幕翻译 -> 实时字幕翻译设置`，启用该插件。
4. 打开插件设置中，如需使用非默认模型请设置模型名称。API Key 留空即可。
5. 完成设置！

## 新增功能

- 对 qwen3 和 deepseek-r1 推理模型的支持
- 添加用于推理模型的自定义设置
- 自定义空格、换行符和 `<think>` 标签的翻译行修剪
- 改进上下文处理，以提高翻译质量
- 修改提示并应用两步翻译策略以提高翻译质量

## 自定义设置

可通过修改 `.as` 文件中的进行的一些自定义设置

**模型设置**  
| 参数 | 说明 |
|------|------|
| `DEFAULT_MODEL_NAME` | 默认模型名称（默认: `"qwen3:14b"`）。**若未在 Potplayer 设置中配置模型将启用此设置** |
| `bIsReasoningModel` | 若模型支持推理请设为 true（默认: `true`） |
| `bActivateReasoning` | 启用推理（默认: `false`） |
| `sReasoningActivatePrompt` | 启用推理提示词: `"/think "` |
| `sReasoningDeactivatePrompt` | 禁用推理提示词: `"/no_think "` |
| `temperature` | 自定义温度（默认: `0` 为确定性输出） |

> 注意，启用推理肯定会消耗更多资源并减慢翻译速度，但配合两步翻译策略应该可以显著提高翻译质量。
>
> （经我测试，翻译质量确实提高了很多 XD）

**提示语**  
| 提示 | 说明 |
|------|------|
| `systemPrompt` | 模型的系统提示语 |
| `userPromptWithContext` | 用户提示词，使用上下文。 |
| `userPromptWithoutContext` | 用户提示词，不使用上下文。 |

> 请根据需要调整提示词，它们会显著影响翻译质量

**上下文历史**  
| 参数 | 说明 |
|------|------|
| `bShouldUseContextHistory` | 是否使用上下文历史进行翻译（默认: `true`） |
| `historyCount` | 使用最近的上下文条数（默认: `3`） |
| `historyMaxSize` | 最大上下文条数（默认: `10`） |

> 请注意：如果上下文条数太大，响应时间可能会显著增加。不过通常不需要那么大的上下文大小。

**Ollama API 设置**  
| 参数 | 说明 | 默认值 |
|------|------|--------|
| `api_key` | API 认证密钥 | （空，可选） |
| `UserAgent` | HTTP 用户代理 | `"Mozilla/5.0 (Windows NT 10.0; Win64; x64)"` |
| `api_url` | API 端点 | `http://127.0.0.1:11434/v1/chat/completions` |
| `api_url_base` | 基础 API 地址 | `http://127.0.0.1:11434` |

**Ollama API 设置**  
| 参数 | 说明 | 默认值 |
|------|------|--------|
| `api_key` | API 认证密钥 | （空，可选） |
| `UserAgent` | HTTP 用户代理 | `"Mozilla/5.0 (Windows NT 10.0; Win64; x64)"` |
| `api_url` | API 端点 | `http://127.0.0.1:11434/v1/chat/completions` |
| `api_url_base` | 基础 API 地址 | `http://127.0.0.1:11434` |

## 参考

> 该项目是对原作者 yxyxyz6 的 PotPlayer_ollama_Translate 进行重写的版本，可在以下链接找到：https://github.com/yxyxyz6/PotPlayer_ollama_Translate

## 许可证

MIT
