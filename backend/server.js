const express = require('express');
const http = require('http');
const path = require('path');
const cors = require('cors');
const helmet = require('helmet');
const { apiLimiter } = require('./middleware/rateLimiters');
const { Server } = require('socket.io');
require('dotenv').config();
const gameRoutes = require('./routes/gameRoutes');
const userRoutes = require('./routes/userRoutes');
const { initializeSocketServer } = require('./websocket/socketServer');
const { logError, getLoggingStatus, probeLoggingTables } = require('./services/logService');

const app = express();
const PORT = Number(process.env.PORT) || 4000;
const server = http.createServer(app);

// CORS allowlist. Comma-separated origins in CORS_ORIGINS (e.g. your web client
// host). If unset, fall back to localhost dev origins only — never wildcard, so
// a hostile site can't drive the API/socket with a victim's credentials.
const allowedOrigins = (process.env.CORS_ORIGINS
  || 'http://localhost:3000,http://localhost:4001,http://10.0.2.2:4001')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

function corsOrigin(origin, callback) {
  // Allow non-browser clients (curl, mobile apps, same-origin) which send no Origin.
  if (!origin) return callback(null, true);
  if (allowedOrigins.includes(origin)) return callback(null, true);
  return callback(new Error('Not allowed by CORS'));
}

const io = new Server(server, {
  cors: {
    origin: corsOrigin,
    methods: ['GET', 'POST'],
  },
});

// Security headers (CSP off for the embedded static demo pages to avoid
// breaking inline scripts; everything else hardened: clickjacking, sniffing).
app.use(helmet({ contentSecurityPolicy: false }));
app.disable('x-powered-by');
app.use(cors({ origin: corsOrigin }));
app.use(express.json({ limit: '64kb' }));

// Global rate limit: blunt protection against scraping/DoS on every route.
app.use(apiLimiter);

// Debug websocket tooling is dev-only. Exposing it in production hands an
// attacker a ready-made socket console; gate it behind EXPOSE_WS_TEST.
if (process.env.EXPOSE_WS_TEST === 'true') {
  app.use('/ws-test', express.static(path.join(__dirname, 'websocket')));
}
app.use('/play', express.static(path.join(__dirname, 'webclient')));

app.use('/api', gameRoutes);
app.use('/api', userRoutes);

// CORS rejections surface as 403 instead of an unhandled 500.
app.use((err, req, res, next) => {
  if (err && err.message === 'Not allowed by CORS') {
    return res.status(403).json({ message: 'Origin not allowed' });
  }
  return next(err);
});

initializeSocketServer(io);

const loggingStatus = getLoggingStatus();
if (!loggingStatus.enabled) {
  console.warn(`Supabase logging disabled: ${loggingStatus.reason || 'not configured'}`);
}

if (!process.env.SUPABASE_JWT_SECRET) {
  console.warn('SUPABASE_JWT_SECRET unset: auth is DISABLED (dev mode). Set it before deploying.');
}

probeLoggingTables()
  .then((result) => {
    if (result.enabled && result.missing.length > 0) {
      console.warn(`Supabase logging tables missing: ${result.missing.join(', ')}`);
      console.warn('Apply backend/sql/logging_tables.sql to enable persistent analytics logs.');
    }
  })
  .catch((error) => {
    console.warn(`Failed to verify logging tables: ${error.message}`);
  });

server.on('error', (error) => {
  if (error && error.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is already in use. Stop the existing process or set PORT to a different value.`);
    process.exit(1);
  }

  throw error;
});

server.listen(PORT, () => {
  console.log(`Sudoku backend running on http://localhost:${PORT}`);
});

process.on('uncaughtException', (err) => {
  logError({
    message: err.message,
    stack: err.stack || null,
    context: {
      type: 'uncaughtException',
    },
  }).catch((logErr) => {
    console.error('Failed to persist uncaughtException log:', logErr.message);
  }).finally(() => {
    console.error('Uncaught exception:', err);
    process.exit(1);
  });
});

process.on('unhandledRejection', (reason) => {
  const message = reason && reason.message ? reason.message : String(reason);
  const stack = reason && reason.stack ? reason.stack : null;

  logError({
    message,
    stack,
    context: {
      type: 'unhandledRejection',
    },
  }).catch((logErr) => {
    console.error('Failed to persist unhandledRejection log:', logErr.message);
  });
});
