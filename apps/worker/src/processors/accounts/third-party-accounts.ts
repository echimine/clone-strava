import { Inject, Injectable } from "@nestjs/common";
import {
  ACCOUNTS_PROCESSOR_OPTIONS,
  POSTHOG_EU_API_HOST,
  REVENUECAT_API_HOST,
  type AccountsProcessorOptions,
} from "./accounts.constants.js";

/** What a cleanup step did: `skipped` without its keys, `not_found` when already gone. */
export type CleanupOutcome = "deleted" | "not_found" | "skipped";

/**
 * The deleted account's traces at RevenueCat and PostHog (ADR-038 §13), both keyed on the user id
 * (RevenueCat's app user id, PostHog's `distinct_id`). Any unexpected answer throws, so the job
 * is retried; an answer meaning « already gone » is a success.
 */
@Injectable()
export class ThirdPartyAccounts {
  private readonly fetch: typeof fetch;

  constructor(@Inject(ACCOUNTS_PROCESSOR_OPTIONS) private readonly options: AccountsProcessorOptions) {
    this.fetch = options.fetch ?? globalThis.fetch;
  }

  /**
   * `DELETE /v2/projects/{project}/customers/{userId}`: asynchronous on RevenueCat's side, and it
   * does not cancel the Apple subscription. `404` = already deleted.
   */
  async deleteRevenueCatCustomer(userId: string): Promise<CleanupOutcome> {
    const { apiKey, projectId } = this.options.revenueCat;
    if (!apiKey || !projectId) {
      return "skipped";
    }
    const url = `${REVENUECAT_API_HOST}/v2/projects/${encodeURIComponent(projectId)}/customers/${encodeURIComponent(userId)}`;
    const response = await this.fetch(url, { method: "DELETE", headers: { authorization: `Bearer ${apiKey}` } });
    if (response.status === 404) {
      return "not_found";
    }
    if (!response.ok) {
      throw new Error(`RevenueCat customer deletion answered ${response.status}`);
    }
    return "deleted";
  }

  /**
   * `POST /api/projects/{project}/persons/bulk_delete/` by `distinct_id`, with the person's events.
   * Queued on PostHog's side (`202`); a person never seen is `not_found`. Errors are reported in
   * `deletion_errors`, not by the status: any of them fails the step.
   */
  async deletePostHogPerson(userId: string): Promise<CleanupOutcome> {
    const { personalApiKey, projectId, host = POSTHOG_EU_API_HOST } = this.options.postHog;
    if (!personalApiKey || !projectId) {
      return "skipped";
    }
    const url = `${host.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectId)}/persons/bulk_delete/`;
    const response = await this.fetch(url, {
      method: "POST",
      headers: { authorization: `Bearer ${personalApiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ distinct_ids: [userId], delete_events: true }),
    });
    if (!response.ok) {
      throw new Error(`PostHog person deletion answered ${response.status}`);
    }
    const body = (await response.json().catch(() => ({}))) as {
      persons_found?: number;
      deletion_errors?: unknown[];
    };
    if (Array.isArray(body.deletion_errors) && body.deletion_errors.length > 0) {
      throw new Error(`PostHog person deletion failed: ${JSON.stringify(body.deletion_errors)}`);
    }
    return body.persons_found === 0 ? "not_found" : "deleted";
  }
}
