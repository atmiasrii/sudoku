function calculateElo(playerRating, opponentRating, score) {
  const K = 32;

  const expected = 1 / (1 + Math.pow(10, (opponentRating - playerRating) / 400));

  return Math.round(playerRating + K * (score - expected));
}

module.exports = {
  calculateElo,
};
