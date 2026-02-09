// Type definitions for Phoenix JavaScript client
// Based on phoenix v1.8.3

declare module "phoenix" {
  export class Socket {
    constructor(
      endPoint: string,
      opts?: {
        transport?: any
        encode?: (payload: any, callback: (encoded: any) => void) => void
        decode?: (payload: string, callback: (decoded: any) => void) => void
        timeout?: number
        heartbeatIntervalMs?: number
        reconnectAfterMs?: (tries: number) => number
        rejoinAfterMs?: (tries: number) => number
        logger?: (kind: string, msg: string, data: any) => void
        longpollerTimeout?: number
        params?: Record<string, any> | (() => Record<string, any>)
        vsn?: string
      }
    )

    connect(): void
    disconnect(callback?: () => void, code?: number, reason?: string): void
    channel(topic: string, chanParams?: Record<string, any>): Channel
    onOpen(callback: () => void): void
    onClose(callback: (event: any) => void): void
    onError(callback: (error: any) => void): void
    onMessage(callback: (message: any) => any): void
    log(kind: string, msg: string, data: any): void
    hasLogger(): boolean
    onConnOpen(): void
    onConnClose(event: any): void
    onConnError(error: any): void
    triggerChanError(): void
    connectionState(): string
    isConnected(): boolean
    remove(channel: Channel): void
    off(refs: number[]): void
    makeRef(): string
  }

  export class Channel {
    constructor(topic: string, params: Record<string, any> | (() => Record<string, any>), socket: Socket)

    join(timeout?: number): Push
    leave(timeout?: number): Push
    onClose(callback: (payload: any, ref: any, joinRef: any) => void): number
    onError(callback: (reason: any) => void): number
    on(event: string, callback: (payload: any, ref: any) => void): number
    off(event: string, ref?: number): void
    push(event: string, payload: Record<string, any>, timeout?: number): Push
    trigger(event: string, payload: any, ref: any, joinRef: any): void
  }

  export class Push {
    constructor(channel: Channel, event: string, payload: Record<string, any>, timeout: number)

    resend(timeout: number): void
    send(): void
    receive(status: string, callback: (response: any) => void): Push
  }

  export class Presence {
    static syncState(
      currentState: any,
      newState: any,
      onJoin?: (key: string, currentPresence: any, newPresence: any) => void,
      onLeave?: (key: string, currentPresence: any, leftPresence: any) => void
    ): any

    static syncDiff(
      state: any,
      diff: { joins: any; leaves: any },
      onJoin?: (key: string, currentPresence: any, newPresence: any) => void,
      onLeave?: (key: string, currentPresence: any, leftPresence: any) => void
    ): any

    static list(presences: any, chooser?: (key: string, presence: any) => any): any[]
  }

  export class LongPoll {
    constructor(endPoint: string)
  }

  export const Serializer: {
    encode(msg: any, callback: (encoded: string) => void): void
    decode(rawPayload: string, callback: (decoded: any) => void): void
  }
}
