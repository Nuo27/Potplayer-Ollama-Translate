# Potplayer Ollama 实时翻译插件

这是一个为 Potplayer 开发的插件，可以使用 Ollama 或者其他自定义 API 进行实时字幕翻译。

<div align="center">
  <strong>简体中文</strong> | <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/README_EN.md">English</a>
</div>
<div align="right">
Ollama测试版本：0.32.1
</div>

## 功能特性

- 实时翻译 PotPlayer 字幕。
- 支持多种 API 协议：Ollama 原生、LM Studio REST、OpenAI 兼容、Anthropic 兼容，详见[高级配置和 Debug](#高级配置和-debug)。
- 支持 Ollama Cloud、云端 OpenAI / Anthropic 兼容 API。
- 可自定义系统提示词、用户提示词和上下文提示词，提供 [提示词合集](prompts.md)。
- 可配置模型参数（`temperature`、`topP`、`contextLength`、`maxTokens`），详见[模型配置](#模型配置)。
- 支持上文历史（最近 N 条字幕），翻译更自然，详见[上文历史](#上文历史)。
- 支持翻译缓存（内存 + 可选磁盘），重复字幕不再重复请求。
- 可控制推理模型的思考模式，包括 qwen3、deepseek-r1、gpt-oss，详见[推理配置](#推理配置)。
- 网络异常时自动重试，错误日志包含诊断信息。

## 目录

- [Potplayer Ollama 实时翻译插件](#potplayer-ollama-实时翻译插件)
  - [功能特性](#功能特性)
  - [目录](#目录)
  - [安装插件](#安装插件)
  - [注意事项](#注意事项)
  - [更新](#更新)
    - [V3.0 主要更新](#v30-主要更新)
  - [关于项目](#关于项目)
  - [自定义配置](#自定义配置)
    - [模型选择](#模型选择)
    - [模型配置](#模型配置)
    - [推理配置](#推理配置)
    - [上文历史](#上文历史)
    - [提示词模板](#提示词模板)
  - [高级配置和 Debug](#高级配置和-debug)
    - [选择 API 类型](#选择-api-类型)
    - [Ollama Cloud](#ollama-cloud)
    - [LM Studio REST](#lm-studio-rest)
    - [OpenAI 兼容 API](#openai-兼容-api)
    - [Anthropic 兼容 API](#anthropic-兼容-api)
    - [自定义端点](#自定义端点)
    - [Debug](#debug)
  - [性能表现](#性能表现)
    - [Ollama](#ollama)
    - [本地其他服务](#本地其他服务)
    - [云端 API](#云端-api)
  - [参考资料](#参考资料)
  - [许可证](#许可证)

## 安装插件

1. 前往 [Release 页面](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases)，下载 `.7z` 或 `.zip` 压缩包，解压后你将得到一个 `.as` 文件和一个 `.ico` 文件。
2. 将这两个文件复制到 PotPlayer 安装目录下的
   `...\DAUM\PotPlayer\Extension\Subtitle\Translate` 文件夹中。
3. 使用文本编辑器或 IDE 打开 `.as` 文件。如果使用 Ollama 以外的服务，在 `Config` 类中修改 `apiFormat` 和 `customEndpoint`，详见[高级配置和 Debug](#高级配置和-debug)。
4. 启动 PotPlayer，右键点击视频窗口，依次进入
   `字幕 → 实时字幕翻译`，选择 **Ollama Translate**，然后打开 **实时字幕翻译设置**。
   你也可以通过 `选项 → 扩展功能 → 实时字幕翻译` 打开该设置面板。
5. 在实时字幕翻译设置中，将翻译引擎选择为 **Ollama Translate**。通常情况下，原始语言可保持为 `auto`，目标语言根据你的需求选择。
6. 在账户设置中，将 **Model Name** 设置为你使用的模型名称。
   - 如果你使用的是 **Ollama Cloud** 模型，请填写对应的 **API Key**；
   - 如果是本地 Ollama 模型，则保持为空即可。
     点击确认后，确保状态提示为 **“可正常处理”**。

7. 配置完成后即可使用。你可以点击 **测试** 按钮发送一次翻译请求，以验证翻译效果。

> 由于 PotPlayer 的机制限制，**测试** 按钮会返回缓存中的翻译结果。在修改配置后请稍微修改测试文本内容，再次测试即可看到新的翻译结果。

## 注意事项

- Ollama 本地用户请**请确保将模型和 ollama 更新到 >= 0.9.0 版本**
- 请确保使用**支持多语言任务**的模型。
- 根据翻译质量自行调整所用的提示词。
- 通常来说，推理/思考（thinking）**默认应该关闭**，它会显著影响翻译速度，并且简单的翻译任务也不怎么需要推理。
- 非常推荐使用**Instruct** 模型，如`qwen3.5:27b`，推荐模型可以参考[性能表现](#性能表现)部分。

## 更新

### V3.0 主要更新

- 插件代码重构，并移除不必要的模型参数设置
- 重构 API 调用和错误处理流程，网络失败时自动重试。
- 支持 `ollama`、`rest`、`openai`、`anthropic` 四种 API 类型。
- 新增上下文记忆和翻译缓存。

<details>
<summary>V2.4 主要更新</summary>

- 更新了提示词，提高准确性和通顺度，优化不完整句子的指令
- 重构 API 请求构建，支持 Ollama 原生和 OpenAI 兼容的 API 请求
  - 可以在 ollama api class 里 设定 `useOllamaNative = false`来使用 OpenAI 兼容的 API
- 对于 ollama cloud 用户来说，在模型配置里填上 api key 应该能让你使用 cloud 模型。
  - 没有进行深度测试，如果有问题请提 issue

</details>

## 关于项目

- 如果有其他需求或者遇到了错误，可以提 issue

> 本来这个项目应该是专注于本地 ollama 调用的，现在新增了自定义 api 的功能，本质上变成了一个通用的大模型翻译插件了

## 自定义配置

### 模型选择

| 变量             | 描述                                                                     |
| ---------------- | ------------------------------------------------------------------------ |
| `modelName`      | 模型名称。通常在 PotPlayer 的账户设置中填写，例如 `qwen3:9b`。           |
| `apiKey`         | API Key。通常由 PotPlayer 账户设置管理；本地 Ollama 可以留空。           |
| `apiFormat`      | API 类型：`ollama`、`rest`、`openai`、`anthropic`。需要编辑 `.as` 文件。 |
| `customEndpoint` | 自定义服务地址。留空时使用对应服务的默认地址。                           |

### 模型配置

| 变量              | 示例值       | 描述                                                       |
| ----------------- | ------------ | ---------------------------------------------------------- |
| `temperature`     | `0.1 - 0.3`  | 较低值让翻译更稳定，推荐保持 `0.3`。                       |
| `topP`            | `0.8 - 0.95` | 控制模型选词范围，通常不用修改。                           |
| `contextLength`   | `4096`       | 上下文窗口大小。越大越占用显存，普通字幕保持 `4096`。      |
| `maxTokens`       | `512`        | 单次输出长度上限。普通字幕保持 `512`。                     |
| `cacheMaxEntries` | `500`        | 内存缓存最多保存的翻译数量。                               |

> 这些配置位于 `.as` 文件的 `Config` 类。通常只需要调整 `temperature` 和 `contextEnabled`。不要随意添加不存在的参数。

### 推理配置

| 变量             | 示例值                           | 描述                                 |
| ---------------- | -------------------------------- | ------------------------------------ |
| `enableThinking` | `false`                          | 激活模型中的推理功能。强烈建议`关闭` |
| `thinkStrength`  | `"low"` `"medium"` `"high"` `""` | 调整模型的思考强度。默认情况请留空。 |

### 上文历史

| 变量             | 示例值                   | 描述                       |
| ---------------- | ------------------------ | -------------------------- |
| `contextEnabled` | `true`                   | 是否使用上文历史进行翻译   |
| `contextCount`   | `7`                      | 包含在上文中的最近句子数量 |
| `contextPrompt`  | [prompts.md](prompts.md) | 自定义上下文提示词模板     |

> 历史记录条目包含原文、译文和语言元数据，格式为：`[源语言] 原文 -> [目标语言] 译文`
> 如果显著增加条目数量，由于上下文大小增加，响应时间也可能显著增加。还需要相应调整 token 数量。
> 仅当 `contextEnabled` 启用且 `contextPrompt` 非空时，上下文才会被注入到提示词中。

### 提示词模板

提示词合集已移至 [prompts.md](prompts.md) 以供参考

其中包含：

- 默认系统、用户和上下文提示词
- 自然口语字幕
- 正式准确翻译
- 游戏术语翻译
- 保留语气、俚语和脏话
- 自定义术语表

模板支持以下变量：

- `{{from}}` 表示源语言
- `{{to}}` 表示目标语言
- `{{optional_reference_context}}` 表示可选的参考历史
- `{{text_to_translate}}` 表示需要翻译的文本内容，`userPrompt` 必须保留
- `{{context_prompt}}` 表示上下文提示词模板

> 修改提示词时，建议要求模型只输出译文。否则模型可能把解释内容也显示到字幕中。

## 高级配置和 Debug

插件支持四种 API 协议，在 `.as` 文件的 `Config` 类中切换：

```javascript
class Config {
    string apiFormat = "ollama";   // ollama | rest | openai | anthropic
    string customEndpoint = "";
}
```

`apiFormat` 和 `customEndpoint` 不在 PotPlayer 登录界面中，必须直接编辑 `.as` 文件修改。修改后重启 PotPlayer。

### 选择 API 类型

| `apiFormat` | 服务           | 默认端点                                    |
| ----------- | -------------- | ------------------------------------------- |
| `ollama`    | Ollama         | `http://127.0.0.1:11434`                    |
| `rest`      | LM Studio REST | `http://127.0.0.1:1234/api/v1/chat`         |
| `openai`    | OpenAI 兼容    | `http://127.0.0.1:1234/v1/chat/completions` |
| `anthropic` | Anthropic 兼容 | `http://127.0.0.1:1234/v1/messages`         |

### Ollama Cloud

- 在账户设置中填入 API Key。
- `apiFormat` 保持为 `"ollama"`。
- `customEndpoint` 保持为空。
- 插件会自动使用云端 API。

### LM Studio REST

- 将 `apiFormat` 改为 `"rest"`。
- 默认地址为 `http://127.0.0.1:1234/api/v1/chat`。
- 在 LM Studio 中开启本地服务并加载模型。

### OpenAI 兼容 API

- 将 `apiFormat` 改为 `"openai"`。
- 在 `customEndpoint` 中填写服务地址，例如：
  - `http://localhost:1234` - LM Studio
  - `https://openrouter.ai/api/v1` - OpenRouter
  - `https://api.z.ai/api/paas/v4` - Z.AI GLM

### Anthropic 兼容 API

- 将 `apiFormat` 改为 `"anthropic"`。
- 在账户设置中填写 API Key。
- 在 `customEndpoint` 中填写服务地址。

### 自定义端点

- `customEndpoint` 可以填写服务主机地址，也可以填写完整地址。
- 插件会根据 `apiFormat` 自动补齐 API 路径。
- 例如 `http://localhost:1234` 会自动补为 `/api/chat` 或 `/v1/chat/completions` 等。

### Debug

- 在 `OnInitialize` 方法中取消 `HostOpenConsole` 的注释，即可在运行时打开控制台。
- `HostPrintUTF8` 方法可以输出调试信息。
- `HostMessageBox` 方法可以弹出消息框。

> 高级设置面向熟悉模型和 API 的用户。普通用户只需使用默认的 Ollama 配置。

## 性能表现

### Ollama

**支持模型：** 只要你的模型能在 ollama app 或 Ollama cli 里运行，插件就是支持的。

> 请测试你的 token/s，响应过慢的模型可能会导致翻译延迟或失败。根据你的硬件配置和需求进行配置，以确保最佳性能。

### 本地其他服务

已测试平台：

- LM Studio
- vLLM
- llama.cpp

> 理论上支持所有本地运行的模型，但需要你自己配置。
> 请优先提前加载模型，以避免因模型加载导致的翻译延迟。

### 云端 API

已测试平台：

- Ollama Cloud
- OpenRouter
- Google Gemini
- Z.Ai
- DeepSeek
- Minimax

> 仅测试了部分模型，但由于 Potplayer 的翻译调用是逐句进行的，请注意并行和速率限制，以及**费用**

## 参考资料

- 受 [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1 版本启发并在此基础上进一步开发。
- 使用 [Angel Script](https://www.angelcode.com/angelscript/) 编写。
- 使用 [Ollama](https://ollama.com/) 提供 LLM 和 API 支持。
- 使用 [OpenAI](https://platform.openai.com/docs/api-reference) API 格式。

## 许可证

MIT 许可证
