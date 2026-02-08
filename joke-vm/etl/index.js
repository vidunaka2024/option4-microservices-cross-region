// joke-vm/etl/index.js

const express = require('express');
const amqp = require('amqplib');

const app = express();
const port = process.env.PORT || 3001;

const DB_TYPE = process.env.DB_TYPE || 'mongo';
const RABBITMQ_URL = process.env.RABBITMQ_URL || 'amqp://10.0.0.7:5672';

const MODERATED_QUEUE = 'MODERATED_QUESTIONS';
const TYPE_UPDATE_EXCHANGE = 'type_update'; // Fanout exchange for ECST

let db;
let channel = null;

// ---------- Database Initialization ----------
async function initDB() {
  if (DB_TYPE === 'mongo') {
    const mongoose = require('mongoose');
    const MONGO_URI = process.env.MONGO_URI || 'mongodb://mongo:27017/jokes';
    await mongoose.connect(MONGO_URI, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
    });

    const JokeSchema = new mongoose.Schema({
      type: String,
      setup: String,
      punchline: String
    });
    const TypeSchema = new mongoose.Schema({
      name: { type: String, unique: true }
    });

    db = {
      Joke: mongoose.model('Joke', JokeSchema),
      Type: mongoose.model('Type', TypeSchema)
    };
    console.log('ETL connected to MongoDB');

  } else if (DB_TYPE === 'mysql') {
    const mysql = require('mysql2/promise');
    const pool = await mysql.createPool({
      host: process.env.MYSQL_HOST || 'mysql',
      user: process.env.MYSQL_USER || 'root',
      password: process.env.MYSQL_PASSWORD || 'password',
      database: process.env.MYSQL_DATABASE || 'jokes',
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0
    });
    db = { pool };

    // Ensure tables exist
    await pool.query(`
      CREATE TABLE IF NOT EXISTS types (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL
      );
    `);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS jokes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        type_id INT NOT NULL,
        setup TEXT NOT NULL,
        punchline TEXT NOT NULL,
        FOREIGN KEY (type_id) REFERENCES types(id)
      );
    `);
    console.log('ETL connected to MySQL');
  }
}

// ---------- Insert joke + type into DB ----------
// Returns true if a NEW type was created
async function insertJoke(data) {
  const { type, setup, punchline } = data;
  let newTypeCreated = false;

  if (DB_TYPE === 'mongo') {
    const existing = await db.Type.findOne({ name: type.toLowerCase() });
    if (!existing) {
      await db.Type.create({ name: type.toLowerCase() });
      newTypeCreated = true;
    }
    await db.Joke.create({ type: type.toLowerCase(), setup, punchline });

  } else if (DB_TYPE === 'mysql') {
    const [result] = await db.pool.query('INSERT IGNORE INTO types (name) VALUES (?)', [type.toLowerCase()]);
    if (result.affectedRows > 0) {
      newTypeCreated = true;
    }
    const [typeRows] = await db.pool.query('SELECT id FROM types WHERE name = ?', [type.toLowerCase()]);
    await db.pool.query('INSERT INTO jokes (type_id, setup, punchline) VALUES (?, ?, ?)',
      [typeRows[0].id, setup, punchline]);
  }

  return newTypeCreated;
}

// ---------- Get all types from DB (for event payload) ----------
async function getAllTypes() {
  if (DB_TYPE === 'mongo') {
    return await db.Type.distinct('name');
  } else if (DB_TYPE === 'mysql') {
    const [rows] = await db.pool.query('SELECT DISTINCT name FROM types ORDER BY name');
    return rows.map(r => r.name);
  }
}

// ---------- RabbitMQ: consume moderated queue, publish type_update events ----------
async function startETL() {
  try {
    const conn = await amqp.connect(RABBITMQ_URL);
    channel = await conn.createChannel();

    // Assert the queue we consume from
    await channel.assertQueue(MODERATED_QUEUE, { durable: true });

    // Assert a fanout exchange for type_update events (ECST pattern)
    await channel.assertExchange(TYPE_UPDATE_EXCHANGE, 'fanout', { durable: true });

    console.log(`ETL listening on queue: ${MODERATED_QUEUE}`);
    console.log(`ETL publishing type_update events to exchange: ${TYPE_UPDATE_EXCHANGE}`);

    channel.consume(MODERATED_QUEUE, async (msg) => {
      if (msg !== null) {
        try {
          const data = JSON.parse(msg.content.toString());
          console.log('ETL received moderated joke:', data);

          const jokeData = {
            type: data.type,
            setup: data.setup,
            punchline: data.punchline
          };

          const newTypeCreated = await insertJoke(jokeData);
          channel.ack(msg);
          console.log('Joke inserted into database.');

          // If a new type was created, publish a type_update event to all subscribers
          if (newTypeCreated) {
            const allTypes = await getAllTypes();
            const event = { types: allTypes, timestamp: Date.now() };
            channel.publish(TYPE_UPDATE_EXCHANGE, '', Buffer.from(JSON.stringify(event)));
            console.log('Published type_update event:', event);
          }
        } catch (err) {
          console.error('Failed to process moderated joke:', err);
          channel.nack(msg, false, true);
        }
      }
    }, { noAck: false });

    conn.on('error', err => console.error('RabbitMQ connection error:', err));
    conn.on('close', () => {
      console.error('RabbitMQ connection closed. Reconnecting in 5s...');
      channel = null;
      setTimeout(startETL, 5000);
    });

  } catch (err) {
    console.error('Failed to connect to RabbitMQ:', err.message);
    console.log('Retrying in 5 seconds...');
    setTimeout(startETL, 5000);
  }
}

// ---------- Health endpoint ----------
/**
 * Simple alive check endpoint
 */
app.get('/status', (req, res) => {
  res.json({
    status: 'ETL service running',
    dbType: DB_TYPE,
    rabbitmq: channel ? 'connected' : 'disconnected'
  });
});

// ---------- Start ----------
initDB().then(() => {
  app.listen(port, '0.0.0.0', () => {
    console.log(`ETL service running on port ${port} with DB_TYPE=${DB_TYPE}`);
  });
  startETL();
}).catch(err => {
  console.error('Failed to initialize ETL DB:', err);
});
