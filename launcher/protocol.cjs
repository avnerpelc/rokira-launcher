'use strict';

const REQUIRED_PACKETVER = 20250402;

function validateManifest(manifest) {
  if (!manifest || manifest.format !== 2) throw new Error('A configuração de atualização precisa da estrutura segura base + patch.');
  if (manifest.packetver !== REQUIRED_PACKETVER) throw new Error(`Atualização bloqueada: este launcher exige PACKETVER=${REQUIRED_PACKETVER}.`);
  if (!manifest.server || !Array.isArray(manifest.ports) || !manifest.ports.length || manifest.ports.some((p) => !Number.isInteger(p) || p < 1 || p > 65535)) {
    throw new Error('A configuração de conexão do jogo está incompleta.');
  }
  for (const channel of ['base', 'patch']) {
    const release = manifest[channel];
    if (!release || !/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(release.version || '')) throw new Error(`A versão ${channel} não está configurada.`);
    if (typeof release.packageUrl !== 'string' || new URL(release.packageUrl).protocol !== 'https:') throw new Error(`O pacote ${channel} não usa HTTPS.`);
    const requiredPolicy = channel === 'base' ? 'rokira-base-v1' : 'rokira-patch-v1';
    if (release.contentPolicy !== requiredPolicy) throw new Error(`O pacote ${channel} não tem a política de conteúdo esperada.`);
    if (!/^[a-f\d]{64}$/i.test(release.sha256 || '') || !Number.isSafeInteger(release.size) || release.size < 1 || release.size > 2_000_000_000) throw new Error(`A verificação de integridade do pacote ${channel} está inválida.`);
  }
  if (manifest.base.packetver !== REQUIRED_PACKETVER) throw new Error(`O cliente base não confirma PACKETVER=${REQUIRED_PACKETVER}.`);
  return manifest;
}

module.exports = { REQUIRED_PACKETVER, validateManifest };
