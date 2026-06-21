// Races a promise against a timer so a slow/cold downstream call (e.g.
// Supabase waking from idle) can never stall a caller indefinitely.
async function withTimeout(promise, ms, fallbackValue) {
  let timer;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve(fallbackValue), ms);
  });

  try {
    return await Promise.race([promise, timeout]);
  } catch (error) {
    return fallbackValue;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { withTimeout };
