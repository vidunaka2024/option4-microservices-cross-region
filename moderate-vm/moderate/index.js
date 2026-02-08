// moderate-vm/moderate/index.js

const express = require('express');
const amqp = require('amqplib');
const fs = require('fs-extra');
const path = require('path');
const swaggerJsDoc = require('swagger-jsdoc');
const swaggerUi = require('swagger-ui-express');
const rateLimit = require('express-rate-limit');
const { auth, requiresAuth } = require('express-openid-connect');
require('dotenv').config();

const app = express();
const port = process.env.PORT || 3100;

// Auth0 configuration
const config = {
  authRequired: false,
  auth0Logout: true,
  baseURL: process.env.AUTH0_BASE_URL || `http://localhost:${port}`,
  clientID: process.env.AUTH0_CLIENT_ID,
  issuerBaseURL: process.env.AUTH0_ISSUER_BASE_URL,
  secret: process.env.AUTH0_SECRET,
  routes: {
    login: '/login',
    logout: '/logout',
    callback: '/callback'
  }
};

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many requests from this IP, please try again later.'
});

app.use(limiter);
app.use(auth(config));

app.use(express.json());
app.use(express.static('public'));

// Single RabbitMQ broker (on its own VM)
const RABBITMQ_URL = process.env.RABBITMQ_URL || 'amqp://10.0.0.7:5672';

const SUBMITTED_QUEUE = 'SUBMITTED_QUESTIONS';
const MODERATED_QUEUE = 'MODERATED_QUESTIONS';
const TYPE_UPDATE_EXCHANGE = 'type_update';
const TYPE_UPDATE_QUEUE = 'mod_type_update'; // Unique queue for this service's type_update subscription

// Types cache file in Docker volume
const typesFilePath = path.join('/data', 'types.json');

function loadTypesCache() {
  if (fs.existsSync(typesFilePath)) {
    try {
      return JSON.parse(fs.readFileSync(typesFilePath, 'utf8'));
    } catch (err) {
      console.error('Error reading types cache:', err);
      return [];
    }
  }
  const defaults = ['general', 'programming', 'dad'];
  saveTypesCache(defaults);
  return defaults;
}

function saveTypesCache(types) {
  try {
    fs.writeFileSync(typesFilePath, JSON.stringify(types, null, 2));
  } catch (err) {
    console.error('Error writing types cache:', err);
  }
}

let typesCache = loadTypesCache();
let channel = null;

// ---------- RabbitMQ Connection ----------
async function connectRabbitMQ() {
  try {
    const conn = await amqp.connect(RABBITMQ_URL);
    channel = await conn.createChannel();

    // Assert queues
    await channel.assertQueue(SUBMITTED_QUEUE, { durable: true });
    await channel.assertQueue(MODERATED_QUEUE, { durable: true });

    // Subscribe to type_update events (ECST via fanout exchange)
    await channel.assertExchange(TYPE_UPDATE_EXCHANGE, 'fanout', { durable: true });
    await channel.assertQueue(TYPE_UPDATE_QUEUE, { durable: true });
    await channel.bindQueue(TYPE_UPDATE_QUEUE, TYPE_UPDATE_EXCHANGE, '');

    console.log(`Moderate service connected to RabbitMQ at ${RABBITMQ_URL}`);
    console.log(`Consuming submitted jokes from: ${SUBMITTED_QUEUE}`);
    console.log(`Publishing moderated jokes to: ${MODERATED_QUEUE}`);
    console.log(`Subscribed to type_update events via: ${TYPE_UPDATE_QUEUE}`);

    // Consume type_update events to keep local cache in sync
    channel.consume(TYPE_UPDATE_QUEUE, (msg) => {
      if (msg !== null) {
        try {
          const event = JSON.parse(msg.content.toString());
          console.log('Received type_update event:', event);
          if (event.types && Array.isArray(event.types)) {
            typesCache = event.types;
            saveTypesCache(typesCache);
            console.log('Types cache updated:', typesCache);
          }
          channel.ack(msg);
        } catch (err) {
          console.error('Error processing type_update:', err);
          channel.ack(msg);
        }
      }
    }, { noAck: false });

    conn.on('error', err => {
      console.error('RabbitMQ connection error:', err);
      channel = null;
    });
    conn.on('close', () => {
      console.error('RabbitMQ connection closed. Reconnecting in 5s...');
      channel = null;
      setTimeout(connectRabbitMQ, 5000);
    });

  } catch (err) {
    console.error('Failed to connect to RabbitMQ:', err.message);
    channel = null;
    setTimeout(connectRabbitMQ, 5000);
  }
}

// ---------- Swagger ----------
const swaggerOptions = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Moderation Service API',
      version: '1.0.0',
      description: 'API for moderating submitted jokes with Auth0 authentication and ECST pattern'
    },
    servers: [
      { url: 'https://mykong123gateway.westus.cloudapp.azure.com/moderate' },
      { url: `http://localhost:${port}`, description: 'Development server' }
    ],
    components: {
      securitySchemes: {
        Auth0: {
          type: 'openIdConnect',
          openIdConnectUrl: `${process.env.AUTH0_ISSUER_BASE_URL}/.well-known/openid_configuration`,
          description: 'Auth0 OpenID Connect authentication'
        }
      }
    }
  },
  apis: [__filename]
};

const swaggerSpec = swaggerJsDoc(swaggerOptions);
app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec));

