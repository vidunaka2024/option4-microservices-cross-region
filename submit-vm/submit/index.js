// submit-vm/submit/index.js

const express = require('express');
const amqp = require('amqplib');
const fs = require('fs');
const path = require('path');
const swaggerJsdoc = require('swagger-jsdoc');
const swaggerUi = require('swagger-ui-express');

const app = express();
const port = process.env.PORT || 3200;

// Single RabbitMQ broker (on its own VM)
const RABBITMQ_URL = process.env.RABBITMQ_URL || 'amqp://10.0.0.7:5672';

const SUBMITTED_QUEUE = 'SUBMITTED_QUESTIONS';
const TYPE_UPDATE_EXCHANGE = 'type_update';
const TYPE_UPDATE_QUEUE = 'sub_type_update'; // Unique queue for this service's type_update subscription

app.use(express.json());
app.use(express.static('public'));

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

    // Assert the queue we publish to
    await channel.assertQueue(SUBMITTED_QUEUE, { durable: true });

    // Subscribe to type_update events (ECST via fanout exchange)
    await channel.assertExchange(TYPE_UPDATE_EXCHANGE, 'fanout', { durable: true });
    await channel.assertQueue(TYPE_UPDATE_QUEUE, { durable: true });
    await channel.bindQueue(TYPE_UPDATE_QUEUE, TYPE_UPDATE_EXCHANGE, '');

    console.log(`Submit service connected to RabbitMQ at ${RABBITMQ_URL}`);
    console.log(`Publishing to: ${SUBMITTED_QUEUE}`);
    console.log(`Subscribed to type_update events via: ${TYPE_UPDATE_QUEUE}`);

    // Consume type_update events to keep cache in sync
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
      title: 'Submit Service API',
      version: '1.0.0',
      description: 'API for submitting new jokes. Jokes are sent to a RabbitMQ queue for moderation.'
    },
    servers: [
      { url: 'https://mykong123gateway.westus.cloudapp.azure.com/submit' }
    ]
  },
  apis: [__filename],
};

const swaggerSpec = swaggerJsdoc(swaggerOptions);
app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec));

// ---------- Endpoints ----------

/**
 * @swagger
 * /types:
 *   get:
 *     summary: Get joke types
 *     description: Returns cached joke types from Docker volume. Kept in sync via type_update events.
 *     tags: [Types]
 *     responses:
 *       200:
 *         description: Array of type names
 */
app.get('/types', (req, res) => {
  res.json(typesCache);
});

/**
 * @swagger
 * /submit:
 *   post:
 *     summary: Submit a new joke
 *     description: >
 *       Submits a joke (setup, punchline, type) to the SUBMITTED_QUESTIONS queue
 *       for moderation. All fields are required.
 *     tags: [Submit]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               setup:
 *                 type: string
 *               punchline:
 *                 type: string
 *               type:
 *                 type: string
 *             required:
 *               - setup
 *               - punchline
 *               - type
 *     responses:
 *       200:
 *         description: Joke submitted successfully
 *       400:
 *         description: Missing required fields
 *       500:
 *         description: RabbitMQ not available
 */
app.post('/submit', async (req, res) => {
  const { setup, punchline, type } = req.body;

  if (!setup || !punchline || !type) {
    return res.status(400).json({
      error: "Missing required fields: setup, punchline, type"
    });
  }

  const message = {
    setup,
    punchline,
    type: type.toLowerCase(),
    timestamp: Date.now()
  };

  try {
    if (!channel) {
      return res.status(500).json({ error: "RabbitMQ channel not available. Please try again later." });
    }
    channel.sendToQueue(
      SUBMITTED_QUEUE,
      Buffer.from(JSON.stringify(message)),
      { persistent: true }
    );
    console.log('Joke submitted to queue:', message);
    res.json({ status: "Joke submitted successfully" });
  } catch (err) {
    console.error("Failed to publish message:", err);
    res.status(500).json({ error: err.message });
  }
});

/**
 * @swagger
 * /status:
 *   get:
 *     summary: Health check
 *     tags: [Health]
 *     responses:
 *       200:
 *         description: Service status
 */
app.get('/status', (req, res) => {
  res.json({
    status: 'Submit service running',
    rabbitmq: channel ? 'connected' : 'disconnected',
    cachedTypes: typesCache.length
  });
});

// ---------- Start ----------
connectRabbitMQ().then(() => {
  app.listen(port, '0.0.0.0', () => {
    console.log(`Submit service running on port ${port}`);
    console.log(`Swagger docs at http://localhost:${port}/docs`);
  });
});
