// Type definitions for Phoenix LiveView JavaScript client
// Based on phoenix_live_view v1.0+

import { Socket, Channel } from "phoenix"

declare module "phoenix_live_view" {
  export interface ViewHookInterface {
    el?: HTMLElement
    pushEvent?(event: string, payload?: Record<string, any>, callback?: (reply: any, ref: any) => void): void
    pushEventTo?(selector: string, event: string, payload?: Record<string, any>, callback?: (reply: any, ref: any) => void): void
    handleEvent?(event: string, callback: (payload: any) => void): void
    upload?(name: string, files: FileList | File[]): void
    uploadTo?(selector: string, name: string, files: FileList | File[]): void
    mounted?(): void
    beforeUpdate?(): void
    updated?(): void
    destroyed?(): void
    disconnected?(): void
    reconnected?(): void
  }

  export type ViewHook = ViewHookInterface

  export interface LiveSocketOptions {
    params?: Record<string, any> | (() => Record<string, any>)
    hooks?: Record<string, ViewHookInterface>
    uploaders?: Record<string, any>
    dom?: {
      onBeforeElUpdated?: (from: HTMLElement, to: HTMLElement) => boolean
    }
    metadata?: {
      click?: (event: MouseEvent, element: HTMLElement) => Record<string, any>
      keydown?: (event: KeyboardEvent, element: HTMLElement) => Record<string, any>
    }
    sessionStorage?: Storage
    localStorage?: Storage
    longPollFallbackMs?: number
    timeout?: number
    heartbeatIntervalMs?: number
    reconnectAfterMs?: (tries: number) => number
    rejoinAfterMs?: (tries: number) => number
    viewLogger?: (view: any, kind: string, msg: string, obj: any) => void
    maxReloads?: number
    reloadJitterMin?: number
    reloadJitterMax?: number
    reloadWindowMin?: number
    reloadWindowMax?: number
  }

  export interface LiveSocketInstanceInterface {
    connect(): void
    disconnect(callback?: () => void): void
    enableDebug(): void
    enableLatencySim(upperBoundMs: number): void
    disableLatencySim(): void
    getLatencySim(): number | null
    enableProfiling(): void
    disableProfiling(): void
    getSocket(): Socket
    time(name: string, func: () => void): any
    log(view: any, kind: string, msgCallback: (view: any) => string): void
    requestDOMUpdate(callback: () => void): void
    transition(time: number, onStart?: () => void, onDone?: () => void): void
    main(): HTMLElement | null
    channel(topic: string, params?: Record<string, any>): Channel
    replaceMain(html: string, streams?: any, targetCID?: number): void
    historyPatch(href: string, kind: "push" | "replace", targetCID?: number): void
    historyRedirect(href: string, kind: "push" | "replace", flash?: any): void
    withPageLoading(info: { to?: string; kind?: string }, func: () => void): void
    bindTopLevelEvents(opts?: any): void
    isConnected(): boolean
    getBindingPrefix(): string
    binding(kind: string): string
    root(el?: HTMLElement): any
  }

  export class LiveSocket implements LiveSocketInstanceInterface {
    constructor(url: string, phxSocket: typeof Socket, opts?: LiveSocketOptions)

    connect(): void
    disconnect(callback?: () => void): void
    enableDebug(): void
    enableLatencySim(upperBoundMs: number): void
    disableLatencySim(): void
    getLatencySim(): number | null
    enableProfiling(): void
    disableProfiling(): void
    getSocket(): Socket
    time(name: string, func: () => void): any
    log(view: any, kind: string, msgCallback: (view: any) => string): void
    requestDOMUpdate(callback: () => void): void
    transition(time: number, onStart?: () => void, onDone?: () => void): void
    main(): HTMLElement | null
    channel(topic: string, params?: Record<string, any>): Channel
    replaceMain(html: string, streams?: any, targetCID?: number): void
    historyPatch(href: string, kind: "push" | "replace", targetCID?: number): void
    historyRedirect(href: string, kind: "push" | "replace", flash?: any): void
    withPageLoading(info: { to?: string; kind?: string }, func: () => void): void
    bindTopLevelEvents(opts?: any): void
    isConnected(): boolean
    getBindingPrefix(): string
    binding(kind: string): string
    root(el?: HTMLElement): any
  }

  export function createHook(callbacks: ViewHookInterface): ViewHookInterface

  export function isUsedInput(el: HTMLElement): boolean

  export type { LiveSocketInstanceInterface }
}
