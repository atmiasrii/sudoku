let supabase = null;
let loggingDisabledReason = null;

try {
  // Keep logging optional: if env is missing, gameplay should still run.
  // eslint-disable-next-line global-require
  supabase = require('../config/supabase');
} catch (error) {
  loggingDisabledReason = error.message;
}

async function safeInsert(table, payload) {
  if (!supabase) {
    return {
      ok: false,
      skipped: true,
      reason: loggingDisabledReason || 'Supabase not configured',
    };
  }

  const { error } = await supabase.from(table).insert(payload);
  if (error) {
    throw new Error(`Failed to write ${table}: ${error.message}`);
  }

  return { ok: true };
}

async function logMatch(data) {
  return safeInsert('match_logs', data);
}

async function logSuspicious(data) {
  return safeInsert('suspicious_activity', data);
}

async function logDisconnect(data) {
  return safeInsert('disconnect_logs', data);
}

async function logError(data) {
  return safeInsert('error_logs', data);
}

async function logQueue(data) {
  return safeInsert('queue_logs', data);
}

function getLoggingStatus() {
  return {
    enabled: Boolean(supabase),
    reason: loggingDisabledReason,
  };
}

async function probeLoggingTables() {
  const tables = [
    'match_logs',
    'suspicious_activity',
    'disconnect_logs',
    'error_logs',
    'queue_logs',
  ];

  if (!supabase) {
    return {
      enabled: false,
      missing: tables,
      details: [{ table: '*', ok: false, message: loggingDisabledReason || 'Supabase not configured' }],
    };
  }

  const details = [];
  for (const table of tables) {
    const { error } = await supabase.from(table).select('*').limit(1);
    if (error) {
      details.push({ table, ok: false, message: error.message });
    } else {
      details.push({ table, ok: true, message: null });
    }
  }

  const missing = details.filter((d) => !d.ok).map((d) => d.table);
  return {
    enabled: true,
    missing,
    details,
  };
}

module.exports = {
  logMatch,
  logSuspicious,
  logDisconnect,
  logError,
  logQueue,
  getLoggingStatus,
  probeLoggingTables,
};
