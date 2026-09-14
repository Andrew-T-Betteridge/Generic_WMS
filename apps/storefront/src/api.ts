const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:3001";

export type Variant = {
  skuId: string;
  name: string;
  options: {
    size?: string;
    dimensions?: string;
    colour?: string;
  };
  price: number;
  compareAtPrice?: number | null;
  availableQty: number;
  available: boolean;
};

export type Product = {
  productId: string;
  name: string;
  slug: string;
  brand?: string;
  shortDescription?: string;
  description?: string;
  deliveryClass: string;
  currency: string;
  media: Array<{ type: string; role: string; url: string; alt?: string }>;
  specification: Record<string, unknown>;
  variants: Variant[];
};

export async function getProduct(slug: string): Promise<Product> {
  const response = await fetch(`${API_URL}/api/catalog/products/${slug}`);
  if (!response.ok) throw new Error("Unable to load product");
  return response.json();
}
