import "dotenv/config";

import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import readline from "node:readline";

import { db } from "./db.js";

type PostcodeRow = {
  postcode: string;
  postcodeCompact: string;
  outwardCode: string;
  positionalQualityIndicator: number | null;
  easting: number | null;
  northing: number | null;
  countryCode: string | null;
  nhsRegionalHaCode: string | null;
  nhsHaCode: string | null;
  adminCountyCode: string | null;
  adminDistrictCode: string | null;
  adminWardCode: string | null;
};

const BATCH_SIZE = 1000;

function parseCsvLine(line: string): string[] {
  const result: string[] = [];
  let value = "";
  let quoted = false;

  for (let i = 0; i < line.length; i += 1) {
    const char = line[i];

    if (char === '"') {
      if (quoted && line[i + 1] === '"') {
        value += '"';
        i += 1;
      } else {
        quoted = !quoted;
      }
    } else if (char === "," && !quoted) {
      result.push(value);
      value = "";
    } else {
      value += char;
    }
  }

  result.push(value);
  return result;
}

function nullableText(value: string): string | null {
  const cleaned = value.trim();
  return cleaned.length ? cleaned : null;
}

function nullableNumber(value: string): number | null {
  const cleaned = value.trim();
  if (!cleaned) return null;

  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}

function postcodeRow(fields: string[]): PostcodeRow {
  if (fields.length < 10) {
    throw new Error(`Unexpected Code-Point row with ${fields.length} columns`);
  }

  const postcodeCompact = fields[0].toUpperCase().replace(/\s+/gu, "");

  if (!/^[A-Z0-9]{5,7}$/u.test(postcodeCompact)) {
    throw new Error(`Invalid postcode in Code-Point data: ${fields[0]}`);
  }

  const outwardCode = postcodeCompact.slice(0, -3);
  const postcode = `${outwardCode} ${postcodeCompact.slice(-3)}`;

  return {
    postcode,
    postcodeCompact,
    outwardCode,
    positionalQualityIndicator: nullableNumber(fields[1]),
    easting: nullableNumber(fields[2]),
    northing: nullableNumber(fields[3]),
    countryCode: nullableText(fields[4]),
    nhsRegionalHaCode: nullableText(fields[5]),
    nhsHaCode: nullableText(fields[6]),
    adminCountyCode: nullableText(fields[7]),
    adminDistrictCode: nullableText(fields[8]),
    adminWardCode: nullableText(fields[9]),
  };
}

async function csvFiles(root: string): Promise<string[]> {
  const info = await stat(root);

  if (info.isFile()) {
    return root.toLowerCase().endsWith(".csv") ? [root] : [];
  }

  const files: string[] = [];

  for (const entry of await readdir(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);

    if (entry.isDirectory()) {
      files.push(...(await csvFiles(full)));
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".csv")) {
      files.push(full);
    }
  }

  return files.sort();
}

async function insertBatch(rows: PostcodeRow[], sourceDate: string | null) {
  if (!rows.length) return;

  const values: unknown[] = [];
  const placeholders = rows.map((row, index) => {
    const offset = index * 14;

    values.push(
      row.postcode,
      row.postcodeCompact,
      row.outwardCode,
      row.positionalQualityIndicator,
      row.easting,
      row.northing,
      row.countryCode,
      row.nhsRegionalHaCode,
      row.nhsHaCode,
      row.adminCountyCode,
      row.adminDistrictCode,
      row.adminWardCode,
      "OS_CODE_POINT_OPEN",
      sourceDate,
    );

    return `(${Array.from({ length: 14 }, (_, i) => `$${offset + i + 1}`).join(",")})`;
  });

  await db.query(
    `
      insert into core.gb_postcode_directory (
        postcode,
        postcode_compact,
        outward_code,
        positional_quality_indicator,
        easting,
        northing,
        country_code,
        nhs_regional_ha_code,
        nhs_ha_code,
        admin_county_code,
        admin_district_code,
        admin_ward_code,
        source,
        source_updated_at
      )
      values ${placeholders.join(",")}
      on conflict (postcode) do update set
        postcode_compact = excluded.postcode_compact,
        outward_code = excluded.outward_code,
        positional_quality_indicator = excluded.positional_quality_indicator,
        easting = excluded.easting,
        northing = excluded.northing,
        country_code = excluded.country_code,
        nhs_regional_ha_code = excluded.nhs_regional_ha_code,
        nhs_ha_code = excluded.nhs_ha_code,
        admin_county_code = excluded.admin_county_code,
        admin_district_code = excluded.admin_district_code,
        admin_ward_code = excluded.admin_ward_code,
        source = excluded.source,
        source_updated_at = excluded.source_updated_at,
        imported_at = now()
    `,
    values,
  );
}

async function main() {
  const input = process.argv[2];
  const sourceDate = process.argv[3] ?? null;

  if (!input) {
    throw new Error(
      "Usage: npm run import:codepoint -- <Code-Point Data/CSV folder> [YYYY-MM-DD]",
    );
  }

  if (sourceDate && !/^\d{4}-\d{2}-\d{2}$/u.test(sourceDate)) {
    throw new Error("Source date must be YYYY-MM-DD");
  }

  const files = await csvFiles(path.resolve(input));

  if (!files.length) {
    throw new Error("No CSV files found");
  }

  console.log(`Found ${files.length} Code-Point CSV files`);

  const dbInfo = await db.query("select current_database() as name");
  const databaseName = String(dbInfo.rows[0]?.name ?? "");
  const expectedDatabase = String(process.env.POSTCODE_IMPORT_EXPECT_DATABASE ?? "").trim();

  if (!expectedDatabase || databaseName !== expectedDatabase) {
    throw new Error(
      'Refusing postcode import: connected to "' +
        databaseName +
        '", expected "' +
        (expectedDatabase || "<not configured>") +
        '"',
    );
  }

  console.log("Confirmed target database: " + databaseName);

  let imported = 0;
  let batch: PostcodeRow[] = [];

  await db.query("begin");

  try {
    await db.query("truncate table core.gb_postcode_directory");

    for (const file of files) {
      const stream = readline.createInterface({
        input: createReadStream(file),
        crlfDelay: Infinity,
      });

      for await (const line of stream) {
        if (!line.trim()) continue;

        batch.push(postcodeRow(parseCsvLine(line)));

        if (batch.length >= BATCH_SIZE) {
          await insertBatch(batch, sourceDate);
          imported += batch.length;
          batch = [];

          if (imported % 100000 === 0) {
            console.log(`Imported ${imported.toLocaleString()} postcodes`);
          }
        }
      }
    }

    if (batch.length) {
      await insertBatch(batch, sourceDate);
      imported += batch.length;
    }

    await db.query("commit");
    console.log(`Import complete: ${imported.toLocaleString()} postcodes`);
  } catch (error) {
    await db.query("rollback");
    throw error;
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await db.end();
  });
