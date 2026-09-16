-- MEDIA_ROLE mapping validated against ck_product_media_role:
--   main      -> HERO
--   side/top/end/details -> GALLERY
--   marketing -> HOVER
-- Allowed schema values are HERO, GALLERY, REPRESENTATIVE, CURRENT_STOCK, HOVER.
--
-- FINatics Aquatics Air-Driven Fry Tray media seed
-- Built against the existing seeded product:
--   CLIENT_ID  = FINATICS
--   PRODUCT_ID = FRYTRAY001
--   SLUG       = finatics-aquatics-air-driven-fry-tray
--
-- This seed uses the EXISTING PRODUCT_VARIANT OPTION_VALUES.colour values.
-- Small and Medium SKUs for the same colour share the same image set.
--
-- IMPORTANT mismatches found in the supplied assets vs existing product seed:
--   * WHITE PINK assets are NOT inserted: there is no White/Pink SKU in the supplied seed.
--   * Existing colour "Clear / Black / Clear" has no matching photo folder in the supplied assets.
--
-- Run in fulfilment_dev first, validate, then apply to fulfilment_test.
-- This script is repeatable for this product/media path.

BEGIN;

-- Make the catalogue-level product image point at a real supplied image
-- instead of the old /products/fry-tray/hero.webp placeholder.
UPDATE core.PRODUCT
SET MEDIA = jsonb_build_array(
    jsonb_build_object(
        'type','image',
        'role','hero',
        'url','/media/products/fry-tray/white/main.png',
        'alt','Finatics Aquatics Air-Driven Fry Tray'
    )
),
LAST_UPDATE_DSTAMP = now()
WHERE CLIENT_ID = 'FINATICS'
  AND PRODUCT_ID = 'FRYTRAY001'
  AND SLUG = 'finatics-aquatics-air-driven-fry-tray';

-- Remove only media previously seeded under our fry-tray storefront paths.
DELETE FROM core.PRODUCT_MEDIA m
WHERE m.CLIENT_ID = 'FINATICS'
  AND m.PRODUCT_ID = 'FRYTRAY001'
  AND (
      m.MEDIA_URL LIKE '/media/products/fry-tray/%'
      OR m.MEDIA_URL LIKE '/media/products/finatics-aquatics-air-driven-fry-tray/%'
  );

