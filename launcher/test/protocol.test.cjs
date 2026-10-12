'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { REQUIRED_PACKETVER, validateManifest } = require('../protocol.cjs');

function manifest() {
  return {
    format: 2,
    packetver: REQUIRED_PACKETVER,
    server: 'game.example.invalid',
    ports: [6900, 6121, 5121],
    base: {
      version: '2.0.0', packetver: REQUIRED_PACKETVER, contentPolicy: 'rokira-base-v1',
      packageUrl: 'https://updates.example.invalid/base.zip', size: 100, sha256: 'a'.repeat(64),
    },
    patch: {
      version: '2.0.0', contentPolicy: 'rokira-patch-v1',
      packageUrl: 'https://updates.example.invalid/patch.zip', size: 100, sha256: 'b'.repeat(64),
    },
  };
}

test('accepts a complete 20250402 release manifest', () => {
  assert.equal(validateManifest(manifest()).packetver, 20250402);
});

test('rejects an old server protocol', () => {
  const value = manifest();
  value.packetver = 20100803;
  assert.throws(() => validateManifest(value), /PACKETVER=20250402/);
});

test('rejects a base package that does not confirm the new client protocol', () => {
  const value = manifest();
  value.base.packetver = 20100803;
  assert.throws(() => validateManifest(value), /cliente base não confirma PACKETVER=20250402/);
});
