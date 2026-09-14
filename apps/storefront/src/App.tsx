import { useEffect, useMemo, useState } from "react";
import { useAuth0 } from "@auth0/auth0-react";
import { getProduct, Product, Variant } from "./api";

const slug = "finatics-aquatics-air-driven-fry-tray";

function money(value: number, currency: string) {
  return new Intl.NumberFormat("en-GB", {
    style: "currency",
    currency,
  }).format(value);
}

export default function App() {
  const [product, setProduct] = useState<Product | null>(null);
  const [selectedSize, setSelectedSize] = useState("Small");
  const [selectedColour, setSelectedColour] = useState("");
  const [error, setError] = useState("");
  const [accountMessage, setAccountMessage] = useState("");

const {
  isLoading: authLoading,
  isAuthenticated,
  user,
  error: authError,
  loginWithRedirect,
  logout,
  getAccessTokenSilently,
} = useAuth0();

  useEffect(() => {
    getProduct(slug)
      .then((data) => {
        setProduct(data);
        const first = data.variants[0];

        if (first) {
          setSelectedSize(first.options.size ?? "Small");
          setSelectedColour(first.options.colour ?? "");
        }
      })
      .catch(() => setError("Unable to load the product catalogue."));
  }, []);

  const sizes = useMemo(
    () => [
      ...new Set(
        product?.variants
          .map((x) => x.options.size)
          .filter(Boolean) ?? []
      ),
    ],
    [product]
  );

  const colours = useMemo(
    () => [
      ...new Set(
        product?.variants
          .filter((x) => x.options.size === selectedSize)
          .map((x) => x.options.colour)
          .filter(Boolean) ?? []
      ),
    ],
    [product, selectedSize]
  );

  const selectedVariant: Variant | undefined = product?.variants.find(
    (x) =>
      x.options.size === selectedSize &&
      x.options.colour === selectedColour
  );

  const signup = () => {
    loginWithRedirect({
      authorizationParams: {
        screen_hint: "signup",
      },
    });
  };

  const testDyneticAccount = async () => {
    try {
      setAccountMessage("Checking DYNETIC WMS account...");

      const token = await getAccessTokenSilently();

      const response = await fetch(
        `${import.meta.env.VITE_API_BASE_URL}/api/account`,
        {
          headers: {
            Authorization: `Bearer ${token}`,
          },
        }
      );

      const data = await response.json();

      if (!response.ok) {
        console.error("DYNETIC account error:", data);
        setAccountMessage("DYNETIC account authentication failed.");
        return;
      }

      console.log("DYNETIC account:", data);
      setAccountMessage("DYNETIC account authentication passed.");
    } catch (err) {
      console.error(err);
      setAccountMessage("Unable to authenticate with DYNETIC WMS.");
    }
  };

if (authError) {
  return (
    <main className="shell">
      <h2>Auth0 login error</h2>
      <p>{authError.message}</p>
    </main>
  );
}

if (error) {
  return (
    <main className="shell">
      <p>{error}</p>
    </main>
  );
}

if (!product) {
    return (
      <main className="shell">
        <p>Loading FINatics Aquatics…</p>
      </main>
    );
  }

  return (
    <>
      <header className="siteHeader">
        <a className="brand" href="/">
          FINatics<span>Aquatics</span>
        </a>

        <nav>
          <a href="#product">Shop</a>
          <a href="#why">Why FINatics</a>
          <a href="#delivery">Delivery</a>
        </nav>

        <div className="headerActions">
          {!authLoading && !isAuthenticated && (
            <>
              <button
                className="accountButton"
                onClick={() => loginWithRedirect()}
              >
                Log in
              </button>

              <button
                className="accountButton"
                onClick={signup}
              >
                Create account
              </button>
            </>
          )}

          {!authLoading && isAuthenticated && (
            <>
              <span className="accountEmail">
                {user?.email}
              </span>

              <button
                className="accountButton"
                onClick={testDyneticAccount}
              >
                Test account
              </button>

              <button
                className="accountButton"
                onClick={() =>
                  logout({
                    logoutParams: {
                      returnTo: window.location.origin,
                    },
                  })
                }
              >
                Log out
              </button>
            </>
          )}

          <button className="basketButton">
            Basket · 0
          </button>
        </div>
      </header>

      {accountMessage && (
        <div className="accountStatus">
          {accountMessage}
        </div>
      )}

      <main>
        <section className="hero">
          <div>
            <p className="eyebrow">BUILT IN A REAL FISH ROOM</p>

            <h1>Better equipment for healthier fry.</h1>

            <p>
              Practical aquatics products designed from everyday breeding,
              grow-out and fish-room use.
            </p>

            <a
              className="primaryButton"
              href="#product"
            >
              Shop the Fry Tray
            </a>
          </div>

          <div className="heroCard">
            <span>FINATICS ORIGINAL</span>

            <strong>
              Air-Driven
              <br />
              Fry Tray
            </strong>

            <small>
              External grow-out · continuous water exchange
            </small>
          </div>
        </section>

        <section
          className="productSection"
          id="product"
        >
          <div className="gallery">
            <div className="productVisual">
              <div className="trayMock">
                <div className="trayInner">
                  FINatics Aquatics
                </div>
              </div>

              <span>
                Product photography can drop into this gallery next.
              </span>
            </div>
          </div>

          <div className="productInfo">
            <p className="eyebrow">
              {product.brand}
            </p>

            <h2>{product.name}</h2>

            <p className="lead">
              {product.shortDescription}
            </p>

            <div className="price">
              {selectedVariant
                ? money(
                    Number(selectedVariant.price),
                    product.currency
                  )
                : money(
                    Number(product.variants[0]?.price ?? 0),
                    product.currency
                  )}
            </div>

            <fieldset>
              <legend>Size</legend>

              <div className="optionGrid">
                {sizes.map((size) => (
                  <button
                    key={size}
                    className={
                      selectedSize === size
                        ? "option active"
                        : "option"
                    }
                    onClick={() => {
                      setSelectedSize(size!);

                      const first =
                        product.variants.find(
                          (x) =>
                            x.options.size === size
                        );

                      setSelectedColour(
                        first?.options.colour ?? ""
                      );
                    }}
                  >
                    {size}
                  </button>
                ))}
              </div>
            </fieldset>

            <fieldset>
              <legend>Colour</legend>

              <select
                value={selectedColour}
                onChange={(e) =>
                  setSelectedColour(e.target.value)
                }
              >
                {colours.map((colour) => (
                  <option
                    key={colour}
                    value={colour}
                  >
                    {colour}
                  </option>
                ))}
              </select>
            </fieldset>

            {selectedVariant && (
              <div className="variantMeta">
                <span>
                  {selectedVariant.options.dimensions}
                </span>

                <span>
                  SKU {selectedVariant.skuId}
                </span>

                <span
                  className={
                    selectedVariant.available
                      ? "stock yes"
                      : "stock"
                  }
                >
                  {selectedVariant.available
                    ? `${selectedVariant.availableQty} available`
                    : "Stock to be loaded"}
                </span>
              </div>
            )}

            <button
              className="addButton"
              disabled={!selectedVariant?.available}
            >
              {selectedVariant?.available
                ? "Add to basket"
                : "Awaiting inventory"}
            </button>

            <p className="description">
              {product.description}
            </p>
          </div>
        </section>

        <section
          className="featureStrip"
          id="why"
        >
          <article>
            <strong>External hang-on</strong>
            <span>
              Keeps valuable tank space free.
            </span>
          </article>

          <article>
            <strong>Air-driven circulation</strong>
            <span>
              Continuous exchange with aquarium water.
            </span>
          </article>

          <article>
            <strong>Small + Medium</strong>
            <span>
              Large will be added when ready.
            </span>
          </article>

          <article>
            <strong>UK designed</strong>
            <span>
              Built from real fish-room use.
            </span>
          </article>
        </section>

        <section
          className="delivery"
          id="delivery"
        >
          <p className="eyebrow">
            CONNECTED TO THE WMS
          </p>

          <h2>
            The website already reads real backend stock.
          </h2>

          <p>
            Once inventory is entered against a variant SKU,
            availability on this page is calculated from the same
            inventory used for allocation, picking and fulfilment.
          </p>
        </section>
      </main>
    </>
  );
}