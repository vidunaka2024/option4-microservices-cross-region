// joke-vm/joke/index.js

const express = require('express');
const rateLimit = require('express-rate-limit');
const swaggerJsdoc = require('swagger-jsdoc');
const swaggerUi = require('swagger-ui-express');

const app = express();
const port = process.env.PORT || 3000;

// Choose DB type via environment variable: 'mongo' or 'mysql'
const DB_TYPE = process.env.DB_TYPE || 'mongo';

app.use(express.json());

// Rate limiting: 100 requests per 2 minutes
const limiter = rateLimit({
  windowMs: 2 * 60 * 1000,
  max: 100,
  message: 'Too many requests from this IP, please try again after 2 minutes.'
});
app.use(limiter);

// Serve static files from "public" folder
app.use(express.static('public'));

let db;

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

    const Joke = mongoose.model('Joke', JokeSchema);
    const Type = mongoose.model('Type', TypeSchema);
    db = { Joke, Type };

    // Insert default data if empty
    const jokeCount = await Joke.countDocuments();
    if (jokeCount === 0) {
      console.log("No jokes found. Inserting sample data.");
      const defaultTypes = ['general', 'programming', 'dad'];
      for (const t of defaultTypes) {
        await Type.findOneAndUpdate({ name: t }, { name: t }, { upsert: true });
      }
      await Joke.insertMany([
        { type: 'general', setup: 'Why did the scarecrow win an award?', punchline: 'Because he was outstanding in his field!' },
        { type: 'general', setup: "Why don't scientists trust atoms?", punchline: 'Because they make up everything!' },
        { type: 'programming', setup: 'Why do programmers prefer dark mode?', punchline: 'Because light attracts bugs!' },
        { type: 'programming', setup: "What is a programmer's favourite hangout place?", punchline: 'Foo Bar!' },
        { type: 'dad', setup: "I'm reading a book about anti-gravity.", punchline: "It's impossible to put down!" },
        { type: 'dad', setup: "Did you hear about the mathematician who's afraid of negative numbers?", punchline: "He'll stop at nothing to avoid them!" }
      ]);
    }
    console.log(`Connected to MongoDB`);

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

    // Create types table (no duplicate types allowed)
    await pool.query(`
      CREATE TABLE IF NOT EXISTS types (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) UNIQUE NOT NULL
      );
    `);

    // Create jokes table with foreign key to types
    await pool.query(`
      CREATE TABLE IF NOT EXISTS jokes (
        id INT AUTO_INCREMENT PRIMARY KEY,
        type_id INT NOT NULL,
        setup TEXT NOT NULL,
        punchline TEXT NOT NULL,
        FOREIGN KEY (type_id) REFERENCES types(id)
      );
    `);
    console.log('MySQL tables ensured.');

    // Insert default data if empty
    const [rows] = await pool.query('SELECT COUNT(*) as count FROM jokes');
    if (rows[0].count === 0) {
      console.log("No jokes found in MySQL. Inserting sample data.");
      const defaultTypes = ['general', 'programming', 'dad'];
      for (const t of defaultTypes) {
        await pool.query('INSERT IGNORE INTO types (name) VALUES (?)', [t]);
      }
      const jokes = [
        ['general', 'Why did the scarecrow win an award?', 'Because he was outstanding in his field!'],
        ['general', "Why don't scientists trust atoms?", 'Because they make up everything!'],
        ['programming', 'Why do programmers prefer dark mode?', 'Because light attracts bugs!'],
        ['programming', "What is a programmer's favourite hangout place?", 'Foo Bar!'],
        ['dad', "I'm reading a book about anti-gravity.", "It's impossible to put down!"],
        ['dad', "Did you hear about the mathematician who's afraid of negative numbers?", "He'll stop at nothing to avoid them!"]
      ];
      for (const [typeName, setup, punchline] of jokes) {
        const [typeRows] = await pool.query('SELECT id FROM types WHERE name = ?', [typeName]);
        await pool.query('INSERT INTO jokes (type_id, setup, punchline) VALUES (?, ?, ?)', [typeRows[0].id, setup, punchline]);
      }
    }
    console.log('Connected to MySQL');
  }
}

