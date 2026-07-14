export type DesktopWindowConfig = {
  height: number;
  minHeight: number;
  minWidth: number;
  preload: string;
  title: string;
  width: number;
  webPreferences: {
    contextIsolation: true;
    nodeIntegration: false;
    sandbox: true;
  };
};

export const desktopWindowConfig: DesktopWindowConfig = {
  height: 900,
  minHeight: 720,
  minWidth: 360,
  // Electron hosts should point BrowserWindow at the compiled preload bundle.
  preload: "dist/preload/index.js",
  title: "AgentWeave",
  width: 1280,
  webPreferences: {
    contextIsolation: true,
    nodeIntegration: false,
    sandbox: true
  }
};

export function getDesktopWindowConfig(): DesktopWindowConfig {
  return desktopWindowConfig;
}
