import { app, BrowserWindow, ipcMain, Notification, safeStorage, shell } from "electron";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { registerApprovalWindowController } from "./approvalWindow";
import { getDesktopWindowConfig } from "./index";
import { registerHostBootstrapController } from "./hostBootstrapController";
import { registerModelSettingsController } from "./modelSettingsController";
import { startDesktopNotificationWorker } from "./notificationWorker";
import { registerOwnerController } from "./ownerController";
import { configureRequesterWindowSecurity } from "./requesterWindowSecurity";
import {
  createDesktopSidecarController,
  installSidecarShutdownGate,
  registerSidecarController,
} from "./sidecarController";
import { resolveDesktopSidecar } from "./sidecarRuntime";
import { registerSidecarApiController } from "./sidecarApiController";

let mainWindow: BrowserWindow | null = null;
let disposeApproval: (() => void) | null = null;
let disposeModelSettings: (() => void) | null = null;
let disposeHostBootstrap: (() => void) | null = null;
let disposeNotifications: (() => void) | null = null;
let disposeSidecar: (() => void) | null = null;
let disposeSidecarApi: (() => void) | null = null;
let disposeOwner: (() => void) | null = null;

app.whenReady().then(async () => {
  const rendererBase = process.env.AGENTWEAVE_DESKTOP_URL;
  const sidecar = createDesktopSidecarController(resolveDesktopSidecar({
    appPath: app.getAppPath(),
    env: process.env,
    isPackaged: app.isPackaged,
    resourcesPath: process.resourcesPath,
    userDataPath: app.getPath("userData"),
  }), {
    log: (stream, message) => console.log(`[sidecar:${stream}] ${message}`),
  });
  installSidecarShutdownGate({
    app,
    controller: sidecar,
    onError: () => console.error("Failed to stop the managed sidecar"),
  });
  await sidecar.start();
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
  disposeSidecar = registerSidecarController({
    controller: sidecar,
    ipcMain,
    requesterWebContents: mainWindow.webContents,
  });
  disposeApproval = registerApprovalWindowController({
    approverToken: process.env.AGENTWEAVE_APPROVER_TOKEN ?? "",
    approvalPreload: path.join(__dirname, "approval-preload.cjs"),
    approvalUrl,
    createWindow: (options) => new BrowserWindow({ ...options, parent: mainWindow! }),
    ipcMain,
    requesterWebContents: mainWindow.webContents,
    sidecarRequest: sidecar.request,
  });
  disposeOwner = registerOwnerController({
    ipcMain,
    requesterToken: process.env.AGENTWEAVE_OWNER_TOKEN ?? "",
    requesterWebContents: mainWindow.webContents,
    sidecarRequest: sidecar.request,
  });
  disposeSidecarApi = registerSidecarApiController({
    ipcMain,
    requesterWebContents: mainWindow.webContents,
    sidecarRequest: sidecar.request,
  });
  disposeModelSettings = registerModelSettingsController({
    ipcMain,
    requesterWebContents: mainWindow.webContents,
    safeStorage,
    sidecarRequest: sidecar.request,
    storagePath: path.join(app.getPath("userData"), "model-settings.v1.json")
  });
  disposeHostBootstrap = registerHostBootstrapController({
    ipcMain,
    requesterWebContents: mainWindow.webContents,
    sidecarRequest: sidecar.request,
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
    request: sidecar.request,
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
  disposeSidecar?.();
  disposeSidecar = null;
  disposeSidecarApi?.();
  disposeSidecarApi = null;
  disposeOwner?.();
  disposeOwner = null;
  mainWindow = null;
  if (process.platform !== "darwin") app.quit();
});
