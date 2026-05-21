import { useEffect } from "react";
import { isPermissionGranted, requestPermission, sendNotification } from "@tauri-apps/plugin-notification";

/**
 * Listens for notification_trigger WebSocket events and dispatches
 * Windows toast notifications via the Tauri notification plugin.
 */
export function useNotifications(ws: WebSocket | null) {
  useEffect(() => {
    if (!ws) return;

    const handleMessage = async (event: MessageEvent) => {
      try {
        const msg = JSON.parse(event.data as string);
        if (msg.event === "notification_trigger") {
          let granted = await isPermissionGranted();
          if (!granted) {
            const permission = await requestPermission();
            granted = permission === "granted";
          }
          if (granted) {
            sendNotification({
              title: "EchoSync Reminder",
              body: msg.message ?? "You have a reminder.",
            });
          }
        }
      } catch {
        // ignore
      }
    };

    ws.addEventListener("message", handleMessage);
    return () => ws.removeEventListener("message", handleMessage);
  }, [ws]);
}
