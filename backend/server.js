const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const WebSocket = require('ws');
const chokidar = require('chokidar');

const app = express();
const PORT = 3001;

app.use(cors());
app.use(express.json());

// WebSocket server for hot updates
const wss = new WebSocket.Server({ noServer: true });
let connectedClients = [];

// Parse soul maps and memory files
function parseSoulMaps() {
  const soulMapsDir = path.join(__dirname, '../../soul-maps');
  const souls = {};

  try {
    const files = fs.readdirSync(soulMapsDir);
    files.filter(f => f.endsWith('.json') && f !== 'schema.json').forEach(file => {
      const filePath = path.join(soulMapsDir, file);
      const content = fs.readFileSync(filePath, 'utf-8');
      const data = JSON.parse(content);
      const soulId = data.meta?.botId || file.replace('.json', '');
      souls[soulId] = {
        ...data,
        traits: extractTraits(data),
        vectors: generateVectors(data)
      };
    });
  } catch (err) {
    console.error('Error parsing soul maps:', err);
  }

  return souls;
}

function extractTraits(soulData) {
  const declared = soulData.declared?.traits || [];
  const observed = soulData.observed?.traits || {};
  return {
    declared: Array.isArray(declared) ? declared : [],
    observed: Array.isArray(observed) ? observed : Object.keys(observed)
  };
}

function generateVectors(soulData) {
  const traits = soulData.declared?.traits || [];
  const baseVectors = {};
  
  traits.forEach((trait, idx) => {
    const angle = (idx / traits.length) * Math.PI * 2;
    const value = 0.5 + Math.random() * 0.5;
    baseVectors[trait] = {
      angle,
      value,
      x: Math.cos(angle) * value,
      y: Math.sin(angle) * value
    };
  });

  return baseVectors;
}

// API Endpoint: /api/souls
app.get('/api/souls', (req, res) => {
  const souls = parseSoulMaps();
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    data: souls
  });
});

// API Endpoint: /api/souls/:id
app.get('/api/souls/:id', (req, res) => {
  const souls = parseSoulMaps();
  const soul = souls[req.params.id];
  
  if (!soul) {
    return res.status(404).json({ error: 'Soul not found' });
  }

  res.json({
    status: 'ok',
    data: soul
  });
});

// WebSocket upgrade
const server = app.listen(PORT, () => {
  console.log(`Backend API running at http://localhost:${PORT}`);
});

server.on('upgrade', (request, socket, head) => {
  if (request.url === '/ws') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      console.log('Client connected to WebSocket');
      connectedClients.push(ws);
      ws.on('close', () => {
        connectedClients = connectedClients.filter(c => c !== ws);
        console.log('Client disconnected');
      });
    });
  }
});

// File watcher
const soulMapsDir = path.join(__dirname, '../../soul-maps');
const memoryDir = path.join(__dirname, '../../memory');

const watcher = chokidar.watch([soulMapsDir, memoryDir], {
  persistent: true,
  awaitWriteFinish: { stabilityThreshold: 500, pollInterval: 100 }
});

watcher.on('change', () => {
  console.log('Files changed, broadcasting update...');
  const souls = parseSoulMaps();
  const update = {
    type: 'update',
    data: souls,
    timestamp: new Date().toISOString()
  };

  connectedClients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(update));
    }
  });
});

console.log(`Watching for changes in ${soulMapsDir} and ${memoryDir}`);
