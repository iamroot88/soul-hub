const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const WebSocket = require('ws');
const chokidar = require('chokidar');
const http = require('http');

const app = express();
const PORT = process.env.PORT || 3000;

// Data directory - use env var for Render, fallback to local
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '../../soul-maps');
const MEMORY_DIR = process.env.MEMORY_DIR || path.join(__dirname, '../../memory');

// Ensure data directories exist
[DATA_DIR, MEMORY_DIR].forEach(dir => {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
});

app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Trust proxy for Render
app.set('trust proxy', 1);

// WebSocket server for hot updates
const wss = new WebSocket.Server({ noServer: true });
let connectedClients = [];

// Serve static files from frontend dist
const distPath = path.join(__dirname, '../frontend/dist');
app.use(express.static(distPath, {
  maxAge: '1h',
  etag: true
}));

// Parse soul maps
function parseSoulMaps() {
  const souls = {};

  try {
    const files = fs.readdirSync(DATA_DIR);
    files.filter(f => f.endsWith('.json') && !['schema.json', 'bootstrap-data.json'].includes(f)).forEach(file => {
      const filePath = path.join(DATA_DIR, file);
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

// Broadcast update to all WebSocket clients
function broadcastUpdate() {
  const souls = parseSoulMaps();
  const update = {
    type: 'update',
    data: souls,
    timestamp: new Date().toISOString()
  };

  connectedClients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      try {
        client.send(JSON.stringify(update));
      } catch (err) {
        console.error('Error sending WebSocket update:', err);
      }
    }
  });
}

// ============================================================
// API Endpoints
// ============================================================

// GET all souls
app.get('/api/souls', (req, res) => {
  const souls = parseSoulMaps();
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    count: Object.keys(souls).length,
    data: souls
  });
});

// GET specific soul
app.get('/api/souls/:id', (req, res) => {
  const souls = parseSoulMaps();
  const soul = souls[req.params.id];
  
  if (!soul) {
    return res.status(404).json({ status: 'error', error: 'Soul not found' });
  }

  res.json({ status: 'ok', data: soul });
});

// POST - Register/update a soul (for remote bots)
app.post('/api/souls/:id', (req, res) => {
  const { id } = req.params;
  const soulData = req.body;

  // Validate
  if (!soulData || typeof soulData !== 'object') {
    return res.status(400).json({ status: 'error', error: 'Invalid soul data' });
  }

  // Ensure meta exists
  if (!soulData.meta) {
    soulData.meta = {};
  }
  soulData.meta.botId = id;
  soulData.meta.lastUpdated = new Date().toISOString();
  soulData.meta.source = req.headers['x-bot-name'] || req.ip || 'remote';

  // Write to disk
  const filePath = path.join(DATA_DIR, `${id}.json`);
  try {
    fs.writeFileSync(filePath, JSON.stringify(soulData, null, 2));
    console.log(`🤖 Soul registered/updated: ${id} (from ${soulData.meta.source})`);
    
    // Broadcast update
    broadcastUpdate();

    res.json({
      status: 'ok',
      message: `Soul '${id}' registered successfully`,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error(`Error writing soul ${id}:`, err);
    res.status(500).json({ status: 'error', error: 'Failed to write soul data' });
  }
});

// PUT - Update specific fields of a soul
app.put('/api/souls/:id', (req, res) => {
  const { id } = req.params;
  const updates = req.body;
  const filePath = path.join(DATA_DIR, `${id}.json`);

  try {
    let existing = {};
    if (fs.existsSync(filePath)) {
      existing = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    }

    // Deep merge
    const merged = deepMerge(existing, updates);
    merged.meta = merged.meta || {};
    merged.meta.botId = id;
    merged.meta.lastUpdated = new Date().toISOString();

    fs.writeFileSync(filePath, JSON.stringify(merged, null, 2));
    console.log(`📝 Soul updated: ${id}`);
    broadcastUpdate();

    res.json({ status: 'ok', message: `Soul '${id}' updated`, data: merged });
  } catch (err) {
    console.error(`Error updating soul ${id}:`, err);
    res.status(500).json({ status: 'error', error: 'Failed to update soul data' });
  }
});

// DELETE a soul
app.delete('/api/souls/:id', (req, res) => {
  const { id } = req.params;
  const filePath = path.join(DATA_DIR, `${id}.json`);

  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ status: 'error', error: 'Soul not found' });
  }

  try {
    fs.unlinkSync(filePath);
    console.log(`🗑️ Soul deleted: ${id}`);
    broadcastUpdate();
    res.json({ status: 'ok', message: `Soul '${id}' deleted` });
  } catch (err) {
    res.status(500).json({ status: 'error', error: 'Failed to delete soul' });
  }
});

