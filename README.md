# Potplayer Ollama 实时翻译插件

这是一个为 Potplayer 开发的插件，可以使用 Ollama 或者其他自定义 API 进行实时字幕翻译。

<div align="center">
  <strong>简体中文</strong> | <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/docs/README_EN.md">English</a>
</div>
<div align="right">
已测试 Ollama 0.32.15
</div>

## 功能特性

- 实时翻译 PotPlayer 字幕。
- 支持多种 API 协议：Ollama、OpenAI、Anthropic，并通过 JSON 配置自由定制请求参数，详见[自定义配置](#自定义配置)。
- 可自定义系统提示词与用户提示词，提供[提示词合集](docs/prompts.md)。
- 支持带入历史上文，翻译更自然，详见[上文历史](#上文历史)。
- 内存 LRU 缓存翻译历史，重复字幕不再重复请求。

## 目录

- [Potplayer Ollama 实时翻译插件](#potplayer-ollama-实时翻译插件)
  - [功能特性](#功能特性)
  - [目录](#目录)
  - [安装插件](#安装插件)
  - [注意事项](#注意事项)
  - [自定义配置](#自定义配置)
    - [模型选择](#模型选择)
    - [模型配置](#模型配置)
    - [通用配置](#通用配置)
    - [上文历史](#上文历史)
  - [提示词](#提示词)
  - [性能表现](#性能表现)
  - [参考资料](#参考资料)
  - [许可证](#许可证)

## 安装插件

1. 前往 [Release 页面](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases)，下载 `.7z` 或 `.zip` 压缩包，解压后你将得到一个 `.as` 文件和一个 `.ico` 文件。
2. 将这两个文件复制到 PotPlayer 安装目录下的以下文件夹：

   ```text
   ...\DAUM\PotPlayer\Extension\Subtitle\Translate\
   ```

3. 使用文本编辑器或 IDE 打开 `.as` 文件。如果使用 Ollama 以外的服务，在 `Config` 类中修改 `apiFormat` 和 `customEndpoint`，详见[自定义配置](#自定义配置)。
4. 启动 PotPlayer，右键点击视频窗口，依次进入
   `字幕 → 实时字幕翻译`，选择 **Ollama Translate**，然后打开 **实时字幕翻译设置**。
   你也可以通过 `选项 → 扩展功能 → 实时字幕翻译` 打开该设置面板。
5. 在实时字幕翻译设置中，将翻译引擎选择为 **Ollama Translate**。通常情况下，原始语言可保持为 `auto`，目标语言根据你的需求选择。
6. 在账户设置中，将 **Model Name** 设置为你使用的模型名称。
   - **Ollama Cloud** 模型：填写对应的 **API Key**。
   - 本地 Ollama 模型：保持为空。

   点击确认后，确保状态提示为 **“可正常处理”**。

7. 你可以点击 **测试** 按钮发送一次翻译请求，以验证翻译效果。

> 由于 PotPlayer 的机制限制，**测试** 按钮会返回缓存中的翻译结果。在修改配置后请稍微修改测试文本内容，再次测试即可看到新的翻译结果。

## 注意事项

- 请确保使用**支持多语言任务**的模型。
- 根据翻译质量自行调整所用的**提示词**。
- 通常来说，推理/思考**默认应该关闭**，它会显著影响翻译速度，并且翻译任务也不怎么需要推理。如需开启，在对应格式的 JSON 配置中设置。
- 翻译失败的请求会自动重试（次数与间隔见[通用配置](#通用配置)；`retryCount = -1` 持续重试直到成功）。失败的字幕保持原文显示，并在下次显示该字幕时重新翻译。
- 非常推荐使用**Instruct** 模型，如`qwen3.5:27b`，已测试的平台可参考[性能表现](#性能表现)部分。
- **Ollama 本地用户**：请确保 Ollama 和模型均为 **>= 0.9.0**（默认预置的 `think` 参数需要 0.9.0+）。

## 自定义配置

### 模型选择

| 变量             | 描述                                                              |
| ---------------- | ----------------------------------------------------------------- |
| `modelName`      | 模型名称。通常在 PotPlayer 的账户设置中填写，例如 `qwen3.5:27b`。 |
| `apiKey`         | API Key。通常由 PotPlayer 账户设置管理；本地服务可以留空。        |
| `apiFormat`      | API 类型：`ollama`、`openai`、`anthropic`。需要编辑 `.as` 文件。  |
| `customEndpoint` | 自定义服务地址。留空时使用对应服务的默认地址。                    |

模型名与 API Key 的解析顺序：**登录对话框输入 > 代码侧默认（`.as` 文件 `Config` 值）> 上次保存值**。

> 对话框填错时自动回退到代码侧默认值，留空时沿用上次保存值；通过校验的值会被持久化，下次留空也能直接使用。登录时模型名会经服务端模型列表校验（Ollama 为 `/api/tags`，OpenAI 兼容为 `/v1/models`），不在列表中的输入会回退到代码侧默认值。

**默认端点**

| `apiFormat` | 默认端点                                    |
| ----------- | ------------------------------------------- |
| `ollama`    | `http://127.0.0.1:11434`                    |
| `openai`    | `http://127.0.0.1:1234/v1/chat/completions` |
| `anthropic` | `http://127.0.0.1:1234/v1/messages`         |

> `ollama` 格式：API Key 留空 = 本地（`http://127.0.0.1:11434`）；填写 Key = 自动切换到 Ollama Cloud（`https://ollama.com`）。

`customEndpoint` 留空使用上述默认；可填服务主机地址（插件按 `apiFormat` 自动补齐 `/api/chat` / `/v1/chat/completions` / `/v1/messages`）或完整 URL。常见场景：

- Ollama Cloud：`apiFormat = "ollama"`，账户设置填 API Key，`customEndpoint` 留空。
- OpenAI 兼容：`apiFormat = "openai"`，`customEndpoint = "http://localhost:1234"`（LM Studio）、`"https://openrouter.ai/api/v1"`、`"https://api.z.ai/api/paas/v4/chat/completions"`。
- Anthropic 兼容：`apiFormat = "anthropic"`，账户设置填 API Key（本地服务如 LM Studio 无需 Key）。云端 Anthropic 需设置 `customEndpoint = "https://api.anthropic.com"`，本地 LM Studio 可留空走默认地址。Anthropic 格式没有通用的模型列表端点，登录时插件会发送一次极小测试请求来校验模型与密钥。

### 模型配置

三种格式统一为「骨架 + JSON 配置」：请求体只固定 `model` 与 `messages` 等，其余全部参数写在对应 JSON 字段里，原样拼入请求体；设为 `""` 时发送最小骨架（ollama 会补回 stream: false）。内容不是合法 JSON 对象时该字段会被忽略并记录警告。

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

`options` 内可写 ollama 支持的任意采样参数（`top_k`、`seed`、`num_gpu`、`repeat_penalty` 等）；Ollama Cloud 用户可删掉 `keep_alive` 行；推理/思考经顶层 `think` 控制。

**OpenAI `openaiConfigs`**

```javascript
string openaiConfigs = ""
    + "{"
    + "\"temperature\": 0.3, "
    // + "\"reasoning_effort\": \"none\", "
    + "\"chat_template_kwargs\": { \"enable_thinking\": false }"
    + "}";
```

服务端支持的任意参数（`max_tokens`、`top_p`、`reasoning_effort` 等）都可以写在这里。

**Anthropic `anthropicConfigs`**

```javascript
string anthropicConfigs = ""
    + "{"
    + "\"temperature\": 0.3, "
    + "\"max_tokens\": 512"
    + "}";
```

请求体固定保留 `model` + `system` + `messages` + `max_tokens`（必填，未在 JSON 中指定时默认 `256`）。规范约束：`thinking` 的 `budget_tokens` 需 >= 1024 且小于 `max_tokens`，开启思考时 `temperature` 只能为 1。

> 这些字段位于 `.as` 文件的 `Config` 类。参数由服务端校验，请对照所用服务的 API 文档填写。

### 通用配置

| 变量              | 示例值 | 描述                                                                       |
| ----------------- | ------ | -------------------------------------------------------------------------- |
| `cacheMaxEntries` | `500`  | 内存缓存最多保存的翻译数量。                                               |
| `retryCount`      | `-1`   | 翻译失败后的重试次数：`0` 关闭，`-1` 持续重试直到成功，`N` 额外重试 N 次。 |
| `retryDelayMs`    | `500`  | 每次重试前的等待毫秒数；`0` 立即重试。仅在重试轮生效，首次请求不等待。     |

### 上文历史

| 变量             | 示例值 | 描述                       |
| ---------------- | ------ | -------------------------- |
| `contextEnabled` | `true` | 是否使用上文历史进行翻译   |
| `contextCount`   | `7`    | 包含在上文中的最近句子数量 |

> 历史记录条目格式为：`原文 ⇒ 译文`（不含语言元数据）
> 如果显著增加条目数量，由于上下文大小增加，响应时间也可能显著增加。还需要相应调整 token 数量。
> 上文经模板变量 `{{context_raw}}` 注入，无上文时为空字符串。

## 提示词

提示词合集已移至 [docs/prompts.md](docs/prompts.md) 以供参考

模板支持以下变量：

- `{{from}}` 表示源语言
- `{{to}}` 表示目标语言
- `{{text_to_translate}}` 表示需要翻译的文本内容，`userPrompt` 必须保留
- `{{context_raw}}` 表示原始上文内容（`原文 ⇒ 译文` 形式的历史字幕），无上文时为空字符串。

> 编辑提示词时，请要求模型只输出译文，否则解释内容可能泄漏进字幕。

## 性能表现

**Ollama：** 只要你的模型能在 ollama app 或 Ollama cli 里运行，插件就是支持的。

> 请测试你的 token/s，响应过慢的模型可能会导致翻译延迟或失败。根据你的硬件配置和需求进行配置，以确保最佳性能。

已测试平台：

| 平台          | 类型 | 备注                            |
| ------------- | ---- | ------------------------------- |
| LM Studio     | 本地 | OpenAI / Anthropic 兼容端点均可 |
| vLLM          | 本地 | OpenAI 兼容端点                 |
| llama.cpp     | 本地 | OpenAI 兼容端点                 |
| Ollama Cloud  | 云端 | 账户设置中填写 API Key          |
| OpenRouter    | 云端 |                                 |
| Google Gemini | 云端 |                                 |
| Z.Ai          | 云端 |                                 |
| DeepSeek      | 云端 |                                 |
| MiniMax       | 云端 |                                 |

> 理论上支持所有能提供上述 API 格式的服务，但需要你自己配置。仅测试了部分模型，PotPlayer 的翻译调用是逐句进行的，请注意并行和速率限制，以及**费用**。

**注意**：Potplayer现在有内置的函数超时，超时会中断请求连接，如果你的模型加载/服务响应/推理过慢，这个会导致翻译无限失败。在使用更大模型或者思考模式的时候请注意提前加载和思考强度。

## 参考资料

- 受 [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1 版本启发并在此基础上进一步开发。
- Potplayer API 文档位于 PotPlayer 安装目录的 Extension 目录下。
- 更新记录见 [Release 页面](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases)。

## 许可证

MIT 许可证
