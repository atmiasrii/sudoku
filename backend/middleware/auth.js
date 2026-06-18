const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.SUPABASE_JWT_SECRET;

function verifyToken(token) {
  // Supabase signs access tokens with HS256. Pin the algorithm so an attacker
  // can't downgrade to "none" or swap to an asymmetric key we don't control.
  const decoded = jwt.verify(token, JWT_SECRET, { algorithms: ['HS256'] });
  return decoded.sub || decoded.user_id || null;
}

// REST guard. When SUPABASE_JWT_SECRET is unset (local dev), it is a no-op so
// two-player testing works without tokens. In production set the secret to
// enforce a valid Bearer token on every protected route.
function requireAuth(req, res, next) {
  if (!JWT_SECRET) return next();

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Missing authorization' });
  }

  try {
    const userId = verifyToken(authHeader.slice(7));
    if (!userId) return res.status(401).json({ message: 'Invalid token' });
    req.userId = userId;
    return next();
  } catch (error) {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

// Socket.io handshake guard. Same dev no-op behavior. When enforced, the
// verified id is stored as socket.data.authUserId and the rest of the socket
// server trusts that over any client-supplied userId in payloads.
function socketAuth(socket, next) {
  if (!JWT_SECRET) return next();

  const token = socket.handshake.auth?.token
    || socket.handshake.headers?.authorization?.replace(/^Bearer /, '');

  if (!token) return next(new Error('Missing authorization'));

  try {
    const userId = verifyToken(token);
    if (!userId) return next(new Error('Invalid token'));
    socket.data.authUserId = userId;
    return next();
  } catch (error) {
    return next(new Error('Invalid token'));
  }
}

module.exports = { requireAuth, socketAuth };