// ---------- Helper: shuffle array ----------
function shuffle(array) {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}

// ---------- Swagger ----------
const swaggerOptions = {
  definition: {
    openapi: '3.0.0',
    info: {
      title: 'Joke Service API',
      version: '1.0.0',
      description: 'API to retrieve random jokes. Supports MongoDB and MySQL backends, switchable via DB_TYPE env var.'
    },
    servers: [
      { url: 'https://mykong123gateway.westus.cloudapp.azure.com' }
    ]
  },
  apis: [__filename]
};

const swaggerSpec = swaggerJsdoc(swaggerOptions);
app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerSpec));

// ---------- Endpoints ----------

/**
 * @swagger
 * /status:
 *   get:
 *     summary: Health check
 *     tags: [Health]
 *     responses:
 *       200:
 *         description: Service is running
 */
app.get('/status', (req, res) => {
  res.json({ status: 'Joke service running', dbType: DB_TYPE });
});

/**
 * @swagger
 * /joke/{type}:
 *   get:
 *     summary: Get random joke(s) by type
 *     description: >
 *       Returns random jokes for the given type. Use "any" for all types.
 *       If count is not provided, returns 1 joke. If fewer jokes exist
 *       than requested, returns what is available.
 *     tags: [Jokes]
 *     parameters:
 *       - in: path
 *         name: type
 *         required: true
 *         schema:
 *           type: string
 *         description: Joke type (e.g. general, dad, programming) or "any"
 *       - in: query
 *         name: count
 *         required: false
 *         schema:
 *           type: integer
 *           default: 1
 *         description: Number of jokes to return
 *     responses:
 *       200:
 *         description: Array of joke objects
 *       500:
 *         description: Server error
 */
app.get('/joke/:type', async (req, res) => {
  const jokeType = req.params.type.toLowerCase();
  const count = parseInt(req.query.count) || 1;

  try {
    if (DB_TYPE === 'mongo') {
      let matchStage = {};
      if (jokeType !== 'any') {
        matchStage = { type: jokeType };
      }
      const jokes = await db.Joke.aggregate([
        { $match: matchStage },
        { $sample: { size: count } },
        { $project: { _id: 0, type: 1, setup: 1, punchline: 1 } }
      ]);
      res.json(jokes);

    } else if (DB_TYPE === 'mysql') {
      let query, params;
      if (jokeType === 'any') {
        query = 'SELECT j.setup, j.punchline, t.name as type FROM jokes j JOIN types t ON j.type_id = t.id ORDER BY RAND() LIMIT ?';
        params = [count];
      } else {
        query = 'SELECT j.setup, j.punchline, t.name as type FROM jokes j JOIN types t ON j.type_id = t.id WHERE t.name = ? ORDER BY RAND() LIMIT ?';
        params = [jokeType, count];
      }
      const [rows] = await db.pool.query(query, params);
      res.json(rows);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * @swagger
 * /types:
 *   get:
 *     summary: Get all joke types
 *     description: Returns distinct joke types from the database
 *     tags: [Types]
 *     responses:
 *       200:
 *         description: Array of type name strings
 *       500:
 *         description: Server error
 */
app.get('/types', async (req, res) => {
  try {
    if (DB_TYPE === 'mongo') {
      const types = await db.Type.distinct('name');
      res.json(types);
    } else if (DB_TYPE === 'mysql') {
      const [rows] = await db.pool.query('SELECT DISTINCT name FROM types ORDER BY name');
      res.json(rows.map(row => row.name));
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Start ----------
initDB()
  .then(() => {
    app.listen(port, '0.0.0.0', () => {
      console.log(`Joke service running on port ${port} with DB_TYPE=${DB_TYPE}`);
      console.log(`Swagger docs at http://localhost:${port}/docs`);
    });
  })
  .catch(err => {
    console.error('Failed to initialize database:', err);
  });
