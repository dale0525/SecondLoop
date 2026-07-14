import { app, BrowserWindow, ipcMain, Notification, safeStorage, shell } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { registerApprovalWindowController } from "./approvalWindow";
import { getDesktopWindowConfig } from "./index";
import { registerHostBootstrapController } from "./hostBootstrapController";
import { registerModelSettingsController } from "./modelSettingsController";
import { startDesktopNotificationWorker } from "./notificationWorker";
import { configureRequesterWindowSecurity } from "./requesterWindowSecurity";

let mainWindow: BrowserWindow | null = null;
let disposeApproval: (() => void) | null = null;
let disposeModelSettings: (() => void) | null = null;
let disposeHostBootstrap: (() => void) | null = null;
let disposeNotifications: (() => void) | null = null;

app.whenReady().then(async () => {
  const rendererBase = process.env.AGENTWEAVE_DESKTOP_URL;
  mainWindow = new BrowserWindow({
    ...getDesktopWindowConfig(),
    webPreferences: {
      ...getDesktopWindowConfig().webPreferences,
      preload: path.join(__dirname, "preload.cjs")
    }
  });
  const mainUrl = rendererBase
    ? new URL("/", rendererBase).href
    : pathToFileURL(path.join(__dirname, "../dist/index.html")).href;
  const approvalUrl = rendererBase
    ? new URL("/approval.html", rendererBase).href
    : pathToFileURL(path.join(__dirname, "../dist/approval.html")).href;
  configureRequesterWindowSecurity({
    openExternal: (url) => shell.openExternal(url),
    onExternalError: (error) => console.error("Failed to open external URL", error),
    trustedUrl: mainUrl,
    webContents: mainWindow.webContents
  });
  disposeApproval = registerApprovalWindowController({
    approvalPreload: path.join(__dirname, "approval-preload.cjs"),
    approvalUrl,
    createWindow: (options) => new BrowserWindow({ ...options, parent: mainWindow! }),
    ipcMain,
    requesterWebContents: mainWindow.webContents
  });
  disposeModelSettings = registerModelSettingsController({
    ipcMain,
    requesterWebContents: mainWindow.webContents,
    safeStorage,
    serverBaseUrl: process.env.AGENTWEAVE_SERVER_URL,
    storagePath: path.join(app.getPath("userData"), "model-settings.v1.json")
  });
  disposeHostBootstrap = registerHostBootstrapController({
    ipcMain,
    requesterWebContents: mainWindow.webContents,
    serverBaseUrl: process.env.AGENTWEAVE_SERVER_URL
  });
  disposeNotifications = startDesktopNotificationWorker({
    createNotification: (options) => {
      const notification = new Notification(options);
      return {
        once: (event, listener) => {
          if (event === "show") notification.once("show", () => listener());
          else notification.once("failed", (_event, error) => listener(new Error(error)));
        },
        show: () => notification.show()
      };
    },
    isSupported: () => Notification.isSupported(),
    serverBaseUrl: process.env.AGENTWEAVE_SERVER_URL
  });
  await mainWindow.loadURL(mainUrl);
});

app.on("window-all-closed", () => {
  disposeApproval?.();
  disposeApproval = null;
  disposeModelSettings?.();
  disposeModelSettings = null;
  disposeHostBootstrap?.();
  disposeHostBootstrap = null;
  disposeNotifications?.();
  disposeNotifications = null;
  mainWindow = null;
  if (process.platform !== "darwin") app.quit();
});
