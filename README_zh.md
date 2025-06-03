# Potplayer Ollama 实时翻译插件

这是一个为 Potplayer 开发的插件，可以使用 Ollama 进行实时字幕翻译。

- 支持 Qwen3 和 Deepseek-R1 推理模型
- 允许模型自定义设置选项
- 更好的上下文处理，可自定义配置
- 意译、改写和两步翻译策略

<div align="center">
  <strong>简体中文</strong> | <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/master/README.md">English</a>
</div>

## 目录

- [Potplayer Ollama 实时翻译插件](#potplayer-ollama-实时翻译插件)
  - [目录](#目录)
  - [功能特性](#功能特性)
  - [使用方法](#使用方法)
  - [注意事项](#注意事项)
  - [自定义配置](#自定义配置)
  - [性能表现](#性能表现)
  - [参考资料](#参考资料)
  - [许可证](#许可证)

## 功能特性

- 新增对推理模型的支持
- 改进上下文历史处理器
- 改述和两步翻译策略
- 自定义模型配置（温度参数、top_p 等）

## 使用方法

1. 下载 `.as` 和 `.ico` 文件，将它们放置到 Potplayer 安装目录下的 `...\DAUM\PotPlayer\Extension\Subtitle\Translate` 文件夹中。
2. 打开 `.as` 文件，修改 `DEFAULT_MODEL_NAME` 为目标模型名称。或者也可以保持默认设置，稍后在扩展设置中配置。
3. 如果需要，可以自由调整**提示词**、**模型配置**和上下文历史大小。
4. 如果使用推理模型，请确保设置推理模型配置。`强烈建议关闭推理功能。`
5. 运行 PotPlayer，右键打开设置 / 按 F5。然后前往 `字幕 -> 字幕翻译 -> 在线字幕翻译设置`，选择并启用插件。
6. 在扩展设置中，如果想使用不同于默认的模型，请设置模型名称。由于使用的是 ollama，不需要 API 密钥。
7. 完成

## 注意事项

- **请确保将模型和 ollama 更新到 >= 0.9.0 版本**，以使用 ollama 的原生思考支持。qwen3 的思考提示词尚未移除，因为在我的测试中它并没有真正起作用。
- 使用旧模板和功能的 Qwen3、Deepseek-r1 以及 ollama <0.9.0 版本是**兼容的**，但其他模型可能不兼容。可以在 `ModelConfig` 下手动添加它们的思考标签和 `bool` 值，在 `options` 字段中添加项目。
- 请记住根据需求调整**提示词**，因为它们会显著影响输出质量。
- 请确保模型**支持多语言任务**，否则翻译质量可能会受到影响。
- 如果不需要，**应该关闭**推理功能，因为它会显著影响翻译速度。

## 自定义配置

**模型选择**
| 变量 | 描述 |
|--------|-------------|
| `DEFAULT_MODEL_NAME` | 默认模型名称（默认值：`"qwen3:14b"`）。**如果没有在 Potplayer 设置中配置模型，将启用此设置** |

**模型配置**  
| 变量 | 推荐值 | 描述 |
|--------|-------------|-------------|
| `temperature` | `0.1 - 0.3` | 较低的值使输出更确定性，更少创造性。**如果想要改述翻译，可能需要稍微增加此值**|
| `topP` | `0.8 - 0.95` | 只考虑累计概率 ≥ topP 的最小顶级 token 集合。|
|`topK`| `20-40` | 在每个生成步骤中只考虑最可能的前 K 个 token。|
| `minP` | `0.01 - 0.1` | 过滤概率低于 minP 的 token，即使它们在 `topP` 或 `topK` 中|
|`repeatPenalty` | `1.0 - 2.0` | 对已生成的 token 进行惩罚，阻止重复|
|`maxTokens` | `1024-2048` | 可生成的最大 token 数量。不过不需要调整这个，因为 ollama 不会限制。|

> 可根据需要添加其他参数。请确保相应更新 `GetActiveParams` 方法。

**推理配置**  
| 变量 | 推荐值 | 描述 |
|--------|-------------|-------------|
| `isReasoningModel` | `false` | 只有在使用支持推理的模型时才选中此项。 |
| `activateReasoning` | `false` | 激活模型中的推理功能。强烈建议`关闭`|

**上下文历史**  
| 变量 | 推荐值 | 描述 |
|--------|-------------|-------------|
| `enabled` | `true` | 是否使用上下文历史进行翻译 |
| `contextCount` | `10` | 包含在上下文中的最近句子数量
| `maxSize` | `50` | 历史记录条目的最大数量 |

> 如果显著增加条目数量，由于上下文大小增加，响应时间也可能显著增加。还需要相应调整 token 数量。

**提示词**  
| 提示词 | 描述 |
|--------|-------------|
| `SYSTEM_PROMPT` | 此提示词和上下文历史将合并形成模型的最终系统提示词。 |
| `USER_PROMPT_BASE` | 默认要求模型改述输出的用户提示词。 |
| `backup_system_prompt` | 备用系统提示词。|
| `two_step_process_prompt` | 默认要求模型遵循两步过程的用户提示词 |

## 性能表现

**测试模型：**

- qwen3:14b
- gemma3:12b
- deepseek-r1:14b-qwen-distill-q4_K_M
- aya-expanse:8b
- granite3.3:8b
- phi4:14b
- llama3.1:8b

**推荐**

- qwen3:14b（未启用思考功能）是迄今为止使用此提示词测试的最佳模型。
- gemma3:12b 在一般提示词下输出质量良好。
- 其他模型也还不错，但不如 qwen3。

> 调整提示词对模型性能有很大影响，这些建议仅供参考。

## 参考资料

- 受 [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1 版本启发并在此基础上进一步开发。
- 使用 [Angel Script](https://www.angelcode.com/angelscript/) 编写。
- 使用 [Ollama](https://ollama.com/) 提供 LLM 和 API 支持。

## 许可证

MIT 许可证
