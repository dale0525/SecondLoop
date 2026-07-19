import { app, BrowserWindow, dialog, ipcMain, Notification, safeStorage, shell } from "electron";
import { open, rename, rm } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { registerApprovalWindowController } from "./approvalWindow";
import { registerAttachmentController } from "./attachmentController";
import { registerDataProtectionController } from "./dataProtectionController";
import { registerDeveloperAccessController } from "./developerAccessController";
import {
  invalidateDeveloperGatewayDeployment,
  loadDeveloperProjectSnapshot,
  recordDeveloperGatewayDeployment,
  registerDeveloperProjectController,
  verifyDeveloperGatewayDeployment,
} from "./developerProjectController";
import { packageDeveloperApp } from "./developerPackager";
import { createDesktopSecurityProvisioner } from "./desktopSecurityProvisioner";
import { createDesktopSecurityKeyStore } from "./desktopSecurityKeys";
import { startDesktopSidecarWithSecurity } from "./desktopStartupSecurity";
import {
  installDesktopLifecycle,
  type DesktopLifecycleEvent,
  type DesktopWindowScope,
} from "./desktopLifecycle";
import { getDesktopWindowConfig } from "./index";
import { loadHostBootstrap, registerHostBootstrapController } from "./hostBootstrapController";
import { registerIdentityController } from "./identityController";
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

configureDevelopmentUserDataRoot();