// ---------- Endpoints ----------

// Protected dashboard route
app.get('/', requiresAuth(), (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// User profile endpoint
app.get('/profile', requiresAuth(), (req, res) => {
  res.json({
    user: req.oidc.user,
    isAuthenticated: req.oidc.isAuthenticated()
  });
});

/**
 * @swagger
 * /types:
 *   get:
 *     summary: Get joke types from cache
 *     description: Returns cached joke types from Docker volume. Kept in sync via type_update events.
 *     security:
 *       - Auth0: []
 *     tags: [Types]
 *     responses:
 *       200:
 *         description: Array of type names
 *       401:
 *         description: Authentication required
 */
app.get('/types', requiresAuth(), (req, res) => {
  res.json(typesCache);
});

/**
 * @swagger
 * /moderate:
 *   get:
 *     summary: Fetch next submitted joke for moderation
 *     description: >
 *       Gets one joke from the SUBMITTED_QUESTIONS queue. If none available,
 *       returns a message. The UI should poll this endpoint at 1-second intervals.
 *     security:
 *       - Auth0: []
 *     tags: [Moderation]
 *     responses:
 *       200:
 *         description: A joke to moderate or no-messages indication
 *       401:
 *         description: Authentication required
 *       503:
 *         description: Queue not available
 */
app.get('/moderate', requiresAuth(), async (req, res) => {
  try {
    if (!channel) {
      return res.status(503).json({ error: "RabbitMQ channel not available" });
    }

    const msg = await channel.get(SUBMITTED_QUEUE, { noAck: false });
    if (msg) {
      const content = JSON.parse(msg.content.toString());
      channel.ack(msg);
      console.log('Fetched joke for moderation:', content);
      res.json(content);
    } else {
      res.json({ message: "No jokes available for moderation" });
    }
  } catch (err) {
    console.error("Error fetching joke for moderation:", err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * @swagger
 * /moderated:
 *   post:
 *     summary: Submit moderated joke
 *     description: >
 *       If approved, publishes the joke to MODERATED_QUESTIONS queue for ETL processing.
 *       If not approved, the joke is rejected (discarded).
 *     security:
 *       - Auth0: []
 *     tags: [Moderation]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               approved:
 *                 type: boolean
 *               setup:
 *                 type: string
 *               punchline:
 *                 type: string
 *               type:
 *                 type: string
 *             required:
 *               - approved
 *               - setup
 *               - punchline
 *               - type
 *     responses:
 *       200:
 *         description: Joke processed (accepted or rejected)
 *       400:
 *         description: Missing fields
 *       401:
 *         description: Authentication required
 *       403:
 *         description: Insufficient permissions
 *       503:
 *         description: RabbitMQ not available
 */
app.post('/moderated', requiresAuth(), async (req, res) => {
  const { approved, setup, punchline, type } = req.body;

  // If not approved, reject and return
  if (approved !== true) {
    return res.json({ status: "rejected", message: "Joke rejected by moderator" });
  }

  // Validate required fields
  if (!setup || !punchline || !type) {
    return res.status(400).json({
      error: "Missing required fields: setup, punchline, type"
    });
  }

  try {
    if (!channel) {
      return res.status(503).json({ error: "RabbitMQ channel not available" });
    }

    const moderatedMessage = {
      setup,
      punchline,
      type: type.toLowerCase(),
      timestamp: Date.now()
    };

    channel.sendToQueue(
      MODERATED_QUEUE,
      Buffer.from(JSON.stringify(moderatedMessage)),
      { persistent: true }
    );

    console.log('Moderated joke sent to queue:', moderatedMessage);
    res.json({ status: "accepted", message: "Moderated joke forwarded to ETL" });
  } catch (err) {
    console.error("Failed to publish moderated message:", err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * @swagger
 * /health:
 *   get:
 *     summary: Health check endpoint
 *     description: Public health check endpoint for service monitoring
 *     tags: [Health]
 *     responses:
 *       200:
 *         description: Service is healthy
 */
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    service: 'moderate-service',
    rabbitmq: channel ? 'connected' : 'disconnected',
    cachedTypes: typesCache.length,
    authenticated: !!req.oidc.user
  });
});

/**
 * @swagger
 * /status:
 *   get:
 *     summary: Detailed service status
 *     security:
 *       - Auth0: []
 *     tags: [Health]
 *     responses:
 *       200:
 *         description: Detailed service status
 *       401:
 *         description: Authentication required
 */
app.get('/status', requiresAuth(), (req, res) => {
  res.json({
    status: 'Moderate service running',
    rabbitmq: channel ? 'connected' : 'disconnected',
    cachedTypes: typesCache.length,
    user: req.oidc.user.name || req.oidc.user.email,
    queues: {
      submit: SUBMITTED_QUEUE,
      moderated: MODERATED_QUEUE,
      typeUpdate: TYPE_UPDATE_QUEUE
    },
    environment: {
      port,
      auth0_domain: process.env.AUTH0_ISSUER_BASE_URL,
      rabbitmq_url: RABBITMQ_URL
    }
  });
});

// ---------- Start ----------
connectRabbitMQ().then(() => {
  app.listen(port, '0.0.0.0', () => {
    console.log(`Moderation service running on port ${port}`);
    console.log(`Swagger docs at http://localhost:${port}/docs`);
  });
});
