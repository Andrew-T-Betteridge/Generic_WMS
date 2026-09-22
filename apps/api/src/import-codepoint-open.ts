import "dotenv/config";

import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import path from "node:path";
import readline from "node:readline";
import type { PoolClient } from "pg";

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

type StageStats = {
  row_count: string;
  coordinate_row_count: string;
  first_postcode: string | null;
  last_postcode: string | null;
};

const BATCH_SIZE = 1000;
const SOURCE = "OS_CODE_POINT_OPEN";

const IMPORT_LOCK_NAMESPACE = "DYNETIC_WMS";
const IMPORT_LOCK_NAME = "GB_POSTCODE_IMPORT";

const MIN_EXPECTED_ROWS = Number(
  process.env.POSTCODE_IMPORT_MIN_ROWS ?? 1_500_000,
);

const MIN_COORDINATE_RATIO = Number(
  process.env.POSTCODE_IMPORT_MIN_COORDINATE_RATIO ?? 0.98,
);

const MAX_ROW_DROP_RATIO = Number(
  process.env.POSTCODE_IMPORT_MAX_ROW_DROP_RATIO ?? 0.05,
);

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

  if (!cleaned) {
    return null;
  }

  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
}

function postcodeRow(fields: string[]): PostcodeRow {
  if (fields.length < 10) {
    throw new Error(
      `Unexpected Code-Point row with ${fields.length} columns`,
    );
  }

  const postcodeCompact = fields[0]
    .toUpperCase()
    .replace(/\s+/gu, "");

  if (!/^[A-Z0-9]{5,7}$/u.test(postcodeCompact)) {
    throw new Error(
      `Invalid postcode in Code-Point data: ${fields[0]}`,
    );
  }

  const outwardCode = postcodeCompact.slice(0, -3);
  const postcode =
    `${outwardCode} ${postcodeCompact.slice(-3)}`;

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
    } else if (
      entry.isFile() &&
      entry.name.toLowerCase().endsWith(".csv")
    ) {
      files.push(full);
    }
  }

  return files.sort();
}

