import { app, BrowserWindow, dialog, ipcMain, Notification, safeStorage, shell } from "electron";
import { open, rename, rm } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { registerApprovalWindowController } from "./approvalWindow";
import { registerAttachmentController } from "./attachmentController";
import {
  loadOrCreateDataProtectionKey,
  unwrapDataProtectionKey,
  type DesktopDataProtectionKey,
} from "./dataProtectionKey";
import { registerDataProtectionController } from "./dataProtectionController";
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
let disposeAttachments: (() => void) | null = null;
let disposeDataProtection: (() => void) | null = null;
let disposeModelSettings: (() => void) | null = null;
let disposeHostBootstrap: (() => void) | null = null;
let disposeNotifications: (() => void) | null = null;
let disposeSidecar: (() => void) | null = null;
let disposeSidecarApi: (() => void) | null = null;
let disposeOwner: (() => void) | null = null;

app.whenReady().then(async () => {
  const rendererBase = process.env.AGENTWEAVE_DESKTOP_URL;
  let dataProtection: DesktopDataProtectionKey | null = null;
  try {
    dataProtection = loadOrCreateDataProtectionKey({
      safeStorage,
      storagePath: path.join(app.getPath("userData"), "data-protection-key.v1.json"),
    });
  } catch {
    console.error("Data protection key is unavailable");
  }
  const sidecar = createDesktopSidecarController(resolveDesktopSidecar({
    appPath: app.getAppPath(),
    env: process.env,
    isPackaged: app.isPackaged,
    resourcesPath: process.resourcesPath,
    userDataPath: app.getPath("userData"),
  }), {
    ...(dataProtection ? { dataProtectionKey: dataProtection.key } : {}),
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
  disposeAttachments = registerAttachmentController({
    ipcMain,
    pickFile: async () => {
      const result = await dialog.showOpenDialog(mainWindow!, {
        properties: ["openFile"],
      });
      return result.canceled ? null : (result.filePaths[0] ?? null);
    },
    readFile: async (filePath) => {
      const handle = await open(filePath, "r");
      try {
        const metadata = await handle.stat();
        if (!metadata.isFile() || metadata.size > 16 * 1024 * 1024) {
          throw new Error("Selected attachment is not an allowed file");
        }
        return new Uint8Array(await handle.readFile());
      } finally {
        await handle.close();
      }
    },
    requesterWebContents: mainWindow.webContents,
    sidecarRequest: sidecar.request,
  });
  disposeDataProtection = registerDataProtectionController({
    chooseBackupDestination: async () => {
      const result = await dialog.showSaveDialog(mainWindow!, {
        defaultPath: `AgentWeave-${new Date().toISOString().slice(0, 10)}.agentweave-backup`,
        filters: [{ name: "AgentWeave encrypted backup", extensions: ["agentweave-backup"] }],
      });
      return result.canceled ? null : (result.filePath ?? null);
    },
    chooseBackupSource: async () => {
      const result = await dialog.showOpenDialog(mainWindow!, {
        filters: [{ name: "AgentWeave encrypted backup", extensions: ["agentweave-backup"] }],
        properties: ["openFile"],
      });
      return result.canceled ? null : (result.filePaths[0] ?? null);
    },
    ipcMain,
    readFile: async (filePath) => {
      const handle = await open(filePath, "r");
      try {
        const metadata = await handle.stat();
        if (!metadata.isFile() || metadata.size > 256 * 1024 * 1024 + 1024) {
          throw new Error("Selected backup is not an allowed file");
        }
        return new Uint8Array(await handle.readFile());
      } finally {
        await handle.close();
      }
    },
    requesterWebContents: mainWindow.webContents,
    sidecar,
    ...(dataProtection
      ? {
          unwrapKey: (wrappedKey: string) => unwrapDataProtectionKey(wrappedKey, safeStorage),
          wrappedKey: dataProtection.wrappedKey,
        }
      : {}),
    writeFile: async (filePath, bytes) => {
      const temporary = `${filePath}.tmp-${process.pid}`;
      const handle = await open(temporary, "wx", 0o600);
      try {
        await handle.writeFile(bytes);
        await handle.sync();
      } finally {
        await handle.close();
      }
      try {
        await rename(temporary, filePath);
      } finally {
        await rm(temporary, { force: true });
      }
    },
  });
  dataProtection?.key.fill(0);
  dataProtection = null;
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
  disposeAttachments?.();
  disposeAttachments = null;
  disposeDataProtection?.();
  disposeDataProtection = null;
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
