type ClaimedNotification = {
  notification_id: string;
  request: { body: string; title: string };
};

type DesktopNotification = {
  once(event: "show" | "failed", listener: (error?: Error) => void): void;
  show(): void;
};

export type DesktopNotificationWorkerOptions = {
  createNotification(options: { body: string; title: string }): DesktopNotification;
  intervalMs?: number;
  isSupported(): boolean;
  request: SidecarRequest;
};

export function startDesktopNotificationWorker(
  options: DesktopNotificationWorkerOptions,
): () => void {
  let stopped = false;
  let polling = false;
  const poll = async () => {
    if (stopped || polling) return;
    polling = true;
    try {
      await deliverDesktopNotificationsOnce(options);
    } catch (error) {
      console.error("Desktop notification poll failed", error);
    } finally {
      polling = false;
    }
  };
  void poll();
  const timer = setInterval(() => void poll(), options.intervalMs ?? 15_000);
  timer.unref?.();
  return () => {
    stopped = true;
    clearInterval(timer);
  };
}

export async function deliverDesktopNotificationsOnce(
  options: DesktopNotificationWorkerOptions,
): Promise<number> {
  if (!options.isSupported()) return 0;
  const request = options.request;
  const query = new URLSearchParams({
    channel: "desktop",
    worker: "desktop-electron",
    limit: "25",
  });
  const response = await request(`/foundation/notifications/claim?${query}`);
  if (!response.ok) throw new Error(`Notification claim failed with HTTP ${response.status}`);
  const notifications = (await response.json()) as ClaimedNotification[];
  for (const notification of notifications) {
    let outcome: unknown;
    try {
      await showNotification(options.createNotification({
        body: notification.request.body,
        title: notification.request.title,
      }));
      outcome = {
        kind: "delivered",
        delivery_id: `electron:${notification.notification_id}`,
      };
    } catch {
      outcome = {
        kind: "uncertain",
        message: "Electron notification delivery could not be confirmed",
      };
    }
    const finish = await request(
      `/foundation/notifications/${encodeURIComponent(notification.notification_id)}`,
      {
        body: JSON.stringify({ worker: "desktop-electron", outcome }),
        headers: { "Content-Type": "application/json" },
        method: "POST",
      },
    );
    if (!finish.ok) throw new Error(`Notification completion failed with HTTP ${finish.status}`);
  }
  return notifications.length;
}

function showNotification(notification: DesktopNotification): Promise<void> {
  return new Promise((resolve, reject) => {
    let settled = false;
    notification.once("show", () => {
      if (!settled) {
        settled = true;
        resolve();
      }
    });
    notification.once("failed", (error) => {
      if (!settled) {
        settled = true;
        reject(error ?? new Error("Notification failed"));
      }
    });
    try {
      notification.show();
    } catch (error) {
      settled = true;
      reject(error);
    }
  });
}
import type { SidecarRequest } from "./sidecarSupervisor";
