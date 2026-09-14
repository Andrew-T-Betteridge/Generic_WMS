-- FINatics first website product.
-- Price and variation wording based on the live FINatics eBay listing on
-- 11-Sep-2026. Stock is NOT imported from marketplaces; website availability
-- remains driven by core.INVENTORY.

INSERT INTO core.CLIENT (CLIENT_ID,DESCRIPTION,ACTIVE)
VALUES ('FINATICS','FINatics Aquatics',TRUE)
ON CONFLICT (CLIENT_ID) DO NOTHING;

INSERT INTO core.PRODUCT_CATEGORY (
    CLIENT_ID,CATEGORY_CODE,CATEGORY_NAME,SLUG,DESCRIPTION,SORT_SEQUENCE,ACTIVE
)
VALUES (
    'FINATICS','BREEDING_EQUIPMENT','Breeding Equipment','breeding-equipment',
    'Equipment for breeding, fry protection and grow-out.',
    20,TRUE
)
ON CONFLICT (CLIENT_ID,CATEGORY_CODE)
DO UPDATE SET
    CATEGORY_NAME=EXCLUDED.CATEGORY_NAME,
    SLUG=EXCLUDED.SLUG,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    ACTIVE=EXCLUDED.ACTIVE,
    LAST_UPDATE_DSTAMP=now();

INSERT INTO core.SKU (
    CLIENT_ID,SKU_ID,WEB_ACTIVE,WEB_FEATURED,
    SUPPLIER_DIRECT_ENABLED,AFFILIATE_FALLBACK,COMING_SOON
)
VALUES
    ('FINATICS','FRYTRAY001-S-G-W-G','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-G-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-B-W-B','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-B-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-R-W-R','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-R-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-BK-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-BK-W-BK','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-CL-BK-CL','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-W-B-B','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-S-W-B-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-G-W-G','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-G-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-B-W-B','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-B-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-R-W-R','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-R-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-BK-W-W','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-BK-W-BK','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-CL-BK-CL','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-W-B-B','Y','N','N','N','N'),
    ('FINATICS','FRYTRAY001-M-W-B-W','Y','N','N','N','N')
ON CONFLICT (CLIENT_ID,SKU_ID) DO UPDATE
SET WEB_ACTIVE='Y';

INSERT INTO core.PRODUCT (
    CLIENT_ID,PRODUCT_ID,PRODUCT_NAME,SLUG,BRAND_NAME,CATEGORY_CODE,
    SHORT_DESCRIPTION,DESCRIPTION,DELIVERY_CLASS,CURRENCY,
    MEDIA,SPECIFICATION,ACTIVE,FEATURED,SORT_SEQUENCE
)
VALUES (
    'FINATICS',
    'FRYTRAY001',
    'Finatics Aquatics Air-Driven Fry Tray',
    'finatics-aquatics-air-driven-fry-tray',
    'Finatics Aquatics',
    'BREEDING_EQUIPMENT',
    'External hang-on fry grow-out and nursery tray with air-driven water exchange.',
    'An external hang-on fry grow-out tray designed to protect fry and juveniles while sharing aquarium water with the main tank. Air-driven circulation provides continual water exchange, helping maintain stable temperature and water quality without taking up valuable internal tank space. Adjustable mounting makes it suitable for a range of aquarium setups.',
    'STANDARD',
    'GBP',
    '[{"type":"image","role":"hero","url":"/products/fry-tray/hero.webp","alt":"Finatics Aquatics Air-Driven Fry Tray"}]'::jsonb,
    '{"productType":"Air Driven Fry Tray","waterType":"All Water Types","material":"Plastic","countryOfOrigin":"United Kingdom","sizes":[{"code":"S","label":"Small","dimensions":"22 cm x 35 cm"},{"code":"M","label":"Medium","dimensions":"34.5 cm x 46 cm"}],"largeStatus":"NOT_YET_RELEASED"}'::jsonb,
    TRUE,
    TRUE,
    10
)
ON CONFLICT (CLIENT_ID,PRODUCT_ID)
DO UPDATE SET
    PRODUCT_NAME=EXCLUDED.PRODUCT_NAME,
    SLUG=EXCLUDED.SLUG,
    BRAND_NAME=EXCLUDED.BRAND_NAME,
    CATEGORY_CODE=EXCLUDED.CATEGORY_CODE,
    SHORT_DESCRIPTION=EXCLUDED.SHORT_DESCRIPTION,
    DESCRIPTION=EXCLUDED.DESCRIPTION,
    DELIVERY_CLASS=EXCLUDED.DELIVERY_CLASS,
    CURRENCY=EXCLUDED.CURRENCY,
    MEDIA=EXCLUDED.MEDIA,
    SPECIFICATION=EXCLUDED.SPECIFICATION,
    ACTIVE=EXCLUDED.ACTIVE,
    FEATURED=EXCLUDED.FEATURED,
    LAST_UPDATE_DSTAMP=now();

