const { getUserRating, updateUserRating } = require('./userService');

async function setUserRating(userId, rating) {
  return updateUserRating(userId, rating);
}

async function adjustUserRating(userId, delta) {
  const currentRating = await getUserRating(userId);
  const nextRating = Number(currentRating || 1200) + Number(delta || 0);
  return updateUserRating(userId, nextRating);
}

module.exports = {
  setUserRating,
  adjustUserRating,
};
