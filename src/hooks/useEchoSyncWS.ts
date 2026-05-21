import { useEffect, useRef, useState, useCallback } from "react";

export type AppStatus =
  | "idle"
  | "hearing"
  | "transcribing"
  | "extracting"
  | "thinking"
  | "error";

export interface WSState {
  status: AppStatus;
  partialText: string;
  isFinal: boolean;
  lastResult: string;
  connected: boolean;
}

const WS_URL = "ws://127.0.0.1:8765/ws/status";
const RECONNECT_DELAY_MS = 2000;

export function useEchoSyncWS(): WSState {
  const [state, setState] = useState<WSState>({
    status: "idle",
    partialText: "",
    isFinal: false,
    lastResult: "",
    connected: false,
  });

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      setState((s) => ({ ...s, connected: true }));
    };

    ws.onclose = () => {
      setState((s) => ({ ...s, connected: false }));
      // Auto-reconnect
      reconnectTimer.current = setTimeout(connect, RECONNECT_DELAY_MS);
    };

    ws.onerror = () => {
      ws.close();
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data as string);

        if (msg.event === "status_change") {
          setState((s) => ({
            ...s,
            status: msg.state as AppStatus,
            lastResult: msg.payload?.result ?? s.lastResult,
            // Clear partial text when returning to idle
            partialText: msg.state === "idle" ? "" : s.partialText,
            isFinal: msg.state === "idle" ? false : s.isFinal,
          }));
        } else if (msg.event === "partial_transcript") {
          setState((s) => ({
            ...s,
            partialText: msg.text ?? "",
            isFinal: msg.is_final ?? false,
          }));
        }
      } catch {
        // ignore malformed messages
      }
    };
  }, []);

  useEffect(() => {
    connect();
    return () => {
      if (reconnectTimer.current) clearTimeout(reconnectTimer.current);
      wsRef.current?.close();
    };
  }, [connect]);

  return state;
}
