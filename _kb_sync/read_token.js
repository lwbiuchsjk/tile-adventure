#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

function getArg(name) {
  const idx = process.argv.indexOf(name);
  if (idx === -1 || idx + 1 >= process.argv.length) return '';
  return process.argv[idx + 1];
}

(async () => {
  try {
    const larkRoot = getArg('--larkRoot');
    const appId = getArg('--appId');
    if (!larkRoot || !appId) {
      console.log(JSON.stringify({ ok: false, error: 'missing args: --larkRoot --appId' }));
      process.exit(1);
    }

    const storePath = path.join(larkRoot, 'dist', 'auth', 'store.js');
    if (!fs.existsSync(storePath)) {
      console.log(JSON.stringify({ ok: false, error: `store.js not found: ${storePath}` }));
      process.exit(1);
    }

    const { authStore } = require(storePath);
    const localTokens = await authStore.getAllLocalAccessTokens();
    const token = localTokens ? localTokens[appId] : '';
    if (!token) {
      console.log(JSON.stringify({ ok: false, error: `no user token for appId=${appId}` }));
      process.exit(1);
    }

    const tokenInfo = await authStore.getToken(token);
    console.log(JSON.stringify({
      ok: true,
      appId,
      userAccessToken: token,
      scopes: tokenInfo?.scopes || [],
      expiresAt: tokenInfo?.expiresAt || 0
    }));
    process.exit(0);
  } catch (err) {
    console.log(JSON.stringify({ ok: false, error: String(err) }));
    process.exit(1);
  }
})();

