import { gcm } from "@noble/ciphers/aes.js"
import { p256 } from "@noble/curves/nist.js"
import { hkdf } from "@noble/hashes/hkdf.js"
import { sha256 } from "@noble/hashes/sha2.js"

const encoder = new TextEncoder()
const purpose = encoder.encode("samgita/github-pat/entry/v1")

function encode(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

function decode(value: string): Uint8Array {
  return Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0))
}

export function encryptPat(token: string, serverPublicKey: string, ticket: string) {
  const peer = decode(serverPublicKey)
  const nonce = crypto.getRandomValues(new Uint8Array(12))
  const secretKey = p256.utils.randomSecretKey()
  const publicKey = p256.getPublicKey(secretKey, false)
  // OTP uses the 32-byte x coordinate. A compressed SEC 1 point prefixes it with one byte.
  const sharedX = p256.getSharedSecret(secretKey, peer, true).subarray(1)
  secretKey.fill(0)
  const key = hkdf(sha256, sharedX, nonce, purpose, 32)
  sharedX.fill(0)

  const message = encoder.encode(token)
  try {
    const ciphertext = gcm(key, nonce, encoder.encode(ticket)).encrypt(message)
    return { public_key: encode(publicKey), nonce: encode(nonce), ciphertext: encode(ciphertext) }
  } finally {
    key.fill(0)
    message.fill(0)
  }
}
