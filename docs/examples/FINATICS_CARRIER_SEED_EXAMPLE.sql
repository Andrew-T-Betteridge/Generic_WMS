-- EXAMPLE ONLY - deliberately NOT applied by build-database.ps1.
-- Keep FINatics-specific carrier choices out of the generic platform build.
--
-- Replace FINATICS with the actual client ID and replace example rates with
-- your contracted/confirmed commercial rates before using in production.

-- Dry goods example:
-- INSERT INTO config.CARRIER (... EVRI ...);
-- INSERT INTO config.CARRIER_SERVICE (... STANDARD ... LIVE_GOODS_ALLOWED=false ...);

-- Livestock example:
-- INSERT INTO config.CARRIER (... APC ...);
-- INSERT INTO config.CARRIER_SERVICE (... LIVE_FISH_NEXTDAY ... LIVE_GOODS_ALLOWED=true ...);

-- Suggested rules:
-- DELIVERY_CLASS=STANDARD  -> eligible dry-goods services
-- DELIVERY_CLASS=LIVESTOCK -> only specifically approved livestock services
--
-- Do not use public website prices as production contract rates.
