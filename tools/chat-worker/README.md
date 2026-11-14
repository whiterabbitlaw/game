# 栖云居畅聊 Worker

P1 本地骨架。默认使用 Cloudflare Workers AI（文本生成 + MeloTTS）。**本目录不会被自动部署**，也不要把密钥写进仓库。

## 本地运行

需要已登录的 Wrangler（`npx wrangler login`）。Workers AI 绑定通常要远程推理：

```bash
cd tools/chat-worker
npx wrangler dev
```

默认监听 `http://127.0.0.1:8787`。游戏端在 `user://chat_config.json` 里可写：

```json
{ "worker_url": "http://127.0.0.1:8787", "tts": true }
```

## 接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/health` | 存活检查 |
| POST | `/v1/chat` | `{ messages, model? }` → `{ text, model }` |
| POST | `/v1/tts` | `{ text, lang? }` → `{ audio }`（base64 MP3） |
| POST | `/v1/summarize` | `{ messages }` → `{ text }`，给记忆滚动摘要用 |

默认模型是 `@cf/qwen/qwen3-30b-a3b-fp8`（中文相对合适、神经元消耗较低）。可在请求体或 `MODEL` 环境变量里覆盖。

若设置了 `GEMINI_API_KEY` 密钥，文本生成会优先走 Gemini；免费档的提示可能会被用于改进 Google 产品，请在上线前自行权衡。

若设置了 `CHAT_TOKEN`，请求需带 `Authorization: Bearer <token>`（`/health` 除外）。本地不设则不校验，**公开部署前请务必加上**。

## 不要做的事

- 不要把 `.dev.vars`、密钥、账号 ID 提交进公开仓库
- 不要在未获玩家同意时，把聊天记录同步到服务器