app.whenReady().then(async () => {
  const rendererBase = process.env.AGENTWEAVE_DESKTOP_URL;
  const userDataPath = app.getPath("userData");
  const sidecarResolution = resolveDesktopSidecar({
    appPath: app.getAppPath(),
    env: process.env,
    isPackaged: app.isPackaged,
    resourcesPath: process.resourcesPath,
    userDataPath,
  });
  const sidecar = createDesktopSidecarController(sidecarResolution, {
    log: (stream, message) => console.log(`[sidecar:${stream}] ${message}`),
  });
  const security = createDesktopSecurityProvisioner({
    keyStore: createDesktopSecurityKeyStore({
      backupKeyPath: path.join(userDataPath, "backup-key.v1.json"),
      credentialVaultKeyPath: path.join(userDataPath, "credential-vault-key.v1.json"),
      legacyKeyPath: path.join(userDataPath, "data-protection-key.v1.json"),
      safeStorage,
    }),
    sidecar,
  });
  installSidecarShutdownGate({
    app,
    controller: sidecar,
    onError: () => console.error("Failed to stop the managed sidecar"),
  });
  await startDesktopSidecarWithSecurity({
    onCredentialVaultStartupFailure: (failure) => {
      console.error(failure === "credential-key-unavailable"
        ? "Credential Vault key is unavailable"
        : failure === "sidecar-startup-failed"
          ? "Sidecar could not start with Credential Vault"
          : "Credential Vault startup failed");
    },
    resolution: sidecarResolution,
    security,
    sidecar,
  });
  const mainUrl = rendererBase
    ? new URL("/", rendererBase).href
    : pathToFileURL(path.join(__dirname, "../dist/index.html")).href;
  const approvalUrl = rendererBase
    ? new URL("/approval.html", rendererBase).href
    : pathToFileURL(path.join(__dirname, "../dist/approval.html")).href;
  const disposeNotifications = startDesktopNotificationWorker({
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
  const lifecycle = installDesktopLifecycle({
    createWindowScope: async () => {
      const windowConfig = getDesktopWindowConfig();
      const mainWindow = new BrowserWindow({
        ...windowConfig,
        webPreferences: {
          ...windowConfig.webPreferences,
          preload: path.join(__dirname, "preload.cjs"),
        },
      });
      const disposers: Array<() => void> = [];
      let windowScopeDisposed = false;
      const disposeWindowScope = () => {
        if (windowScopeDisposed) return;
        windowScopeDisposed = true;
        for (const dispose of disposers.reverse()) dispose();
      };
      try {
        const developerAppRoot = process.env.AGENTWEAVE_APP_ROOT
          ? path.resolve(process.env.AGENTWEAVE_APP_ROOT)
          : null;
        configureRequesterWindowSecurity({
          openExternal: (url) => shell.openExternal(url),
          onExternalError: (error) => console.error("Failed to open external URL", error),
          trustedUrl: mainUrl,
          webContents: mainWindow.webContents,
        });
        disposers.push(registerSidecarController({
          controller: sidecar,
          ipcMain,
          requesterWebContents: mainWindow.webContents,
        }));
        disposers.push(registerApprovalWindowController({
          approverToken: process.env.AGENTWEAVE_APPROVER_TOKEN ?? "",
          approvalPreload: path.join(__dirname, "approval-preload.cjs"),
          approvalUrl,
          createWindow: (options) => new BrowserWindow({ ...options, parent: mainWindow }),
          ipcMain,
          requesterWebContents: mainWindow.webContents,
          sidecarRequest: sidecar.request,
        }));
        disposers.push(registerOwnerController({
          ipcMain,
          requesterToken: process.env.AGENTWEAVE_OWNER_TOKEN ?? "",
          requesterWebContents: mainWindow.webContents,
          sidecarRequest: sidecar.request,
        }));
        disposers.push(registerSidecarApiController({
          ...(sidecarResolution.mode === "managed"
            ? { ensureCredentialVault: () => security.ensureCredentialVault() }
            : {}),
          ipcMain,
          openExternal: (url) => shell.openExternal(url),
          requesterWebContents: mainWindow.webContents,
          sidecarRequest: sidecar.request,
        }));
        disposers.push(registerAttachmentController({
          ipcMain,
          pickFile: async () => {
            const result = await dialog.showOpenDialog(mainWindow, {
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
        }));
        disposers.push(registerDataProtectionController({
          chooseBackupDestination: async () => {
            const productName = app.getName();
            const result = await dialog.showSaveDialog(mainWindow, {
              defaultPath: `${productName}-${new Date().toISOString().slice(0, 10)}.agentweave-backup`,
              filters: [{
                name: `${productName} encrypted backup`,
                extensions: ["agentweave-backup"],
              }],
            });
            return result.canceled ? null : (result.filePath ?? null);
          },
          chooseBackupSource: async () => {
            const productName = app.getName();
            const result = await dialog.showOpenDialog(mainWindow, {
              filters: [{
                name: `${productName} encrypted backup`,
                extensions: ["agentweave-backup"],
              }],
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
          ...(sidecarResolution.mode === "managed"
            ? {
                prepareBackup: () => security.ensureBackup(),
                unwrapKey: (wrappedKey: string) => security.unwrapBackupKey(wrappedKey),
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
        }));
        disposers.push(registerDeveloperProjectController({
          appRoot: developerAppRoot,
          ipcMain,
          packageApp: async (appRoot) => packageDeveloperApp({
            appRoot,
            projectRoot: sidecarResolution.mode === "managed"
              ? sidecarResolution.cwd
              : process.cwd(),
          }),
          ...(sidecarResolution.mode === "managed"
            ? {
                refreshRuntime: async () => {
                  await sidecar.stop();
                  const status = await sidecar.start();
                  if (status.state !== "ready") {
                    throw new Error("The Agent runtime could not reload the developer project");
                  }
                },
              }
            : {}),
          requesterWebContents: mainWindow.webContents,
          showItemInFolder: (outputPath) => shell.showItemInFolder(outputPath),
        }));
        if (
          sidecarResolution.mode === "managed"
          && sidecarResolution.env.AGENTWEAVE_DEV_API === "1"
        ) {
          disposers.push(registerDeveloperAccessController({
            ensureCredentialVault: () => security.ensureCredentialVault(),
            ipcMain,
            invalidateDeployment: () => invalidateDeveloperGatewayDeployment({
              appRoot: developerAppRoot,
            }),
            loadProject: () => loadDeveloperProjectSnapshot(developerAppRoot),
            openExternal: (url) => shell.openExternal(url),
            recordDeployment: (expectedRevision, receipt) =>
              recordDeveloperGatewayDeployment({
                appRoot: developerAppRoot,
                expectedRevision,
                receipt,
              }),
            redirectUri: process.env.AGENTWEAVE_CLOUDFLARE_OAUTH_REDIRECT_URI
              ?? "http://127.0.0.1:8977/agentweave/cloudflare/callback",
            requesterWebContents: mainWindow.webContents,
            sidecarRequest: sidecar.request,
            verifyDeployment: (deployment, expectedRevision, test) =>
              verifyDeveloperGatewayDeployment({
                appRoot: developerAppRoot,
                deployment,
                expectedRevision,
                test,
              }),
          }));
        }
        disposers.push(registerModelSettingsController({
          ipcMain,
          loadHostDiscovery: () => loadHostBootstrap({
            ipcMain,
            requesterWebContents: mainWindow.webContents,
            sidecarRequest: sidecar.request,
          }),
          requesterWebContents: mainWindow.webContents,
          safeStorage,
          sidecarRequest: sidecar.request,
          storagePath: path.join(app.getPath("userData"), "model-settings.v1.json"),
        }));
        disposers.push(registerHostBootstrapController({
          ipcMain,
          requesterWebContents: mainWindow.webContents,
          sidecarRequest: sidecar.request,
        }));
        disposers.push(registerIdentityController({
          ...(sidecarResolution.mode === "managed"
            ? { ensureCredentialVault: () => security.ensureCredentialVault() }
            : {}),
          ipcMain,
          loadHostDiscovery: () => loadHostBootstrap({
            ipcMain,
            requesterWebContents: mainWindow.webContents,
            sidecarRequest: sidecar.request,
          }),
          openExternal: (url) => shell.openExternal(url),
          requesterWebContents: mainWindow.webContents,
          sidecarRequest: sidecar.request,
        }));
        await mainWindow.loadURL(mainUrl);
        return Object.freeze<DesktopWindowScope>({
          dispose: disposeWindowScope,
          focus: () => {
            if (mainWindow.isDestroyed()) return;
            if (mainWindow.isMinimized()) mainWindow.restore();
            mainWindow.show();
            mainWindow.focus();
          },
          isDestroyed: () => mainWindow.isDestroyed(),
          onClosed: (listener) => mainWindow.once("closed", listener),
        });
      } catch (error) {
        disposeWindowScope();
        if (!mainWindow.isDestroyed()) mainWindow.destroy();
        throw error;
      }
    },
    disposeHostScope: disposeNotifications,
    on: onLifecycleEvent,
    onError: (error) => console.error("Failed to create the main window", error),
    platform: process.platform,
    quit: () => app.quit(),
    removeListener: removeLifecycleListener,
  });
  await lifecycle.ensureWindow();
});

function configureDevelopmentUserDataRoot(): void {
  if (app.isPackaged) return;
  const configured = process.env.AGENTWEAVE_DEV_USER_DATA_ROOT;
  if (!configured) return;
  if (!path.isAbsolute(configured)) {
    throw new Error("AGENTWEAVE_DEV_USER_DATA_ROOT must be absolute");
  }
  app.setPath("userData", path.normalize(configured));
}

function onLifecycleEvent(event: DesktopLifecycleEvent, listener: () => void): void {
  switch (event) {
    case "activate":
      app.on("activate", listener);
      break;
    case "before-quit":
      app.on("before-quit", listener);
      break;
    case "will-quit":
      app.on("will-quit", listener);
      break;
    case "window-all-closed":
      app.on("window-all-closed", listener);
      break;
  }
}

function removeLifecycleListener(event: DesktopLifecycleEvent, listener: () => void): void {
  switch (event) {
    case "activate":
      app.removeListener("activate", listener);
      break;
    case "before-quit":
      app.removeListener("before-quit", listener);
      break;
    case "will-quit":
      app.removeListener("will-quit", listener);
      break;
    case "window-all-closed":
      app.removeListener("window-all-closed", listener);
      break;
  }
}
