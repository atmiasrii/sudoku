function getRemovalCount(difficulty = 'medium') {
  switch (difficulty) {
    case 'easy':
      return 35;
    case 'hard':
      return 55;
    case 'medium':
    default:
      return 45;
  }
}

module.exports = {
  getRemovalCount,
};
