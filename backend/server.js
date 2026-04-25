const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

// ── PostgreSQL connection pool ──────────────────────────────────
// These env vars come from Kubernetes Secret + ConfigMap
const pool = new Pool({
  host:     process.env.DB_HOST     || 'postgres-service',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'storedb',
  user:     process.env.DB_USER     || 'storeuser',
  password: process.env.DB_PASSWORD || 'changeme',
});

// ── DB init: create products table if not exists ────────────────
async function initDB() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS products (
        id        SERIAL PRIMARY KEY,
        name      VARCHAR(100) NOT NULL,
        price     NUMERIC(10,2) NOT NULL,
        stock     INT DEFAULT 0,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `);

    // Seed some data if table is empty
    const { rowCount } = await client.query('SELECT 1 FROM products LIMIT 1');
    if (rowCount === 0) {
      await client.query(`
        INSERT INTO products (name, price, stock) VALUES
          ('Laptop Pro 15',   89999.00, 25),
          ('Mechanical Keyboard', 4999.00, 100),
          ('USB-C Hub 7-in-1', 2499.00, 200),
          ('4K Monitor 27"',  34999.00, 15),
          ('Wireless Mouse',   1299.00, 150);
      `);
      console.log('✅ Database seeded with sample products');
    }
  } finally {
    client.release();
  }
}

// ── Routes ──────────────────────────────────────────────────────

// Health check — Kubernetes liveness/readiness probe hits this
app.get('/health', (req, res) => {
  res.json({ status: 'ok', tier: 'app', timestamp: new Date().toISOString() });
});

// Get all products
app.get('/api/products', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM products ORDER BY created_at DESC'
    );
    res.json({ success: true, products: result.rows });
  } catch (err) {
    console.error('DB error:', err.message);
    res.status(500).json({ success: false, error: err.message });
  }
});

// Get single product
app.get('/api/products/:id', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM products WHERE id = $1',
      [req.params.id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ success: false, error: 'Product not found' });
    }
    res.json({ success: true, product: result.rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Create product
app.post('/api/products', async (req, res) => {
  const { name, price, stock } = req.body;
  if (!name || price == null) {
    return res.status(400).json({ success: false, error: 'name and price are required' });
  }
  try {
    const result = await pool.query(
      'INSERT INTO products (name, price, stock) VALUES ($1, $2, $3) RETURNING *',
      [name, price, stock || 0]
    );
    res.status(201).json({ success: true, product: result.rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// Delete product
app.delete('/api/products/:id', async (req, res) => {
  try {
    await pool.query('DELETE FROM products WHERE id = $1', [req.params.id]);
    res.json({ success: true, message: 'Product deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// ── Start server ────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;

initDB()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`🚀 App tier running on port ${PORT}`);
      console.log(`   DB host: ${process.env.DB_HOST || 'postgres-service'}`);
    });
  })
  .catch(err => {
    console.error('❌ Failed to initialize DB:', err.message);
    process.exit(1);
  });
