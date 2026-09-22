import { db } from "./db.js";

export interface AddressSearchItem {
  id: string;
  label: string;
}

export interface ResolvedAddress {
  name?: string | null;
  address1?: string | null;
  address2?: string | null;
  town?: string | null;
  county?: string | null;
  postcode?: string | null;
  country?: string | null;
}

export class AddressLookupError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, status = 503) {
    super(code);
    this.name = "AddressLookupError";
    this.code = code;
    this.status = status;
  }
}

type IdealPostcodesEnvelope<T> = {
  result?: T;
  code?: number;
  message?: string;
};

type IdealAddressHit = {
  id?: string;
  suggestion?: string;
};

type IdealAddress = {
  id?: string;
  country_iso?: string;
  country_iso_2?: string;
  country?: string;
  line_1?: string;
  line_2?: string;
  line_3?: string;
  post_town?: string;
  county?: string;
  postcode?: string;
};

const IDEAL_POSTCODES_BASE_URL = "https://api.ideal-postcodes.co.uk/v1";
const SEARCH_LIMIT = 8;
const DEFAULT_TIMEOUT_MS = 4000;

function configuredProvider() {
  return String(process.env.ADDRESS_LOOKUP_PROVIDER ?? "IDEAL_POSTCODES")
    .trim()
    .toUpperCase();
}

function apiKey() {
  if (configuredProvider() !== "IDEAL_POSTCODES") {
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }

  const key = String(process.env.ADDRESS_LOOKUP_API_KEY ?? "").trim();

  if (!key || /[\r\n"]/u.test(key)) {
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }

  return key;
}

function timeoutMs() {
  const parsed = Number(process.env.ADDRESS_LOOKUP_TIMEOUT_MS ?? DEFAULT_TIMEOUT_MS);

  if (!Number.isFinite(parsed)) return DEFAULT_TIMEOUT_MS;
  return Math.min(Math.max(Math.trunc(parsed), 500), 10000);
}

function normaliseCountry(value: string) {
  const country = value.trim().toUpperCase();

  if (!country || ["GB", "GBR", "UK", "UNITED KINGDOM"].includes(country)) {
    return "GB";
  }

  throw new AddressLookupError("DELIVERY_COUNTRY_UNSUPPORTED", 400);
}

function clean(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function compactPostcode(value: string) {
  return value.toUpperCase().replace(/\s+/gu, "");
}

function validatePostcodeQuery(value: string) {
  const compact = compactPostcode(value);

  if (compact.length < 3) {
    throw new AddressLookupError("ADDRESS_LOOKUP_QUERY_TOO_SHORT", 400);
  }

  if (compact.length > 7 || !/^[A-Z0-9]+$/u.test(compact)) {
    throw new AddressLookupError("ADDRESS_LOOKUP_QUERY_INVALID", 400);
  }

  return compact;
}

async function idealPostcodesGet<T>(
  path: string,
  params?: Record<string, string>,
): Promise<T> {
  const url = new URL(`${IDEAL_POSTCODES_BASE_URL}${path}`);

  for (const [name, value] of Object.entries(params ?? {})) {
    url.searchParams.set(name, value);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs());

  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        accept: "application/json",
        authorization: `api_key="${apiKey()}"`,
      },
      signal: controller.signal,
    });

    if (response.status === 404) {
      throw new AddressLookupError("ADDRESS_LOOKUP_NOT_FOUND", 404);
    }

    if (!response.ok) {
      throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
    }

    let body: IdealPostcodesEnvelope<T>;
    try {
      body = (await response.json()) as IdealPostcodesEnvelope<T>;
    } catch {
      throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
    }

    if (body.code !== 2000 || body.result == null) {
      throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
    }

    return body.result;
  } catch (error) {
    if (error instanceof AddressLookupError) throw error;
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  } finally {
    clearTimeout(timer);
  }
}