// POST - Push observed data for a soul (trait extraction results)
app.post('/api/souls/:id/observed', (req, res) => {
  const { id } = req.params;
  const observedData = req.body;
  const filePath = path.join(DATA_DIR, `${id}.json`);

  try {
    let existing = {};
    if (fs.existsSync(filePath)) {
      existing = JSON.parse(fs.readFileSync(filePath, 'utf-8'));
    }

    existing.observed = observedData;
    existing.meta = existing.meta || {};
    existing.meta.lastObserved = new Date().toISOString();

    fs.writeFileSync(filePath, JSON.stringify(existing, null, 2));
    console.log(`👁️ Observed data updated for: ${id}`);
    broadcastUpdate();

    res.json({ status: 'ok', message: `Observed data for '${id}' updated` });
  } catch (err) {
    res.status(500).json({ status: 'error', error: 'Failed to update observed data' });
  }
});

// GET - Health check
app.get('/api/health', (req, res) => {
  const souls = parseSoulMaps();
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    souls: Object.keys(souls).length,
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// GET - Schema
app.get('/api/schema', (req, res) => {
  const schemaPath = path.join(DATA_DIR, 'schema.json');
  if (fs.existsSync(schemaPath)) {
    const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf-8'));
    res.json({ status: 'ok', data: schema });
  } else {
    res.status(404).json({ status: 'error', error: 'Schema not found' });
  }
});

// Deep merge utility
function deepMerge(target, source) {
  const result = { ...target };
  for (const key of Object.keys(source)) {
    if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
      result[key] = deepMerge(target[key] || {}, source[key]);
    } else {
      result[key] = source[key];
    }
  }
  return result;
}

// Fallback to index.html for SPA routing
app.use((req, res, next) => {
  if (!req.path.startsWith('/api')) {
    res.sendFile(path.join(distPath, 'index.html'));
  } else {
    next();
  }
});

// Create HTTP server
const server = http.createServer(app);

// WebSocket upgrade handler
server.on('upgrade', (request, socket, head) => {
  if (request.url === '/ws') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      console.log('🔌 Client connected to WebSocket');
      connectedClients.push(ws);
      
      ws.on('close', () => {
        connectedClients = connectedClients.filter(c => c !== ws);
        console.log('🔌 Client disconnected');
      });

      ws.on('error', (err) => {
        console.error('WebSocket error:', err);
      });
    });
  } else {
    socket.destroy();
  }
});

// File watcher (local mode only)
if (!process.env.RENDER) {
  const watcher = chokidar.watch([DATA_DIR, MEMORY_DIR], {
    persistent: true,
    awaitWriteFinish: { stabilityThreshold: 500, pollInterval: 100 }
  });

  watcher.on('change', (filePath) => {
    console.log(`📝 File changed: ${filePath}`);
    broadcastUpdate();
  });

  console.log(`👁️ Watching for changes in:\n  - ${DATA_DIR}\n  - ${MEMORY_DIR}`);
}

// Start server
server.listen(PORT, '0.0.0.0', () => {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`🧠 SOUL HUB — LIVE`);
  console.log(`${'='.repeat(60)}`);
  console.log(`\n🚀 Server: http://0.0.0.0:${PORT}`);
  console.log(`\n📡 API endpoints:`);
  console.log(`   GET    /api/souls              (list all souls)`);
  console.log(`   GET    /api/souls/:id           (get soul)`);
  console.log(`   POST   /api/souls/:id           (register/update soul)`);
  console.log(`   PUT    /api/souls/:id           (partial update)`);
  console.log(`   DELETE /api/souls/:id           (remove soul)`);
  console.log(`   POST   /api/souls/:id/observed  (push observed data)`);
  console.log(`   GET    /api/health              (health check)`);
  console.log(`   GET    /api/schema              (get schema)`);
  console.log(`   WS     /ws                      (live updates)`);
  console.log(`\n✨ Frontend: ${distPath}`);
  console.log(`📂 Data: ${DATA_DIR}`);
  console.log(`${'='.repeat(60)}\n`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received, shutting down...');
  server.close(() => {
    process.exit(0);
  });
});
