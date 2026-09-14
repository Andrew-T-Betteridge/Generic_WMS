# FINatics Website Start

This patch does two things:

1. loads the first real FINatics ecommerce product into the generic backend;
2. creates the first API + React storefront skeleton.

## 1. Apply database changes

From repository root:

```powershell
.\scripts\build-database.ps1
.\scripts\verify-clean-build.ps1
```

## 2. Start the API

```powershell
cd .\apps\api
npm install
Copy-Item .env.example .env
```

Edit `.env` and put your local PostgreSQL password in `DB_PASSWORD`.

Then:

```powershell
npm run dev
```

Expected API:

`http://localhost:3001`

Test:

`http://localhost:3001/health`

## 3. Start the website

Open a second PowerShell from repository root:

```powershell
cd .\apps\storefront
npm install
Copy-Item .env.example .env
npm run dev
```

Open:

`http://localhost:5173`

The first page is already connected to the Fry Tray product API.

## 4. Load inventory manually

The seed creates the product and 22 variant SKUs but deliberately creates no
physical inventory.

When inventory is added to one of those SKUs, its website availability changes
through the same WMS inventory data used by allocation.

## Next build

Once this screen is running, the next patch should be checkout:

- basket;
- customer/address;
- delivery quote;
- mixed livestock/non-live choice;
- CONSOLIDATE vs SPLIT_WHEN_REQUIRED;
- order submission through ORDER_HEADER_IF / ORDER_LINE_IF;
- payment integration.
