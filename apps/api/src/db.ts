import pg from "pg";
import { env } from "./env.js";

const { Pool } = pg;

export const db = new Pool({
  host: env.dbHost,
  port: env.dbPort,
  database: env.dbName,
  user: env.dbUser,
  password: env.dbPassword,
  max: 10,
});
