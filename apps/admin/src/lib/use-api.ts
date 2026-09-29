import { useCallback, useEffect, useState } from "react";

export type ApiState<T> = {
  data: T | undefined;
  error: unknown;
  loading: boolean;
  reload: () => void;
};

/**
 * Runs a read against the WMS API whenever `key` changes.
 * Stale responses from superseded requests are ignored.
 */
export function useApi<T>(load: () => Promise<T>, key: string): ApiState<T> {
  const [data, setData] = useState<T | undefined>(undefined);
  const [error, setError] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    let live = true;
    setLoading(true);
    setError(null);
    load()
      .then((result) => { if (live) setData(result); })
      .catch((e) => { if (live) { setError(e); setData(undefined); } })
      .finally(() => { if (live) setLoading(false); });
    return () => { live = false; };
    // `load` is intentionally keyed by `key` so callers may pass inline functions.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, nonce]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);
  return { data, error, loading, reload };
}