async function searchDyneticPostcodes(query: string): Promise<AddressSearchItem[]> {
  const compact = validatePostcodeQuery(query);

  try {
    const outwardExists = await db.query(
      `
        select exists(
          select 1
          from core.gb_postcode_directory
          where outward_code = $1
        ) as exists
      `,
      [compact],
    );

    const useOutward = outwardExists.rows[0]?.exists === true;

    const result = await db.query(
      `
        select postcode, postcode_compact
        from core.gb_postcode_directory
        where
          ($1::boolean = true and outward_code = $2)
          or
          ($1::boolean = false and postcode_compact like $3)
        order by
          case when postcode_compact = $2 then 0 else 1 end,
          postcode
        limit $4
      `,
      [useOutward, compact, `${compact}%`, SEARCH_LIMIT],
    );

    return result.rows.map((row) => ({
      id: `postcode:${String(row.postcode_compact)}`,
      label: String(row.postcode),
    }));
  } catch {
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }
}

async function resolveDyneticPostcode(id: string): Promise<ResolvedAddress> {
  const raw = id.startsWith("postcode:") ? id.slice("postcode:".length) : id;
  const compact = compactPostcode(raw);

  if (!compact || compact.length > 7 || !/^[A-Z0-9]+$/u.test(compact)) {
    throw new AddressLookupError("ADDRESS_LOOKUP_NOT_FOUND", 404);
  }

  try {
    const result = await db.query(
      `
        select postcode
        from core.gb_postcode_directory
        where postcode_compact = $1
        limit 1
      `,
      [compact],
    );

    if (result.rows.length === 0) {
      throw new AddressLookupError("ADDRESS_LOOKUP_NOT_FOUND", 404);
    }

    return {
      address1: null,
      address2: null,
      town: null,
      county: null,
      postcode: String(result.rows[0].postcode),
      country: "GB",
    };
  } catch (error) {
    if (error instanceof AddressLookupError) throw error;
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }
}

export async function searchUkAddresses(
  query: string,
  country = "GB",
): Promise<AddressSearchItem[]> {
  const q = query.trim();

  if (q.length < 3) {
    throw new AddressLookupError("ADDRESS_LOOKUP_QUERY_TOO_SHORT", 400);
  }

  if (q.length > 120) {
    throw new AddressLookupError("ADDRESS_LOOKUP_QUERY_INVALID", 400);
  }

  normaliseCountry(country);

  const provider = configuredProvider();

  if (provider === "DYNETIC_OPEN_DATA") {
    return searchDyneticPostcodes(q);
  }

  if (provider !== "IDEAL_POSTCODES") {
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }

  const result = await idealPostcodesGet<{ hits?: IdealAddressHit[] }>(
    "/autocomplete/addresses",
    {
      query: q,
      context: "GBR",
      limit: String(SEARCH_LIMIT),
    },
  );

  return (Array.isArray(result.hits) ? result.hits : [])
    .map((hit) => ({
      id: clean(hit.id),
      label: clean(hit.suggestion),
    }))
    .filter((hit) => hit.id.length > 0 && hit.label.length > 0)
    .slice(0, SEARCH_LIMIT);
}

export async function resolveUkAddress(id: string): Promise<ResolvedAddress> {
  const provider = configuredProvider();

  if (provider === "DYNETIC_OPEN_DATA") {
    return resolveDyneticPostcode(id);
  }

  if (provider !== "IDEAL_POSTCODES") {
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }

  const addressId = id.trim();

  if (!addressId || addressId.length > 200) {
    throw new AddressLookupError("ADDRESS_LOOKUP_NOT_FOUND", 404);
  }

  const result = await idealPostcodesGet<IdealAddress>(
    `/autocomplete/addresses/${encodeURIComponent(addressId)}/gbr`,
  );

  const countryIso2 = clean(result.country_iso_2).toUpperCase();
  const countryIso3 = clean(result.country_iso).toUpperCase();

  if (countryIso2 !== "GB" && countryIso3 !== "GBR") {
    throw new AddressLookupError("DELIVERY_COUNTRY_UNSUPPORTED", 422);
  }

  const address1 = clean(result.line_1);
  const address2 = [clean(result.line_2), clean(result.line_3)]
    .filter(Boolean)
    .join(", ");
  const town = clean(result.post_town);
  const county = clean(result.county);
  const postcode = clean(result.postcode).toUpperCase();

  if (!address1 || !postcode) {
    throw new AddressLookupError("ADDRESS_LOOKUP_UNAVAILABLE", 503);
  }

  return {
    address1,
    address2: address2 || null,
    town: town || null,
    county: county || null,
    postcode,
    country: "GB",
  };
}
