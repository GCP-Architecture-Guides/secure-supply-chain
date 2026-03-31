'use strict';

const express = require('express');

// Production should set DB_PASSWORD (e.g. Secret Manager on Cloud Run, K8s secret on GKE).
const dbPassword = process.env.DB_PASSWORD || 'not-set';

const app = express();
const port = process.env.PORT || 3000;

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    demo: 'good-app',
    dbConfigured: dbPassword !== 'not-set',
  });
});

app.listen(port, () => {
  console.log(`good-app listening on port ${port}`);
});
