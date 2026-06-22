const queue = [];

function getRangeForWaitTime(waitSeconds) {
  if (waitSeconds > 15) return 400;
  if (waitSeconds > 10) return 300;
  if (waitSeconds > 5) return 200;
  return 100;
}

function addToQueue(player) {
  removeFromQueue(player.userId);

  const entry = {
    ...player,
    joinedAt: player.joinedAt || Date.now(),
  };

  queue.push(entry);
  return entry;
}

function findMatch(player) {
  const now = Date.now();
  const playerWaitSeconds = (now - player.joinedAt) / 1000;
  const playerRange = getRangeForWaitTime(playerWaitSeconds);

  const candidates = queue
    .filter((other) => other.userId !== player.userId)
    .filter((other) => {
      const otherWaitSeconds = (now - other.joinedAt) / 1000;
      const otherRange = getRangeForWaitTime(otherWaitSeconds);
      const allowedRange = Math.max(playerRange, otherRange);
      return Math.abs(other.rating - player.rating) <= allowedRange;
    })
    .sort((a, b) => {
      const diffA = Math.abs(a.rating - player.rating);
      const diffB = Math.abs(b.rating - player.rating);
      if (diffA !== diffB) return diffA - diffB;
      return a.joinedAt - b.joinedAt;
    });

  return candidates[0] || null;
}

function removeFromQueue(userId) {
  const index = queue.findIndex((entry) => entry.userId === userId);
  if (index >= 0) {
    queue.splice(index, 1);
  }
}

function getQueuedPlayer(userId) {
  return queue.find((entry) => entry.userId === userId) || null;
}

// Shallow copy so callers can iterate while the underlying queue mutates
// (matches remove entries mid-iteration).
function getQueueSnapshot() {
  return [...queue];
}

module.exports = {
  addToQueue,
  findMatch,
  removeFromQueue,
  getQueuedPlayer,
  getQueueSnapshot,
};