async function insertBatch(
  client: PoolClient,
  rows: PostcodeRow[],
  sourceDate: string | null,
) {
  if (!rows.length) {
    return;
  }

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
      SOURCE,
      sourceDate,
    );

    return `(${Array.from(
      { length: 14 },
      (_, i) => `$${offset + i + 1}`,
    ).join(",")})`;
  });

  await client.query(
    `
      insert into core.gb_postcode_directory_stage (
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
        positional_quality_indicator =
          excluded.positional_quality_indicator,
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

function validateConfiguration() {
  if (
    !Number.isFinite(MIN_EXPECTED_ROWS) ||
    MIN_EXPECTED_ROWS < 1
  ) {
    throw new Error(
      "POSTCODE_IMPORT_MIN_ROWS must be a positive number",
    );
  }

  if (
    !Number.isFinite(MIN_COORDINATE_RATIO) ||
    MIN_COORDINATE_RATIO <= 0 ||
    MIN_COORDINATE_RATIO > 1
  ) {
    throw new Error(
      "POSTCODE_IMPORT_MIN_COORDINATE_RATIO must be > 0 and <= 1",
    );
  }

  if (
    !Number.isFinite(MAX_ROW_DROP_RATIO) ||
    MAX_ROW_DROP_RATIO < 0 ||
    MAX_ROW_DROP_RATIO >= 1
  ) {
    throw new Error(
      "POSTCODE_IMPORT_MAX_ROW_DROP_RATIO must be >= 0 and < 1",
    );
  }
}

async function main() {
  validateConfiguration();

  const input = process.argv[2];
  const sourceDate = process.argv[3] ?? null;

  if (!input) {
    throw new Error(
      "Usage: npm run import:codepoint -- <Code-Point Data/CSV folder> [YYYY-MM-DD]",
    );
  }

  if (
    sourceDate &&
    !/^\d{4}-\d{2}-\d{2}$/u.test(sourceDate)
  ) {
    throw new Error("Source date must be YYYY-MM-DD");
  }

  const inputPath = path.resolve(input);
  const inputInfo = await stat(inputPath);
  const hashRoot = inputInfo.isDirectory()
    ? inputPath
    : path.dirname(inputPath);

  const files = await csvFiles(inputPath);

  if (!files.length) {
    throw new Error("No CSV files found");
  }

  console.log(
    `Found ${files.length} Code-Point CSV files`,
  );

  const client = await db.connect();

  let importId: string | null = null;
  let promoted = false;
  let advisoryLockHeld = false;

  try {
    const dbInfo = await client.query(
      "select current_database() as name",
    );

    const databaseName = String(
      dbInfo.rows[0]?.name ?? "",
    );

    const expectedDatabase = String(
      process.env.POSTCODE_IMPORT_EXPECT_DATABASE ?? "",
    ).trim();

    if (
      !expectedDatabase ||
      databaseName !== expectedDatabase
    ) {
      throw new Error(
        'Refusing postcode import: connected to "' +
          databaseName +
          '", expected "' +
          (expectedDatabase || "<not configured>") +
          '"',
      );
    }

    console.log(
      "Confirmed target database: " + databaseName,
    );

    const lockResult = await client.query<{
      locked: boolean;
    }>(
      `
        select pg_try_advisory_lock(
          hashtext($1),
          hashtext($2)
        ) as locked
      `,
      [IMPORT_LOCK_NAMESPACE, IMPORT_LOCK_NAME],
    );

    advisoryLockHeld =
      lockResult.rows[0]?.locked === true;

    if (!advisoryLockHeld) {
      throw new Error(
        "Another postcode import is already running",
      );
    }

    console.log("Postcode import lock acquired");

    const releaseResult = await client.query<{
      import_id: string;
    }>(
      `
        insert into config.postcode_dataset_release (
          source,
          source_date,
          database_name,
          file_count,
          status
        )
        values ($1,$2,$3,$4,'STAGING')
        returning import_id::text
      `,
      [
        SOURCE,
        sourceDate,
        databaseName,
        files.length,
      ],
    );

    importId =
      releaseResult.rows[0]?.import_id ?? null;

    if (!importId) {
      throw new Error(
        "Failed to create postcode import audit record",
      );
    }

    console.log("Import ID: " + importId);

    await client.query(
      "truncate table core.gb_postcode_directory_stage",
    );

    console.log(
      "Staging table cleared; loading new dataset",
    );

    let imported = 0;
    let batch: PostcodeRow[] = [];

    const datasetHash = createHash("sha256");

    for (const file of files) {
      const relativeFile = path
        .relative(hashRoot, file)
        .split(path.sep)
        .join("/");

      datasetHash.update(relativeFile);
      datasetHash.update("\0");

      const fileStream = createReadStream(file);

      fileStream.on("data", (chunk) => {
        datasetHash.update(chunk);
      });

      const stream = readline.createInterface({
        input: fileStream,
        crlfDelay: Infinity,
      });

      for await (const line of stream) {
        if (!line.trim()) {
          continue;
        }

        batch.push(
          postcodeRow(parseCsvLine(line)),
        );

        if (batch.length >= BATCH_SIZE) {
          await insertBatch(
            client,
            batch,
            sourceDate,
          );

          imported += batch.length;
          batch = [];

          if (imported % 100000 === 0) {
            console.log(
              `Staged ${imported.toLocaleString()} postcodes`,
            );
          }
        }
      }

      datasetHash.update("\0");
    }

    if (batch.length) {
      await insertBatch(
        client,
        batch,
        sourceDate,
      );

      imported += batch.length;
    }

    const checksum =
      datasetHash.digest("hex");

    console.log(
      `Finished staging ${imported.toLocaleString()} source rows`,
    );

    const stageStatsResult =
      await client.query<StageStats>(
        `
          select
            count(*)::text as row_count,
            count(*) filter (
              where easting is not null
                and northing is not null
            )::text as coordinate_row_count,
            min(postcode) as first_postcode,
            max(postcode) as last_postcode
          from core.gb_postcode_directory_stage
        `,
      );

    const stageStats = stageStatsResult.rows[0];

    const rowCount = Number(
      stageStats?.row_count ?? 0,
    );

    const coordinateRowCount = Number(
      stageStats?.coordinate_row_count ?? 0,
    );

    if (rowCount !== imported) {
      throw new Error(
        "Postcode validation failed: " +
          `${imported.toLocaleString()} source rows were read but ` +
          `${rowCount.toLocaleString()} unique rows exist in staging. ` +
          "The source dataset may contain duplicate postcodes.",
      );
    }

    if (rowCount < MIN_EXPECTED_ROWS) {
      throw new Error(
        "Postcode validation failed: staging contains only " +
          `${rowCount.toLocaleString()} rows; minimum is ` +
          `${MIN_EXPECTED_ROWS.toLocaleString()}`,
      );
    }

    const coordinateRatio =
      rowCount > 0
        ? coordinateRowCount / rowCount
        : 0;

    if (
      coordinateRatio < MIN_COORDINATE_RATIO
    ) {
      throw new Error(
        "Postcode validation failed: coordinate coverage is " +
          `${(coordinateRatio * 100).toFixed(2)}%; minimum is ` +
          `${(MIN_COORDINATE_RATIO * 100).toFixed(2)}%`,
      );
    }

    const liveCountResult = await client.query<{
      row_count: string;
    }>(
      `
        select count(*)::text as row_count
        from core.gb_postcode_directory
      `,
    );

    const liveRowCount = Number(
      liveCountResult.rows[0]?.row_count ?? 0,
    );

    if (
      liveRowCount >= MIN_EXPECTED_ROWS &&
      rowCount <
        liveRowCount *
          (1 - MAX_ROW_DROP_RATIO)
    ) {
      throw new Error(
        "Postcode validation failed: new dataset contains " +
          `${rowCount.toLocaleString()} rows versus ` +
          `${liveRowCount.toLocaleString()} currently live. ` +
          `A drop greater than ${(MAX_ROW_DROP_RATIO * 100).toFixed(1)}% ` +
          "is not permitted.",
      );
    }

    await client.query(
      `
        update config.postcode_dataset_release
           set source_checksum=$2,
               row_count=$3,
               coordinate_row_count=$4,
               first_postcode=$5,
               last_postcode=$6,
               status='VALIDATED',
               validated_at=now(),
               error_text=null
         where import_id=$1
      `,
      [
        importId,
        checksum,
        rowCount,
        coordinateRowCount,
        stageStats?.first_postcode ?? null,
        stageStats?.last_postcode ?? null,
      ],
    );

    console.log(
      "Validation passed: " +
        `${rowCount.toLocaleString()} postcodes, ` +
        `${coordinateRowCount.toLocaleString()} with coordinates ` +
        `(${(coordinateRatio * 100).toFixed(2)}%)`,
    );

    console.log(
      `Current live row count: ${liveRowCount.toLocaleString()}`,
    );

    console.log(
      "Promoting staged postcode dataset to live",
    );

    await client.query("begin");

    try {
      await client.query(
        "set local lock_timeout = '30s'",
      );

      await client.query(
        `
          lock table core.gb_postcode_directory
          in access exclusive mode
        `,
      );

      await client.query(
        "truncate table core.gb_postcode_directory",
      );

      await client.query(
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
            source_updated_at,
            imported_at
          )
          select
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
            source_updated_at,
            now()
          from core.gb_postcode_directory_stage
        `,
      );

      await client.query(
        `
          update config.postcode_dataset_release
             set status='PROMOTED',
                 promoted_at=now()
           where import_id=$1
        `,
        [importId],
      );

      await client.query("commit");
      promoted = true;
    } catch (error) {
      await client.query("rollback");
      throw error;
    }

    console.log(
      "Atomic postcode promotion committed",
    );

    await client.query(
      "analyze core.gb_postcode_directory",
    );

    await client.query(
      "truncate table core.gb_postcode_directory_stage",
    );

    await client.query(
      `
        update config.postcode_dataset_release
           set status='COMPLETED',
               completed_at=now(),
               error_text=null
         where import_id=$1
      `,
      [importId],
    );

    console.log(
      `Postcode refresh complete: ${rowCount.toLocaleString()} live postcodes`,
    );

    console.log(
      "Dataset SHA-256: " + checksum,
    );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    if (importId) {
      try {
        if (promoted) {
          await client.query(
            `
              update config.postcode_dataset_release
                 set status='PROMOTED',
                     error_text=left($2,10000)
               where import_id=$1
            `,
            [importId, message],
          );
        } else {
          await client.query(
            `
              update config.postcode_dataset_release
                 set status='FAILED',
                     completed_at=now(),
                     error_text=left($2,10000)
               where import_id=$1
            `,
            [importId, message],
          );
        }
      } catch (auditError) {
        console.error(
          "Unable to update postcode import audit record:",
          auditError,
        );
      }
    }

    throw error;
  } finally {
    if (advisoryLockHeld) {
      try {
        await client.query(
          `
            select pg_advisory_unlock(
              hashtext($1),
              hashtext($2)
            )
          `,
          [
            IMPORT_LOCK_NAMESPACE,
            IMPORT_LOCK_NAME,
          ],
        );
      } catch (unlockError) {
        console.error(
          "Unable to release postcode import lock:",
          unlockError,
        );
      }
    }

    client.release();
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