# 🧠 Soul Hub

Neural monitoring dashboard for AI agent swarms. Visualize bot personalities, track trait drift, and manage your swarm from a single interface.

## Features

- **Soul Maps** — Interactive visualization of bot identity, traits, values, and expertise
- **Live Updates** — WebSocket-powered real-time dashboard
- **Remote API** — Any bot on any network can register/update its soul
- **Drift Detection** — Track personality drift over time
- **Swarm Management** — Monitor all agents from one place

## Quick Start

```bash
npm install
npm start
# Open http://localhost:3000
```

## API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/souls` | List all souls |
| GET | `/api/souls/:id` | Get specific soul |
| POST | `/api/souls/:id` | Register/update soul |
| PUT | `/api/souls/:id` | Partial update |
| DELETE | `/api/souls/:id` | Remove soul |
| POST | `/api/souls/:id/observed` | Push observed behavior data |
| GET | `/api/health` | Health check |
| GET | `/api/schema` | Get soul schema |
| WS | `/ws` | Live updates |

## Register a Remote Bot

```bash
curl -X POST https://your-soul-hub.onrender.com/api/souls/my-bot \
  -H "Content-Type: application/json" \
  -H "X-Bot-Name: my-bot" \
  -d '{
    "meta": { "botId": "my-bot", "botName": "My Bot", "role": "Assistant" },
    "declared": {
      "traits": ["Helpful", "Curious", "Precise"],
      "values": ["Accuracy", "Transparency"],
      "skills": { "general": ["conversation", "research"] }
    }
  }'
```

## Deploy to Render

1. Push to GitHub
2. Connect repo on [render.com](https://render.com)
3. It auto-detects `render.yaml` and deploys

## Stack

- **Backend**: Express 5 + WebSocket + Chokidar
- **Frontend**: Pure HTML/CSS/JS (zero build step)
- **Data**: JSON files (soul-maps/*.json)

## License

MIT
