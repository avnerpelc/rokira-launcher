'use strict';

const { contextBridge, ipcRenderer, shell } = require('electron');

contextBridge.exposeInMainWorld('rokira', {
  version: '1.2.0',
  checkFiles: () => ipcRenderer.invoke('rokira:check-files'),
  getManifest: () => ipcRenderer.invoke('rokira:get-manifest'),
  getInstalledVersion: (channel) => ipcRenderer.invoke('rokira:get-installed-version', channel),
  serverStatus: () => ipcRenderer.invoke('rokira:server-status'),
  downloadUpdate: (channel, progress) => {
    const listener = (_event, value) => progress?.(value);
    ipcRenderer.on('rokira:download-progress', listener);
    return ipcRenderer.invoke('rokira:download-update', channel).finally(() => {
      ipcRenderer.removeListener('rokira:download-progress', listener);
    });
  },
  selectClientFolder: () => ipcRenderer.invoke('rokira:select-client-folder'),
  play: () => ipcRenderer.invoke('rokira:play'),
  news: () => ipcRenderer.invoke('rokira:news'),
  openDiscord: () => shell.openExternal('https://discord.gg/H7jZvBZcn'),
  openOfficialClient: () => shell.openExternal('https://renewal.playragnarok.com/downloads/clientdownload.aspx'),
});
