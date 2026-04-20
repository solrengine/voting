import { Controller } from "@hotwired/stimulus"
import {
  findWalletByAddress,
  buildProgramInstruction,
  compileTransactionMessage,
  toWireBytes,
  signAndSend,
  explorerUrl,
  getCsrfToken,
} from "@solrengine/wallet-utils"

const STATE = Object.freeze({
  IDLE:       "idle",
  CONNECTING: "connecting",
  PREPARING:  "preparing",
  SIGNING:    "signing",
  CONFIRMING: "confirming",
  SUCCESS:    "success",
  ERROR:      "error"
})

const CONFIRM_INTERVAL_MS = 1_000
const CONFIRM_TIMEOUT_MS  = 45_000

export default class extends Controller {
  static targets = ["status", "button"]
  static values = {
    candidate: String,
    walletAddress: String,
    chain: { type: String, default: "solana:devnet" },
    prepareUrl: { type: String, default: "/poll/vote" },
    confirmUrl: { type: String, default: "/poll/confirm" }
  }

  connect() {
    this._wallet = null
    this._account = null
    this._abort = null
    this._confirmTimer = null
    this._disconnected = false
    this._state = STATE.IDLE
  }

  disconnect() {
    this._disconnected = true
    this._abort?.abort()
    if (this._confirmTimer) clearTimeout(this._confirmTimer)
  }

  async vote(event) {
    event?.preventDefault()

    // Page-level lock: one in-flight vote across all voting controller
    // instances. Survives cross-<li> double-clicks.
    if (window.__votingInFlight) {
      this.#setState(STATE.ERROR, "Another vote is still being submitted.")
      return
    }
    window.__votingInFlight = true

    try {
      await this.#runVoteFlow()
    } catch (error) {
      if (this._disconnected) return
      this.#setState(STATE.ERROR, this.#friendlyError(error))
    } finally {
      // Only clear the page-level lock on terminal states. While confirming,
      // we keep it held — the reload-after-confirm drops it via page unload.
      if (this._state !== STATE.CONFIRMING && this._state !== STATE.SUCCESS) {
        window.__votingInFlight = false
      }
    }
  }

  // --- internals ---

  async #runVoteFlow() {
    this.#setState(STATE.CONNECTING, "Connecting wallet…")
    await this.#ensureWallet()
    if (this._disconnected) return

    let signature
    try {
      signature = await this.#prepareSignAndSend()
    } catch (error) {
      // Stale-blockhash auto-retry once: fetch a fresh prepare and try again.
      // The wallet popup re-opens, but the user only sees one retry.
      if (this.#isStaleBlockhashError(error)) {
        this.#setState(STATE.PREPARING, "Refreshing transaction…")
        signature = await this.#prepareSignAndSend()
      } else {
        throw error
      }
    }
    if (this._disconnected) return

    this.#setState(STATE.CONFIRMING, "Confirming on-chain…")
    this.#appendExplorerLink(signature)
    await this.#pollConfirmation(signature)
    if (this._disconnected) return