WITH media_source(
    folder_slug,
    variant_colour,
    source_role,
    media_role,
    media_url,
    sort_sequence,
    alt_text,
    caption
) AS (
VALUES
  ('black', 'Black / White / Black', 'end', 'GALLERY', '/media/products/fry-tray/black/end.png', 40, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - End', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - End'),
  ('black', 'Black / White / Black', 'side', 'GALLERY', '/media/products/fry-tray/black/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Side', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Side'),
  ('black', 'Black / White / Black', 'top', 'GALLERY', '/media/products/fry-tray/black/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Top', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Top'),
  ('black', 'Black / White / Black', 'main', 'HERO', '/media/products/fry-tray/black/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Main', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Main'),
  ('black', 'Black / White / Black', 'marketing', 'HOVER', '/media/products/fry-tray/black/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / Black - Marketing'),
  ('black-white', 'Black / White / White', 'side', 'GALLERY', '/media/products/fry-tray/black-white/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Side', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Side'),
  ('black-white', 'Black / White / White', 'main', 'HERO', '/media/products/fry-tray/black-white/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Main', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Main'),
  ('black-white', 'Black / White / White', 'top', 'GALLERY', '/media/products/fry-tray/black-white/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Top', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Top'),
  ('black-white', 'Black / White / White', 'end', 'GALLERY', '/media/products/fry-tray/black-white/end.jpeg', 40, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - End', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - End'),
  ('black-white', 'Black / White / White', 'marketing', 'HOVER', '/media/products/fry-tray/black-white/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Black / White / White - Marketing'),
  ('blue', 'Blue / White / Blue', 'end', 'GALLERY', '/media/products/fry-tray/blue/end.png', 40, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - End', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - End'),
  ('blue', 'Blue / White / Blue', 'side', 'GALLERY', '/media/products/fry-tray/blue/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Side', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Side'),
  ('blue', 'Blue / White / Blue', 'main', 'HERO', '/media/products/fry-tray/blue/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Main', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Main'),
  ('blue', 'Blue / White / Blue', 'top', 'GALLERY', '/media/products/fry-tray/blue/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Top', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Top'),
  ('blue', 'Blue / White / Blue', 'marketing', 'HOVER', '/media/products/fry-tray/blue/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / Blue - Marketing'),
  ('blue-white', 'Blue / White / White', 'side', 'GALLERY', '/media/products/fry-tray/blue-white/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Side', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Side'),
  ('blue-white', 'Blue / White / White', 'main', 'HERO', '/media/products/fry-tray/blue-white/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Main', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Main'),
  ('blue-white', 'Blue / White / White', 'top', 'GALLERY', '/media/products/fry-tray/blue-white/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Top', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Top'),
  ('blue-white', 'Blue / White / White', 'end', 'GALLERY', '/media/products/fry-tray/blue-white/end.jpeg', 40, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - End', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - End'),
  ('blue-white', 'Blue / White / White', 'marketing', 'HOVER', '/media/products/fry-tray/blue-white/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Blue / White / White - Marketing'),
  ('green', 'Green / White / Green', 'end', 'GALLERY', '/media/products/fry-tray/green/end.png', 40, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - End', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - End'),
  ('green', 'Green / White / Green', 'side', 'GALLERY', '/media/products/fry-tray/green/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Side', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Side'),
  ('green', 'Green / White / Green', 'main', 'HERO', '/media/products/fry-tray/green/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Main', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Main'),
  ('green', 'Green / White / Green', 'top', 'GALLERY', '/media/products/fry-tray/green/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Top', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Top'),
  ('green', 'Green / White / Green', 'marketing', 'HOVER', '/media/products/fry-tray/green/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / Green - Marketing'),
  ('green-white', 'Green / White / White', 'side', 'GALLERY', '/media/products/fry-tray/green-white/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Side', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Side'),
  ('green-white', 'Green / White / White', 'main', 'HERO', '/media/products/fry-tray/green-white/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Main', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Main'),
  ('green-white', 'Green / White / White', 'top', 'GALLERY', '/media/products/fry-tray/green-white/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Top', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Top'),
  ('green-white', 'Green / White / White', 'end', 'GALLERY', '/media/products/fry-tray/green-white/end.jpeg', 40, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - End', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - End'),
  ('green-white', 'Green / White / White', 'marketing', 'HOVER', '/media/products/fry-tray/green-white/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Green / White / White - Marketing'),
  ('red', 'Red / White / Red', 'end', 'GALLERY', '/media/products/fry-tray/red/end.png', 40, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - End', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - End'),
  ('red', 'Red / White / Red', 'main', 'HERO', '/media/products/fry-tray/red/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Main', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Main'),
  ('red', 'Red / White / Red', 'top', 'GALLERY', '/media/products/fry-tray/red/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Top', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Top'),
  ('red', 'Red / White / Red', 'side', 'GALLERY', '/media/products/fry-tray/red/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Side', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Side'),
  ('red', 'Red / White / Red', 'marketing', 'HOVER', '/media/products/fry-tray/red/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / Red - Marketing'),
  ('red-white', 'Red / White / White', 'side', 'GALLERY', '/media/products/fry-tray/red-white/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Side', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Side'),
  ('red-white', 'Red / White / White', 'main', 'HERO', '/media/products/fry-tray/red-white/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Main', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Main'),
  ('red-white', 'Red / White / White', 'top', 'GALLERY', '/media/products/fry-tray/red-white/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Top', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Top'),
  ('red-white', 'Red / White / White', 'end', 'GALLERY', '/media/products/fry-tray/red-white/end.jpeg', 40, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - End', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - End'),
  ('red-white', 'Red / White / White', 'marketing', 'HOVER', '/media/products/fry-tray/red-white/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - Red / White / White - Marketing'),
  ('white-blue', 'White / Blue / Blue', 'side', 'GALLERY', '/media/products/fry-tray/white-blue/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Side', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Side'),
  ('white-blue', 'White / Blue / Blue', 'main', 'HERO', '/media/products/fry-tray/white-blue/main.jpeg', 10, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Main', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Main'),
  ('white-blue', 'White / Blue / Blue', 'top', 'GALLERY', '/media/products/fry-tray/white-blue/top.jpeg', 30, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Top', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Top'),
  ('white-blue', 'White / Blue / Blue', 'end', 'GALLERY', '/media/products/fry-tray/white-blue/end.jpeg', 40, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - End', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - End'),
  ('white-blue', 'White / Blue / Blue', 'marketing', 'HOVER', '/media/products/fry-tray/white-blue/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / Blue - Marketing'),
  ('white', 'White / Blue / White', 'end', 'GALLERY', '/media/products/fry-tray/white/end.png', 40, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - End', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - End'),
  ('white', 'White / Blue / White', 'top', 'GALLERY', '/media/products/fry-tray/white/top.png', 30, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Top', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Top'),
  ('white', 'White / Blue / White', 'main', 'HERO', '/media/products/fry-tray/white/main.png', 10, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Main', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Main'),
  ('white', 'White / Blue / White', 'side', 'GALLERY', '/media/products/fry-tray/white/side.jpeg', 20, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Side', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Side'),
  ('white', 'White / Blue / White', 'marketing', 'HOVER', '/media/products/fry-tray/white/marketing.jpeg', 50, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Marketing', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Marketing'),
  ('white', 'White / Blue / White', 'in-hand-main', 'GALLERY', '/media/products/fry-tray/white/in-hand-main.jpg', 61, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Main', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Main'),
  ('white', 'White / Blue / White', 'in-hand-side', 'GALLERY', '/media/products/fry-tray/white/in-hand-side.jpg', 62, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Side', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Side'),
  ('white', 'White / Blue / White', 'in-hand-angle', 'GALLERY', '/media/products/fry-tray/white/in-hand-angle.jpg', 63, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Angle', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Angle'),
  ('white', 'White / Blue / White', 'in-hand-top', 'GALLERY', '/media/products/fry-tray/white/in-hand-top.jpg', 64, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Top', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - In Hand Top'),
  ('white', 'White / Blue / White', 'airline-detail', 'GALLERY', '/media/products/fry-tray/white/airline-detail.jpg', 65, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Airline Detail', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Airline Detail'),
  ('white', 'White / Blue / White', 'air-inlet-detail', 'GALLERY', '/media/products/fry-tray/white/air-inlet-detail.jpg', 66, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Air Inlet Detail', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Air Inlet Detail'),
  ('white', 'White / Blue / White', 'filter-end-detail', 'GALLERY', '/media/products/fry-tray/white/filter-end-detail.jpg', 67, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Filter End Detail', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Filter End Detail'),
  ('white', 'White / Blue / White', 'filter-media-detail', 'GALLERY', '/media/products/fry-tray/white/filter-media-detail.jpg', 68, 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Filter Media Detail', 'FINatics Aquatics Air-Driven Fry Tray - White / Blue / White - Filter Media Detail')
),
variant_map AS (
    SELECT
        pv.CLIENT_ID,
        pv.PRODUCT_ID,
        pv.SKU_ID,
        pv.VARIANT_NAME,
        pv.OPTION_VALUES->>'colour' AS variant_colour
    FROM core.PRODUCT_VARIANT pv
    WHERE pv.CLIENT_ID = 'FINATICS'
      AND pv.PRODUCT_ID = 'FRYTRAY001'
      AND pv.ACTIVE = TRUE
)
INSERT INTO core.PRODUCT_MEDIA (
    CLIENT_ID,
    PRODUCT_ID,
    SKU_ID,
    MEDIA_TYPE,
    MEDIA_ROLE,
    MEDIA_URL,
    THUMBNAIL_URL,
    ALT_TEXT,
    CAPTION,
    SORT_SEQUENCE,
    ACTIVE
)
SELECT
    v.CLIENT_ID,
    v.PRODUCT_ID,
    v.SKU_ID,
    'IMAGE',
    s.media_role,
    s.media_url,
    s.media_url,
    s.alt_text,
    s.caption,
    s.sort_sequence,
    TRUE
FROM media_source s
JOIN variant_map v
  ON v.variant_colour = s.variant_colour;

COMMIT;

-- ============================================================
-- VALIDATION
-- ============================================================

-- 1. See every seeded SKU/media mapping.
SELECT
    pv.SKU_ID,
    pv.VARIANT_NAME,
    pv.OPTION_VALUES->>'size' AS size,
    pv.OPTION_VALUES->>'colour' AS colour,
    m.MEDIA_ROLE,
    m.MEDIA_URL,
    m.SORT_SEQUENCE
FROM core.PRODUCT_MEDIA m
JOIN core.PRODUCT_VARIANT pv
  ON pv.CLIENT_ID = m.CLIENT_ID
 AND pv.PRODUCT_ID = m.PRODUCT_ID
 AND pv.SKU_ID = m.SKU_ID
WHERE m.CLIENT_ID = 'FINATICS'
  AND m.PRODUCT_ID = 'FRYTRAY001'
  AND m.ACTIVE = TRUE
ORDER BY
    pv.SORT_SEQUENCE,
    m.SORT_SEQUENCE,
    m.MEDIA_URL;

-- 2. Show active variants that still have NO SKU-specific media.
-- Expected from the supplied assets: Clear / Black / Clear (Small + Medium).
SELECT
    pv.SKU_ID,
    pv.VARIANT_NAME,
    pv.OPTION_VALUES
FROM core.PRODUCT_VARIANT pv
WHERE pv.CLIENT_ID = 'FINATICS'
  AND pv.PRODUCT_ID = 'FRYTRAY001'
  AND pv.ACTIVE = TRUE
  AND NOT EXISTS (
      SELECT 1
      FROM core.PRODUCT_MEDIA m
      WHERE m.CLIENT_ID = pv.CLIENT_ID
        AND m.PRODUCT_ID = pv.PRODUCT_ID
        AND m.SKU_ID = pv.SKU_ID
        AND m.ACTIVE = TRUE
  )
ORDER BY pv.SORT_SEQUENCE;

-- 3. Check catalogue-level image now points to a real file.
SELECT PRODUCT_ID, PRODUCT_NAME, SLUG, MEDIA
FROM core.PRODUCT
WHERE CLIENT_ID = 'FINATICS'
  AND PRODUCT_ID = 'FRYTRAY001';
