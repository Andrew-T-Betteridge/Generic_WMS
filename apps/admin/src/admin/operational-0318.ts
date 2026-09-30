export type OperationalRow = Record<string, unknown>;

export function newOperationId(prefix: string): string {
  if (
    globalThis.crypto &&
    typeof globalThis.crypto.randomUUID === "function"
  ) {
    return `${prefix}:${globalThis.crypto.randomUUID()}`;
  }

  return `${prefix}:${Date.now()}:${Math.random().toString(36).slice(2)}`;
}

export function refundableBalance(payment: OperationalRow): number {
  const captured = Number(
    payment.captured_amount ??
      payment.CAPTURED_AMOUNT ??
      payment.amount ??
      payment.AMOUNT ??
      0,
  );

  const refunded = Number(
    payment.refunded_amount ??
      payment.REFUNDED_AMOUNT ??
      payment.total_refunded ??
      payment.TOTAL_REFUNDED ??
      0,
  );

  if (!Number.isFinite(captured) || !Number.isFinite(refunded)) {
    return 0;
  }

  return Math.max(0, captured - refunded);
}

export function customerHref(customerKey: string): string {
  return `/customers?customer=${encodeURIComponent(customerKey)}`;
}

export function orderHref(orderId: string): string {
  return `/orders/${encodeURIComponent(orderId)}`;
}