    this.#setState(STATE.SUCCESS, "Vote confirmed!")
    // Small grace so the user reads the success before the reload.
    this._confirmTimer = setTimeout(() => {
      if (this._disconnected) return
      window.__votingInFlight = false
      if (window.Turbo) window.Turbo.visit(window.location.href, { action: "replace" })
      else window.location.reload()
    }, 1200)
  }

  async #ensureWallet() {
    // Always re-query the wallet standard. The adapter caches internally,
    // so this is cheap when nothing changed, and it picks up an account
    // switch the user did in their extension UI since last click.
    const { wallet, account } = await findWalletByAddress(this.walletAddressValue)
    this._wallet = wallet
    this._account = account
  }

  async #prepareSignAndSend() {
    this.#setState(STATE.PREPARING, "Preparing transaction…")
    this._abort = new AbortController()

    const response = await fetch(this.prepareUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": getCsrfToken()
      },
      body: JSON.stringify({ candidate: this.candidateValue }),
      signal: this._abort.signal
    })

    if (!response.ok) {
      const err = await response.json().catch(() => ({}))
      const message = err.error || `Server error (${response.status})`
      const e = new Error(message)
      e.code = err.code
      throw e
    }

    const { program_id, accounts, instruction_data, blockhash, last_valid_block_height } = await response.json()

    const instruction = buildProgramInstruction({
      programId: program_id,
      instructionData: instruction_data,
      accounts
    })
    const compiled = compileTransactionMessage({
      feePayer: this._account.address,
      blockhash,
      lastValidBlockHeight: last_valid_block_height,
      instruction,
      version: "legacy"
    })

    this.#setState(STATE.SIGNING, "Approve in wallet…")
    const txBytes = toWireBytes(compiled)
    return await signAndSend({
      wallet: this._wallet,
      account: this._account,
      transaction: txBytes,
      chain: this.chainValue
    })
  }

  async #pollConfirmation(signature) {
    const startedAt = Date.now()
    while (Date.now() - startedAt < CONFIRM_TIMEOUT_MS) {
      if (this._disconnected) return

      const response = await fetch(`${this.confirmUrlValue}/${encodeURIComponent(signature)}`, {
        headers: { "Accept": "application/json" }
      })
      if (response.ok) {
        const { confirmation_status, err } = await response.json()
        if (err) {
          const e = new Error(typeof err === "string" ? err : JSON.stringify(err))
          e.code = "transaction_failed"
          throw e
        }
        if (confirmation_status === "confirmed" || confirmation_status === "finalized") {
          return
        }
      }
      await this.#sleep(CONFIRM_INTERVAL_MS)
    }
    const e = new Error("Confirmation timed out after 45s. The transaction may still land — refresh the page to check.")
    e.code = "confirmation_timeout"
    throw e
  }

  #sleep(ms) {
    return new Promise((resolve) => { this._confirmTimer = setTimeout(resolve, ms) })
  }

  #setState(state, message) {
    this._state = state
    const tone = {
      [STATE.IDLE]:       null,
      [STATE.CONNECTING]: "pending",
      [STATE.PREPARING]:  "pending",
      [STATE.SIGNING]:    "pending",
      [STATE.CONFIRMING]: "pending",
      [STATE.SUCCESS]:    "success",
      [STATE.ERROR]:      "error"
    }[state]
    this.#renderStatus(message, tone)
    this.#renderBusy(state !== STATE.IDLE && state !== STATE.ERROR)
  }

  #renderStatus(message, type) {
    if (!this.hasStatusTarget) return
    const colors = {
      pending: "text-gray-500 dark:text-gray-400",
      success: "text-green-600 dark:text-green-400",
      error:   "text-red-600 dark:text-red-400"
    }
    this.statusTarget.className = `text-sm mt-2 ${colors[type] || ""}`
    this.statusTarget.textContent = message || ""
  }

  #renderBusy(busy) {
    if (!this.hasButtonTarget) return
    this.buttonTarget.disabled = busy
    this.buttonTarget.classList.toggle("opacity-50", busy)
    this.buttonTarget.classList.toggle("cursor-not-allowed", busy)
  }

  #appendExplorerLink(signature) {
    if (!this.hasStatusTarget) return
    const link = document.createElement("a")
    link.href = explorerUrl(signature, this.chainValue)
    link.target = "_blank"
    link.rel = "noopener"
    link.className = "underline ml-1"
    link.textContent = "View ↗"
    this.statusTarget.appendChild(link)
  }

  #isStaleBlockhashError(error) {
    const msg = error?.message || String(error)
    return /BlockhashNotFound|block height exceeded|blockhash.*expired/i.test(msg)
  }

  #friendlyError(error) {
    const msg = error?.message || String(error)
    if (/User rejected|rejected the request/i.test(msg)) return "You cancelled the signature."
    if (error?.code === "not_open" || /VotingEnded/i.test(msg)) return "Voting has ended."
    if (error?.code === "not_started" || /VotingNotStarted/i.test(msg)) return "Voting hasn't started yet."
    if (error?.code === "unknown_candidate") return "That candidate is no longer in the list."
    if (error?.code === "confirmation_timeout") return msg
    if (this.#isStaleBlockhashError(error)) return "Transaction took too long to confirm. Please try again."
    return msg
  }
}
