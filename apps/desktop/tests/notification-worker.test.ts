// @vitest-environment node

import { describe, expect, it, vi } from "vitest";

import { deliverDesktopNotificationsOnce } from "../src/main/notificationWorker";

describe("desktop notification host", () => {
  it("claims one channel-scoped notification and records confirmed delivery", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify([{
        notification_id: "notification-1",
        request: { title: "Reminder", body: "Review the draft" },
      }]), { headers: { "Content-Type": "application/json" } }))
      .mockResolvedValueOnce(new Response("true", { headers: { "Content-Type": "application/json" } }));
    const show = vi.fn();

    const count = await deliverDesktopNotificationsOnce({
      createNotification: () => ({
        once: (event, listener) => {
          if (event === "show") show.mockImplementationOnce(() => listener());
        },
        show: () => show(),
      }),
      isSupported: () => true,
      request: fetchMock,
    });

    expect(count).toBe(1);
    expect(fetchMock.mock.calls[0][0]).toContain("channel=desktop");
    expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({
      worker: "desktop-electron",
      outcome: { kind: "delivered", delivery_id: "electron:notification-1" },
    });
  });

  it("does not claim when operating-system notifications are unsupported", async () => {
    const fetchMock = vi.fn();
    await expect(deliverDesktopNotificationsOnce({
      createNotification: () => { throw new Error("unused"); },
      isSupported: () => false,
      request: fetchMock,
    })).resolves.toBe(0);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
