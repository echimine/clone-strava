import {
  BadGatewayException,
  Inject,
  Injectable,
  Logger,
  Optional,
  ServiceUnavailableException,
} from "@nestjs/common";
import {
  ADMIN_PREMIUM_ERROR_CODES,
  revenueCatCustomerSchema,
  revenueCatSubscriptionListSchema,
  type RevenueCatCustomer,
  type RevenueCatSubscription,
} from "@repo/contracts";
import { REVENUECAT_OPTIONS, type RevenueCatOptions } from "../revenuecat.constants.js";

const API_ORIGIN = "https://api.revenuecat.com";
const DASHBOARD_ORIGIN = "https://app.revenuecat.com";
/** Subscriptions read per page, and pages at most: far more than an athlete ever has. */
const PAGE_SIZE = 100;
const MAX_PAGES = 5;

interface Configured {
  apiKey: string;
  projectId: string;
  premiumEntitlementId: string;
}

/**
 * RevenueCat's REST API v2 (ADR-038 §12), the only place calling it. The customer id is our user
 * id (the app's `app_user_id`). v1 is never called: its read creates the customer.
 *
 * Without the configuration every call answers `503 revenuecat_not_configured`; a RevenueCat
 * failure answers `502 revenuecat_unavailable` (the worker retries the job).
 */
@Injectable()
export class RevenueCatClient {
  private readonly logger = new Logger(RevenueCatClient.name);
  private readonly settings: Configured | null;
  private readonly fetch: typeof fetch;

  constructor(@Optional() @Inject(REVENUECAT_OPTIONS) private readonly options?: RevenueCatOptions) {
    const { apiKey, projectId, premiumEntitlementId } = options ?? {};
    this.settings = apiKey && projectId && premiumEntitlementId ? { apiKey, projectId, premiumEntitlementId } : null;
    this.fetch = options?.fetch ?? fetch;
  }

  get configured(): boolean {
    return this.settings !== null;
  }

  /** `503 revenuecat_not_configured` without the configuration. */
  assertConfigured(): void {
    this.require();
  }

  /** RevenueCat's id of the `premium` entitlement. */
  get premiumEntitlementId(): string {
    return this.require().premiumEntitlementId;
  }

  /** The customer in the RevenueCat dashboard: needs the project id only. */
  dashboardUrl(customerId: string): string | null {
    const projectId = this.options?.projectId;
    return projectId
      ? `${DASHBOARD_ORIGIN}/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(customerId)}`
      : null;
  }

  /** `GET …/customers/{id}`; null when RevenueCat has no such customer. */
  async getCustomer(customerId: string): Promise<RevenueCatCustomer | null> {
    const response = await this.call("GET", this.customerPath(customerId));
    if (response.status === 404) {
      return null;
    }
    return revenueCatCustomerSchema.parse(await this.ok(response));
  }

  /** `GET …/customers/{id}/subscriptions`, every page; none for an unknown customer. */
  async listSubscriptions(customerId: string): Promise<RevenueCatSubscription[]> {
    const items: RevenueCatSubscription[] = [];
    let path: string | null = `${this.customerPath(customerId)}/subscriptions?limit=${PAGE_SIZE}`;
    for (let page = 0; path && page < MAX_PAGES; page += 1) {
      const response = await this.call("GET", path);
      if (response.status === 404) {
        return items;
      }
      const list = revenueCatSubscriptionListSchema.parse(await this.ok(response));
      items.push(...list.items);
      path = list.next_page ?? null;
    }
    return items;
  }

  /**
   * `actions/grant_entitlement` until `expiresAt`: a Promotional Premium. An account that never
   * opened the app has no customer yet: it is created first.
   */
  async grantPremium(customerId: string, expiresAt: Date): Promise<void> {
    const body = { entitlement_id: this.premiumEntitlementId, expires_at: expiresAt.getTime() };
    let response = await this.call("POST", `${this.customerPath(customerId)}/actions/grant_entitlement`, body);
    if (response.status === 404) {
      const created = await this.call("POST", `/v2/projects/${this.projectPath()}/customers`, { id: customerId });
      if (created.status !== 409) {
        await this.ok(created);
      }
      response = await this.call("POST", `${this.customerPath(customerId)}/actions/grant_entitlement`, body);
    }
    await this.ok(response);
  }

  /**
   * `actions/revoke_granted_entitlement`: removes the Promotional Premium at once, never an App
   * Store subscription. Nothing to revoke (no customer, no grant) is not an error.
   */
  async revokePremium(customerId: string): Promise<void> {
    const response = await this.call("POST", `${this.customerPath(customerId)}/actions/revoke_granted_entitlement`, {
      entitlement_id: this.premiumEntitlementId,
    });
    if (response.status === 404) {
      return;
    }
    await this.ok(response);
  }

  /**
   * Account deletion (ADR-038 §13): `DELETE …/customers/{id}`, asynchronous on RevenueCat's side;
   * it does not cancel the Apple subscription. Needs the key and the project only (not the
   * entitlement): `skipped` without them, `not_found` when RevenueCat has no such customer.
   */
  async deleteCustomer(customerId: string): Promise<"deleted" | "not_found" | "skipped"> {
    const { apiKey, projectId } = this.options ?? {};
    if (!apiKey || !projectId) {
      return "skipped";
    }
    const path = `/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(customerId)}`;
    const response = await this.send(apiKey, "DELETE", path);
    if (response.status === 404) {
      return "not_found";
    }
    await this.ok(response);
    return "deleted";
  }

  private customerPath(customerId: string): string {
    return `/v2/projects/${this.projectPath()}/customers/${encodeURIComponent(customerId)}`;
  }

  private projectPath(): string {
    return encodeURIComponent(this.require().projectId);
  }

  private require(): Configured {
    if (!this.settings) {
      throw new ServiceUnavailableException({
        code: ADMIN_PREMIUM_ERROR_CODES.notConfigured,
        message: "RevenueCat non configuré",
      });
    }
    return this.settings;
  }

  private call(method: "GET" | "POST", path: string, body?: unknown): Promise<Response> {
    return this.send(this.require().apiKey, method, path, body);
  }

  private async send(apiKey: string, method: "GET" | "POST" | "DELETE", path: string, body?: unknown): Promise<Response> {
    try {
      return await this.fetch(`${API_ORIGIN}${path}`, {
        method,
        headers: {
          authorization: `Bearer ${apiKey}`,
          accept: "application/json",
          ...(body === undefined ? {} : { "content-type": "application/json" }),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(10_000),
      });
    } catch (error) {
      this.logger.warn({ err: error, method, path }, "RevenueCat unreachable");
      throw unavailable();
    }
  }

  /** The JSON body of a 2xx answer; any other status is RevenueCat failing or refusing. */
  private async ok(response: Response): Promise<unknown> {
    if (!response.ok) {
      this.logger.warn({ status: response.status, body: await response.text().catch(() => "") }, "RevenueCat refused");
      throw unavailable();
    }
    return response.status === 204 ? undefined : response.json();
  }
}

function unavailable(): BadGatewayException {
  return new BadGatewayException({
    code: ADMIN_PREMIUM_ERROR_CODES.unavailable,
    message: "RevenueCat n'a pas répondu, réessayez plus tard",
  });
}
