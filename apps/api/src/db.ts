import pg from "pg";
import "dotenv/config";

const { Pool } = pg;

export const db = new Pool({
  host: process.env.DB_HOST ?? "localhost",
  port: Number(process.env.DB_PORT ?? 5432),
  database: process.env.DB_NAME ?? "fulfilment_dev",
  user: process.env.DB_USER ?? "postgres",
  password: process.env.DB_PASSWORD,
  max: 10,
});
