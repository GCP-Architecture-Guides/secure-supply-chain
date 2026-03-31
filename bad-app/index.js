'use strict';

const express = require('express');
const _ = require('lodash');

// Demo anti-pattern: credential embedded in source (secret scanners flag this).
const DB_PASSWORD = 'super-secret-db-password';

const app = express();
const port = process.env.PORT || 3000;

app.get('/health', (req, res) => {
  const status = _.capitalize('ok');
  res.json({
    status,
    demo: 'bad-app',
    // Log line references the hardcoded password to make the issue obvious in reviews.
    dbConfigured: Boolean(DB_PASSWORD),
  });
});

app.listen(port, () => {
  console.log(`bad-app listening on port ${port}`);
});
