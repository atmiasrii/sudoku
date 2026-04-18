const express = require('express');
const http = require('http');
const path = require('path');
const cors = require('cors');
const { Server } = require('socket.io');
require('dotenv').config();
const gameRoutes = require('./routes/gameRoutes');
const userRoutes = require('./routes/userRoutes');
const { initializeSocketServer } = require('./websocket/socketServer');
const { logError, getLoggingStatus, probeLoggingTables } = require('./services/logService');

const app = express();
const PORT = Number(process.env.PORT) || 4000;
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
  },
});

app.use(cors());
app.use(express.json());
app.use('/ws-test', express.static(path.join(__dirname, 'websocket')));

app.use('/api', gameRoutes);
app.use('/api', userRoutes);

initializeSocketServer(io);

const loggingStatus = getLoggingStatus();
if (!loggingStatus.enabled) {
  console.warn(`Supabase logging disabled: ${loggingStatus.reason || 'not configured'}`);
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
