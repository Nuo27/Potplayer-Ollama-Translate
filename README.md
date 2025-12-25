# Potplayer Ollama 实时翻译插件

这是一个为 Potplayer 开发的插件，可以使用 Ollama 或者其他自定义 API 进行实时字幕翻译。

<div align="center">
  <strong>简体中文</strong> | <a href="https://github.com/Nuo27/Potplayer-Ollama-Translate/blob/main/README_EN.md">English</a>
</div>

## 功能特性

- 支持自定义翻译提示词
  - 使用变量来替换提示词中的内容 -> [提示词模板](#提示词模板)
- api 支持
  - Ollama 本地原生 api
  - ollama cloud 和自定义 api ->[高级配置](#高级配置和-debug)
- 支持配置推理模型的思考功能，包括 qwen3, deepsseek-r1, gpt-oss -> [推理配置](#推理配置)
- 可以配置的上文历史 -> [上文历史](#上文历史)
- 自定义大模型参数配置 -> [模型配置](#模型配置)

## 目录

- [Potplayer Ollama 实时翻译插件](#potplayer-ollama-实时翻译插件)
  - [功能特性](#功能特性)
  - [目录](#目录)
  - [安装插件](#安装插件)
  - [高级配置和 Debug](#高级配置和-debug)
  - [注意事项](#注意事项)
  - [更新](#更新)
    - [V2.3 主要更新](#v23-主要更新)
  - [TODO](#todo)
  - [关于项目](#关于项目)
  - [自定义配置](#自定义配置)
    - [模型选择](#模型选择)
    - [模型配置](#模型配置)
    - [推理配置](#推理配置)
    - [上文历史](#上文历史)
    - [提示词模板](#提示词模板)
  - [性能表现](#性能表现)
    - [Ollama](#ollama)
    - [外部 API](#外部-api)
  - [参考资料](#参考资料)
  - [许可证](#许可证)

## 安装插件

1. 前往 [Release 页面](https://github.com/Nuo27/Potplayer-Ollama-Translate/releases)，下载 `.7z` 或 `.zip` 压缩包，解压后你将得到一个 `.as` 文件和一个 `.ico` 文件。
2. 将这两个文件复制到 PotPlayer 安装目录下的
   `...\DAUM\PotPlayer\Extension\Subtitle\Translate` 文件夹中。
3. 使用文本编辑器或 IDE 打开 `.as` 文件，修改 `DEFAULT_MODEL_NAME` 的值为**保底模型名称**。当你尚未在扩展设置中配置模型时，将默认使用该模型。
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

## 高级配置和 Debug

- **自定义提示词**：在[提示词模板](#提示词模板)，可根据模板以自定义系统和用户提示词，以适应不同的模型和翻译需求
- **Ollama Cloud**：在账户设置中填入你的 API Key，并使用 Ollama Cloud 的模型进行翻译
  - 不需要单独填入`g_customEndpoint`，请保持为空，插件会根据 API Key 是否为空来判断使用本地还是云端
- **自定义 API**：现在已支持自定义 OpenAI 兼容的 API endpoint
  - 如果使用的是支持 OpenAI 兼容的 API，需要在插件中把 url 填入 `g_customEndpoint`
    - 例如：
      - `http://localhost:1234/v1/chat/completions` - LM Studio
      - `https://openrouter.ai/api/v1/chat/completions` - OpenRouter
    - 插件会检测是否使用 OpenAI 兼容的 API，并检查模型是否在支持列表中
  - 如果使用了一个自定义的 endpoint，请确保它是完整的，并以`/chat/completions`结尾
    - 例如：
      - `https://api.z.ai/api/paas/v4/chat/completions` - Z.AI GLM
    - 插件会跳过模型检查，并直接使用提供的 endpoint 和模型进行翻译
- **Debug**：
  - 在 `OnInitialize` 方法中取消 `HostOpenConsole` 的注释，即可在运行时打开查看控制台输出
  - `HostPrintUTF8` 方法可以用于输出调试信息
  - `HostMessageBox` 方法可以用于弹出消息框

## 注意事项

- Ollama 本地用户请**请确保将模型和 ollama 更新到 >= 0.9.0 版本**
- 请确保使用**支持多语言任务**的模型。
- 根据翻译质量自行调整所用的提示词。
- 通常来说，推理/思考（thinking）**应该关闭**，它会显著影响翻译速度，并且简单的翻译任务也不怎么需要推理。
- 非常推荐使用**Instruct** 模型，如`qwen3:30b-a3b-instruct-2507-q4_K_M`，推荐模型可以参考[性能表现](#性能表现)部分。

## 更新

### V2.3 主要更新

- 重构了提示词模板和处理，并且支持使用变量来替换提示词中的内容。
- 重构了插件的错误处理，并优化了模型/api 的检测逻辑
- 新增了对自定义 api 的支持，你可以指定 api url 和 key 来使用外部 LLM 提交翻译请求。

<details>
<summary>V2.2 主要更新</summary>

- 更新了提示词，提高准确性和通顺度，优化不完整句子的指令
- 重构 API 请求构建，支持 Ollama 原生和 OpenAI 兼容的 API 请求
  - 可以在 ollama api class 里 设定 `useOllamaNative = false`来使用 OpenAI 兼容的 API
- 对于 ollama cloud 用户来说，在模型配置里填上 api key 应该能让你使用 cloud 模型。
  - 没有进行深度测试，如果有问题请提 issue

</details>

## TODO

- [ ] 优化提示词 (长期)
  - 提高翻译质量
- [ ] Terms 术语表
  - 写了一版并且测试了几个 10-14g 左右的模型，但其实在这种小参数模型里效果也差不太多，所以暂时不加入这个功能

## 关于项目

- 如果有其他需求或者遇到了错误，可以提 issue

> 本来这个项目应该是专注于本地 ollama 调用的，现在新增了自定义 api 的功能，本质上变成了一个通用的大模型翻译插件了

## 自定义配置

### 模型选择

| 变量                 | 描述                                                                                                                |
| -------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `DEFAULT_MODEL_NAME` | 默认模型名称（默认值：`"qwen3-vl:30b-a3b-instruct-q4_K_M"`）。**如果没有在 Potplayer 设置中配置模型，将使用该模型** |

### 模型配置

| 变量            | 示例值       | 描述                                                       |
| --------------- | ------------ | ---------------------------------------------------------- |
| `temperature`   | `0.1 - 0.3`  | 较低的值使输出更确定性，更少创造性。                       |
| `topP`          | `0.8 - 0.95` | 只考虑累计概率 ≥ topP 的最小顶级 token 集合。              |
| `topK`          | `20-40`      | 在每个生成步骤中只考虑最可能的前 K 个 token。              |
| `minP`          | `0.01 - 0.1` | 过滤概率低于 minP 的 token，即使它们在 `topP` 或 `topK` 中 |
| `repeatPenalty` | `1.0 - 2.0`  | 对已生成的 token 进行惩罚，阻止重复                        |
| `maxTokens`     | `1024-2048`  | 可生成的最大 token 数量。                                  |

> 可根据需要添加其他参数，但通常来说你只需要调整温度和 topP。请确保相应更新 `GetActiveParams` 方法。

### 推理配置

| 变量             | 示例值                           | 描述                                                                                                                                                        |
| ---------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `enableThinking` | `false`                          | 激活模型中的推理功能。强烈建议`关闭`                                                                                                                        |
| `thinkStrength`  | `"low"` `"medium"` `"high"` `""` | 调整 gpt-oss 模型的思考强度。仅适用于 gpt-oss 且 gpt-oss 模型的思考不能被关闭，如果`enableThinking`被设置成`false`，会自动使用`"low"`强度。默认情况请留空。 |

### 上文历史

| 变量           | 示例值 | 描述                       |
| -------------- | ------ | -------------------------- |
| `enabled`      | `true` | 是否使用上文历史进行翻译   |
| `contextCount` | `5`    | 包含在上文中的最近句子数量 |
| `maxSize`      | `10`   | 历史记录条目的最大数量     |

> 如果显著增加条目数量，由于上下文大小增加，响应时间也可能显著增加。还需要相应调整 token 数量。
> 如果没有历史内容，用户提示词中的 `<Context>` 会被省略。

### 提示词模板

你可以把以下模板应用给你的提示词，使用变量来替换提示词中的内容

- `{{from}}` 表示源语言
- `{{to}}` 表示目标语言
- `{{optional_reference_context}}` 表示可选的参考历史
- `{{text_to_translate}}` 表示需要翻译的文本内容

<details>
<summary>SYSTEM_PROMPT_BASE</summary>

```

const string SYSTEM_PROMPT_BASE =
"You are a professional simultaneous interpreter.\n"
"Translate from {{from}} into {{to}} with natural, fluent, native-sounding output.\n"
"Preserve meaning, tone, emotion, and speaker intent.\n"
"\n"
"Context & History:\n"
"- Reference context and prior turns are for tone, intent, and continuity only\n"
"- Never translate or quote context or history\n"
"- If context conflicts with the current text, translate the current text faithfully\n"
"- Assume the same speaker unless stated otherwise\n"
"\n"
"Rules:\n"
"- Output ONLY the translation in {{to}}\n"
"- Do NOT add explanations or commentary\n"
"- Keep names, numbers, symbols, tags, and formatting unchanged\n"
"- Smooth disfluencies only when it improves natural spoken flow\n"
"- Do not add, omit, or reinterpret meaning\n"
"- If input is fragmentary or incomplete, translate it naturally as-is\n"
"\n"
"Follow the rules strictly, output PLAIN TEXT ONLY.";

```

</details>
<details>
<summary>USER_PROMPT_BASE</summary>

```

const string USER_PROMPT_BASE =
"<Context>\n"
"{{optional_reference_context}}\n"
"</Context>\n"
"\n"
"Translate ONLY the text inside <Text> into {{to}}.\n"
"The context is for tone and continuity only and must NOT be translated.\n"
"\n"
"<Text>\n"
"{{text_to_translate}}\n"
"</Text>";

```

</details>
<details>
<summary>SYSTEM_PROMPT_LONG</summary>

```
const string SYSTEM_PROMPT_LONG =
    "Role: Simultaneous Interpreter\n"
    "\n"
    "Profile\n"
    "- Source Language: {{from}}\n"
    "- Target Language: {{to}}\n"
    "- Description: Act as a senior professional simultaneous interpreter, delivering accurate, natural, and listener-friendly translations suitable for real-time interpretation or subtitles.\n"
    "- Experience: 15+ years in corporate, legal, diplomatic, and technical live interpretation.\n"
    "- Style: Calm, precise, adaptive, and native-sounding.\n"
    "\n"
    "Core Skills\n"
    "1. Interpretation\n"
    "- Accuracy: Preserve original meaning, intent, and tone.\n"
    "- Fluency: Produce natural spoken language; avoid stiff or literal phrasing.\n"
    "- Cultural Adaptation: Adjust expressions appropriately from {{from}} to {{to}}.\n"
    "- Real-time Optimization: Prioritize clarity, brevity, and smooth flow.\n"
    "\n"
    "2. Technical Handling\n"
    "- Terminology Consistency: Maintain domain-specific terms across {{from}} → {{to}}.\n"
    "- Preservation: Keep all names, numbers, symbols, identifiers, code, and tags unchanged.\n"
    "- Formatting: Preserve original punctuation, spacing, and structure.\n"
    "- Smoothing: Remove filler words, repetitions, and minor grammatical issues without altering meaning.\n"
    "\n"
    "Output Rules (Strict)\n"
    "- Output ONLY the translated text in {{to}}.\n"
    "- Do NOT include explanations, notes, comments, or metadata.\n"
    "- Do NOT add, omit, or reinterpret content.\n"
    "- Do NOT use Markdown unless present in the source.\n"
    "- Output plain text only.\n"
    "\n"
    "Context History Handling\n"
    "- The user prompt may include prior context or conversation history in {{from}}.\n"
    "- Use context ONLY as background to resolve references, implied meaning, tone, and terminology consistency.\n"
    "- Translate ONLY the explicitly provided target text from {{from}} to {{to}}.\n"
    "- Do NOT translate, quote, summarize, or reference context history.\n"
    "- If context conflicts with current input, prioritize the current input.\n"
    "- If context is unclear or incomplete, translate conservatively without speculation.\n"
    "\n"
    "Behavioral Guidelines\n"
    "- Optimize output for real-time listening and subtitle readability.\n"
    "- Smooth incomplete or cut-off sentences naturally.\n"
    "- Ensure the final result sounds fluent, native, and effortless in {{to}}.\n"
    "\n"
    "Workflow\n"
    "- Step 1: Read source text ({{from}}) and optional context.\n"
    "- Step 2: Interpret meaning while preserving intent and tone.\n"
    "- Step 3: Refine for fluency and subtitle compatibility in {{to}}.\n"
    "- Result: One clean block of natural, accurate translated text in {{to}}.\n"
    "\n"
    "Initialization\n"
    "Follow all rules strictly and execute tasks exactly as defined.\n";

```

</details>
<details>
<summary>已弃用的系统提示词（供参考）</summary>

- SYSTEM_PROMPT_OLD

```
You are a professional subtitle translator. Your task is to fluently translate text into the target language. Strictly follow these rules:

1. Output only the translated content, without explanations or additional content.
2. Use provided context if provided to aid understanding, but DO NOT include it in your output.
3. Maintain the original tone, style, and narrative of the subtitles.
```

- SYSTEM_PROMPT_BASIC

```
Act as a professional, authentic translation engine dedicated to providing accurate and fluent translations of subtitles.
ONLY provide the translated subtitle text without any additional information.
```

- SYSTEM_PROMPT_BASIC_OLD_TWO_STEP

```
You are a professional subtitle translator skilled in accurate and culturally appropriate translations. I may provide additional context to help clarify the meaning. Use this context to understand the subtitle's meaning and provide an accurate translation. Follow these rules:

1. First, perform a direct translation based on the original text without adding any information.
2. Then, reinterpret the translation to make it sound more natural and understandable in the target language, while preserving the original meaning.
3. Use the provided context and cultural cues to ensure the translation aligns with local language norms and nuances.
4. Your output must only include the translated text—do not include any explanations, context, or commentary.
```

</details>

## 性能表现

### Ollama

**支持模型：**

- 所有 ollama 官方支持的模型
- 所有 ollama 社区支持的 huggingface 模型
- 通过 ollama 配置的自定义模型

> 意思是只要你的模型能在 ollama app 或 Ollama cli 里运行，插件就是支持的。

**推荐**

- qwen3-vl:30b-a3b-instruct-q4_K_M
- qwen3:30b-a3b-instruct-2507-q4_K_M
- gpt-oss:20b
- **qwen3-vl:8b-instruct**
- ministral-3:14b-instruct-2512-q4_K_M
- gemma3:12b/gemma3n:e4b
- 对于配置不高的用户，可以考虑 qwen3:4b-instruct, qwen3-vl:4b-instruct

> 请测试你的 token/s，响应过慢的模型可能会导致翻译延迟或失败。根据你的硬件配置和需求进行配置，以确保最佳性能。

### 外部 API

**推荐**

- 免费
  - GLM4.6V-flash - Z.AI
  - gpt-oss-120b - OpenRouter
  - MiMo-V2-Flash - OpenRouter
  -
- 付费
  - Gemini 3 - Google

> 仅测试了部分模型，但由于 Potplayer 的翻译调用是逐句进行的，请注意并行和速率限制，以及费用

## 参考资料

- 受 [PotPlayer_ollama_Translate](https://github.com/yxyxyz6/PotPlayer_ollama_Translate) v1 版本启发并在此基础上进一步开发。
- 使用 [Angel Script](https://www.angelcode.com/angelscript/) 编写。
- 使用 [Ollama](https://ollama.com/) 提供 LLM 和 API 支持。
- 使用 [OpenAI](https://platform.openai.com/docs/api-reference) API 格式。

## 许可证

MIT 许可证