INSERT INTO core.PRODUCT_VARIANT (
    CLIENT_ID,PRODUCT_ID,SKU_ID,VARIANT_NAME,OPTION_VALUES,
    WEB_PRICE,ACTIVE,SORT_SEQUENCE
)
VALUES
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-G-W-G','Small - Green / White / Green','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Green / White / Green"}'::jsonb,26.99,TRUE,10),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-G-W-W','Small - Green / White / White','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Green / White / White"}'::jsonb,26.99,TRUE,20),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-B-W-B','Small - Blue / White / Blue','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Blue / White / Blue"}'::jsonb,26.99,TRUE,30),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-B-W-W','Small - Blue / White / White','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Blue / White / White"}'::jsonb,26.99,TRUE,40),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-R-W-R','Small - Red / White / Red','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Red / White / Red"}'::jsonb,26.99,TRUE,50),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-R-W-W','Small - Red / White / White','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Red / White / White"}'::jsonb,26.99,TRUE,60),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-BK-W-W','Small - Black / White / White','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Black / White / White"}'::jsonb,26.99,TRUE,70),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-BK-W-BK','Small - Black / White / Black','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Black / White / Black"}'::jsonb,26.99,TRUE,80),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-CL-BK-CL','Small - Clear / Black / Clear','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "Clear / Black / Clear"}'::jsonb,26.99,TRUE,90),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-W-B-B','Small - White / Blue / Blue','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "White / Blue / Blue"}'::jsonb,26.99,TRUE,100),
    ('FINATICS','FRYTRAY001','FRYTRAY001-S-W-B-W','Small - White / Blue / White','{"size": "Small", "dimensions": "22 cm x 35 cm", "colour": "White / Blue / White"}'::jsonb,26.99,TRUE,110),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-G-W-G','Medium - Green / White / Green','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Green / White / Green"}'::jsonb,26.99,TRUE,120),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-G-W-W','Medium - Green / White / White','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Green / White / White"}'::jsonb,26.99,TRUE,130),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-B-W-B','Medium - Blue / White / Blue','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Blue / White / Blue"}'::jsonb,26.99,TRUE,140),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-B-W-W','Medium - Blue / White / White','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Blue / White / White"}'::jsonb,26.99,TRUE,150),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-R-W-R','Medium - Red / White / Red','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Red / White / Red"}'::jsonb,26.99,TRUE,160),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-R-W-W','Medium - Red / White / White','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Red / White / White"}'::jsonb,26.99,TRUE,170),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-BK-W-W','Medium - Black / White / White','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Black / White / White"}'::jsonb,26.99,TRUE,180),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-BK-W-BK','Medium - Black / White / Black','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Black / White / Black"}'::jsonb,26.99,TRUE,190),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-CL-BK-CL','Medium - Clear / Black / Clear','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "Clear / Black / Clear"}'::jsonb,26.99,TRUE,200),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-W-B-B','Medium - White / Blue / Blue','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "White / Blue / Blue"}'::jsonb,26.99,TRUE,210),
    ('FINATICS','FRYTRAY001','FRYTRAY001-M-W-B-W','Medium - White / Blue / White','{"size": "Medium", "dimensions": "34.5 cm x 46 cm", "colour": "White / Blue / White"}'::jsonb,26.99,TRUE,220)
ON CONFLICT (CLIENT_ID,PRODUCT_ID,SKU_ID)
DO UPDATE SET
    VARIANT_NAME=EXCLUDED.VARIANT_NAME,
    OPTION_VALUES=EXCLUDED.OPTION_VALUES,
    WEB_PRICE=EXCLUDED.WEB_PRICE,
    ACTIVE=EXCLUDED.ACTIVE,
    SORT_SEQUENCE=EXCLUDED.SORT_SEQUENCE,
    LAST_UPDATE_DSTAMP=now();
