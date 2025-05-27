# Potplayer Ollama 实时翻译插件

这是一个用于 Potplayer 的插件，可通过 Ollama 实现字幕的实时翻译。

<div align="center">
  <strong >简体中文</a> | <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/master/README.md">English</a>
</div>

## 使用方法

1. 下载 `.as` 和 `.ico` 文件，并将其放置到 Potplayer 安装目录下的 `...\DAUM\PotPlayer\Extension\Subtitle\Translate` 文件夹中。
2. 打开 `.as` 文件，按需调整默认模型名字。
3. 运行 PotPlayer，右键 `字幕 -> 实时字幕翻译 -> 实时字幕翻译设置`，启用该插件。
4. 在插件设置中，如需使用非默认模型请设置模型名称。如不需要 API 密钥则留空。
5. 完成设置，享受实时翻译功能！

## 新增功能

- 添加用于推理模型切换推理的自定义设置
- 添加自定义温度设置
- 自定义空格、换行符和 `<think>` 标签的翻译行修剪
- 改进上下文历史记录处理，以提高翻译质量
- 修改提示并应用两步翻译策略以提高翻译质量（如果模型支持推理，翻译质量应该会大幅提升，但这将耗费更多时间和资源。）

## 自定义设置

可通过修改 `.as` 文件中的设置或通过 PotPlayer 插件设置界面自定义插件。以下是一些可能需要调整的变量：

**模型设置**  
| 参数 | 说明 |
|------|------|
| `DEFAULT_MODEL_NAME` | 默认模型名称（默认: `"qwen3:14b"`）。**若未在 Potplayer 设置中配置模型将启用此设置** |
| `bIsReasoningModel` | 若模型支持推理请设为 true（默认: `true`） |
| `bActivateReasoning` | 启用推理（默认: `false`） |
| `sReasoningActivatePrompt` | 启用推理提示词: `""` |
| `sReasoningDeactivatePrompt` | 禁用推理提示词: `"/no_think "` |
| `temperature` | 自定义温度（默认: `0` 为确定性输出） |

**提示语**  
| 提示 | 说明 |
|------|------|
| `systemPrompt` | 模型的系统提示语 |
| `userPrompt` | 模型的用户提示语 |

**上下文历史**  
| 参数 | 说明 |
|------|------|
| `historyCount` | 使用最近的上下文条数（默认: `3`） |
| `historyMaxSize` | 最大上下文条数（默认: `10`） |

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
